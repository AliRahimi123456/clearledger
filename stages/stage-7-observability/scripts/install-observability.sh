#!/usr/bin/env bash
# Stage 7 — Observability installer (idempotent, MicroK8s-tolerant)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_DIR="${STAGE_DIR}/infra/helm"
FORCE="${FORCE:-0}"
HELM_RETRIES="${HELM_RETRIES:-3}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "✗ Missing dependency: $1"
    exit 1
  }
}

helm_retry() {
  local attempt=1
  while [ "${attempt}" -le "${HELM_RETRIES}" ]; do
    if "$@"; then
      return 0
    fi
    echo "  ⚠ Helm attempt ${attempt}/${HELM_RETRIES} failed — retrying in 15s..."
    sleep 15
    attempt=$((attempt + 1))
  done
  echo "✗ Helm failed after ${HELM_RETRIES} attempts: $*"
  return 1
}

stack_installed() {
  helm status kube-prometheus-stack -n monitoring >/dev/null 2>&1
}

loki_installed() {
  helm status loki -n monitoring >/dev/null 2>&1
}

loki_restart_count() {
  kubectl get pod -n monitoring loki-0 -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "999"
}

loki_ready_in_pod() {
  kubectl exec -n monitoring loki-0 -- wget -qO- --timeout=3 http://127.0.0.1:3100/ready 2>/dev/null | grep -q ready
}

loki_ready_from_grafana() {
  kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
    wget -qO- --timeout=5 http://loki:3100/ready 2>/dev/null | grep -q ready
}

monitoring_ready() {
  local restarts
  kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null \
    | awk '{print $2}' | grep -q '3/3' || return 1
  kubectl get pods -n monitoring loki-0 --no-headers 2>/dev/null \
    | awk '{print $2}' | grep -q '1/1' || return 1
  restarts="$(loki_restart_count)"
  [ "${restarts:-999}" -le 3 ] || return 1
  loki_ready_from_grafana
}

wait_loki() {
  echo "▶ Waiting for Loki (pod + Service path from Grafana)..."
  local i=0 ok=0
  while [ "${i}" -lt 90 ]; do
    if loki_ready_in_pod && loki_ready_from_grafana; then
      ok=$((ok + 1))
      if [ "${ok}" -ge 3 ]; then
        echo "  ✓ Loki ready (stable 3×)"
        return 0
      fi
    else
      ok=0
    fi
    sleep 2
    i=$((i + 1))
  done
  echo "✗ Loki not ready after 180s — check:"
  echo "  kubectl describe pod -n monitoring loki-0 | grep -E 'Restart|Unhealthy'"
  echo "  kubectl logs -n monitoring loki-0 --tail=50"
  return 1
}

purge_stale_grafana_dashboards() {
  echo "▶ Removing stale ClearLedger dashboards from Grafana (fixes slug / em-dash URLs)..."
  kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- sh -c '
    for uid in clearledger-security-events clearledger-kyverno clearledger-kyverno-violations \
      clearledger-service-health clearledger-compliance clearledger-audit-logs clearledger-dora clearledger-dora-metrics; do
      wget -qO- --method=DELETE --header="Content-Type: application/json" \
        --http-user=admin --http-password=admin123 \
        "http://127.0.0.1:3000/api/dashboards/uid/${uid}" >/dev/null 2>&1 || true
    done
  ' || true
  kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring >/dev/null 2>&1 || true
  kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=300s
}

apply_clearledger_dashboards() {
  echo "▶ Provisioning ClearLedger dashboards (sidecar label: clearledger_dashboard=1)..."
  for f in "${STAGE_DIR}"/infra/dashboards/*.json; do
    base="$(basename "$f" .json)"
    cm="grafana-dashboard-${base}"
    kubectl -n monitoring create configmap "$cm" \
      --from-file="${base}.json=${f}" \
      -o yaml --dry-run=client | \
    kubectl label --local -f - clearledger_dashboard=1 -o yaml | \
    kubectl apply -f -
  done
}

install_loki_helm() {
  echo "▶ Installing Loki (logs)..."
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  local default_sc loki_values=(-f "${HELM_DIR}/loki-stack-values.yaml")
  default_sc="$(kubectl get storageclass 2>/dev/null | awk '$2=="(default)" {print $1; exit}' || true)"
  if [ -n "${default_sc:-}" ]; then
    loki_values+=(--set loki.persistence.enabled=true --set loki.persistence.size=5Gi)
  else
    echo "  ⚠ No default StorageClass — Loki runs without persistence (lab)"
  fi

  if helm_retry helm upgrade --install loki grafana/loki-stack \
    --namespace monitoring \
    "${loki_values[@]}" \
    --timeout 15m \
    --wait; then
    return 0
  fi
  if kubectl get pods -n monitoring loki-0 --no-headers 2>/dev/null | awk '{print $2}' | grep -q '1/1'; then
    echo "  ⚠ Loki Helm failed but loki-0 is running — continuing"
    return 0
  fi
  return 1
}

grafana_ready() {
  kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null \
    | awk '{print $2}' | grep -q '3/3'
}

require kubectl
require helm

if [ "${FORCE}" != "1" ] && monitoring_ready; then
  echo "▶ Observability stack already healthy — skipping Helm."
  echo "  Applying manifests + dashboards only. (FORCE=1 to re-run all Helm upgrades)"
elif [ "${FORCE}" != "1" ] && grafana_ready && ! loki_ready_from_grafana; then
  echo "▶ Grafana is up but Loki is not reachable — upgrading Loki only..."
  install_loki_helm || exit 1
else
  echo "▶ Installing Prometheus + Grafana (kube-prometheus-stack)..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  if helm_retry helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    -f "${HELM_DIR}/kube-prometheus-stack-values.yaml" \
    --timeout 15m \
    --wait; then
    :
  elif monitoring_ready; then
    echo "  ⚠ Helm upgrade failed but Grafana is up — continuing with manifests/dashboards only"
  else
    exit 1
  fi

  install_loki_helm || exit 1
fi

wait_loki

echo "▶ Applying Loki datasource + ServiceMonitors + PrometheusRule..."
kubectl apply -f "${STAGE_DIR}/infra/monitoring/loki-datasource.yaml"
kubectl apply -f "${STAGE_DIR}/infra/monitoring/argocd-servicemonitor.yaml"
kubectl apply -f "${STAGE_DIR}/infra/monitoring/falco-servicemonitor.yaml"
kubectl apply -f "${STAGE_DIR}/infra/monitoring/kyverno-servicemonitor.yaml"
kubectl apply -f "${STAGE_DIR}/infra/monitoring/clearledger-podmonitor.yaml"
kubectl apply -f "${STAGE_DIR}/infra/monitoring/alerting-rules.yaml"

echo "▶ Ensuring Falco metrics Service exists..."
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm_retry helm upgrade --install falco falcosecurity/falco -n falco \
  -f "${ROOT_DIR}/stages/stage-6-runtime-security/infra/falco/helm-values.yaml" \
  --timeout 5m
echo "  Waiting for Falco DaemonSet (up to 3m)..."
kubectl rollout status daemonset/falco -n falco --timeout=180s 2>/dev/null || \
  echo "  ⚠ Falco not fully ready — Security Timeline needs 2/2 falco pods; check: kubectl get pods -n falco"

apply_clearledger_dashboards
purge_stale_grafana_dashboards

echo "▶ Waiting for Grafana (all containers)..."
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=300s

GRAFANA_POD="$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana \
  --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || true)"
READY="$(kubectl get pod -n monitoring "${GRAFANA_POD:-none}" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null \
  | tr ' ' '\n' | grep -c true || true)"
if [ -z "${GRAFANA_POD:-}" ] || [ "${READY:-0}" -lt 3 ]; then
  echo "✗ Grafana pod not fully ready (expected 3/3). Check:"
  echo "  kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana"
  echo "  kubectl describe pod -n monitoring ${GRAFANA_POD:-<grafana-pod>}"
  exit 1
fi

echo ""
echo "✓ Stage 7 installed."
echo "  Grafana: http://grafana.local (admin / admin123)"
echo "  Dashboards: http://grafana.local/dashboards?tag=clearledger"
echo "  Metrics images (optional): bash ${STAGE_DIR}/scripts/build-metrics-images.sh"
echo "  Generate data: bash ${STAGE_DIR}/scripts/generate-dashboard-data.sh"
echo "  Health check: bash ${ROOT_DIR}/scripts/health-check.sh 7"
