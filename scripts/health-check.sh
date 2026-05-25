#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ClearLedger Stage Health Check
# PURPOSE: Verify each stage is working correctly before moving to the next.
#          Run this after completing a stage. Green = ready to proceed.
#          Red = something is broken — fix it before continuing.
#
# Usage:
#   bash scripts/health-check.sh [stage-number]
#   bash scripts/health-check.sh 0    # verify Stage 0
#   bash scripts/health-check.sh 4    # verify Stage 4
#   bash scripts/health-check.sh all  # run all checks
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARN=$((WARN + 1)); }
header() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }

# ── Helper functions ──────────────────────────────────────────────────────────
pod_running() {
  local label=$1 namespace=${2:-clearledger}
  local count
  count=$(kubectl get pods -n "$namespace" -l "app=$label" \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
  [ "$count" -gt 0 ]
}

pod_ready() {
  local label=$1 namespace=${2:-clearledger}
  kubectl wait --for=condition=ready pod \
    -l "app=$label" -n "$namespace" --timeout=10s &>/dev/null
}

http_ok() {
  local url=$1
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$url" 2>/dev/null || echo "000")
  [ "$status" = "200" ] || [ "$status" = "201" ]
}

http_status() {
  curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$1" 2>/dev/null || echo "000"
}

# ── Stage 0: Raw Kubernetes ───────────────────────────────────────────────────
check_stage_0() {
  header "Stage 0 — Raw Kubernetes"

  # Cluster
  if kubectl get nodes &>/dev/null; then
    pass "kubectl can reach the cluster"
  else
    fail "kubectl cannot reach the cluster — run QUICKSTART.md first"
    return
  fi

  local node_status
  node_status=$(kubectl get nodes --no-headers | awk '{print $2}')
  if echo "$node_status" | grep -q "Ready"; then
    pass "Node is Ready"
  else
    fail "Node is not Ready: $node_status"
  fi

  # Namespace
  if kubectl get namespace clearledger &>/dev/null; then
    pass "clearledger namespace exists"
  else
    fail "clearledger namespace missing — run: kubectl apply -f infra/manifests/namespace.yaml"
  fi

  # RBAC — ServiceAccounts + least-privilege Roles (infra/manifests/rbac/rbac.yaml)
  for sa in auth-service ledger-service notification-service clearledger-viewer; do
    if kubectl get serviceaccount "$sa" -n clearledger &>/dev/null; then
      pass "ServiceAccount $sa exists"
    else
      fail "ServiceAccount $sa missing — kubectl apply -f infra/manifests/rbac/rbac.yaml"
    fi
  done

  local can_secrets_auth can_ep_auth can_pods_viewer can_secrets_viewer
  can_secrets_auth=$(kubectl auth can-i get secrets \
    --as=system:serviceaccount:clearledger:auth-service -n clearledger 2>/dev/null) || true
  if [[ "$can_secrets_auth" == "no" ]]; then
    pass "RBAC: auth-service cannot get Secrets"
  else
    fail "RBAC: auth-service should not get Secrets (got: $can_secrets_auth)"
  fi

  can_ep_auth=$(kubectl auth can-i get endpoints \
    --as=system:serviceaccount:clearledger:auth-service -n clearledger 2>/dev/null) || true
  if [[ "$can_ep_auth" == "yes" ]]; then
    pass "RBAC: auth-service can get Endpoints"
  else
    fail "RBAC: auth-service should get Endpoints (got: $can_ep_auth)"
  fi

  can_pods_viewer=$(kubectl auth can-i get pods \
    --as=system:serviceaccount:clearledger:clearledger-viewer -n clearledger 2>/dev/null) || true
  if [[ "$can_pods_viewer" == "yes" ]]; then
    pass "RBAC: clearledger-viewer can get Pods"
  else
    fail "RBAC: clearledger-viewer should get Pods (got: $can_pods_viewer)"
  fi

  can_secrets_viewer=$(kubectl auth can-i get secrets \
    --as=system:serviceaccount:clearledger:clearledger-viewer -n clearledger 2>/dev/null) || true
  if [[ "$can_secrets_viewer" == "no" ]]; then
    pass "RBAC: clearledger-viewer cannot get Secrets"
  else
    fail "RBAC: clearledger-viewer must not get Secrets (got: $can_secrets_viewer)"
  fi

  local vault_auth automount_expected automount_actual
  for deploy in auth-service ledger-service notification-service; do
    vault_auth=$(kubectl get deploy "$deploy" -n clearledger \
      -o jsonpath='{.spec.template.metadata.annotations.vault\.hashicorp\.com/agent-inject}' 2>/dev/null || true)
    if [[ "$vault_auth" == "true" ]]; then
      automount_expected="true"
    else
      automount_expected="false"
    fi
    automount_actual=$(kubectl get deploy "$deploy" -n clearledger \
      -o jsonpath='{.spec.template.spec.automountServiceAccountToken}' 2>/dev/null || echo "")
    if [[ "$automount_actual" == "$automount_expected" ]]; then
      pass "Deployment $deploy automountServiceAccountToken=$automount_actual (expected for Vault=$vault_auth)"
    else
      fail "Deployment $deploy automountServiceAccountToken=$automount_actual (expected $automount_expected when vault inject=$vault_auth)"
    fi
  done

  # Infrastructure pods
  for svc in postgres redis; do
    if pod_running "$svc"; then
      pass "$svc is running"
    else
      fail "$svc is not running"
    fi
  done

  # Application pods
  for svc in auth-service ledger-service notification-service frontend; do
    if pod_running "$svc"; then
      pass "$svc is running"
    else
      fail "$svc is not running"
    fi
  done

  # Ingress
  if kubectl get ingress clearledger-api -n clearledger &>/dev/null; then
    pass "API Ingress exists"
  else
    fail "API Ingress missing — run: kubectl apply -f infra/manifests/ingress.yaml"
  fi

  if kubectl get ingress clearledger-frontend -n clearledger &>/dev/null; then
    pass "Frontend Ingress exists"
  else
    fail "Frontend Ingress missing — run: kubectl apply -f infra/manifests/ingress.yaml"
  fi

  # /etc/hosts
  if grep -q "clearledger.local" /etc/hosts 2>/dev/null; then
    pass "clearledger.local in /etc/hosts"
  else
    warn "/etc/hosts entry missing — run scripts/setup-hosts.sh"
  fi

  # API health checks
  if http_ok "http://clearledger.local/auth/health"; then
    pass "auth-service /health responds 200"
  else
    fail "auth-service /health not reachable at http://clearledger.local/auth/health"
  fi

  if http_ok "http://clearledger.local/ledger/health"; then
    pass "ledger-service /health responds 200"
  else
    fail "ledger-service /health not reachable"
  fi

  if http_ok "http://clearledger.local/notifications/health"; then
    pass "notification-service /health responds 200"
  else
    fail "notification-service /health not reachable"
  fi

  if curl -sf "http://clearledger.local/" 2>/dev/null | grep -q "ClearLedger"; then
    pass "frontend UI served at http://clearledger.local/"
  else
    fail "frontend UI not reachable at http://clearledger.local/"
  fi

  # End-to-end smoke test
  local reg_status
  reg_status=$(http_status "http://clearledger.local/auth/register" || echo "000")
  # 405 = method not allowed (GET on a POST endpoint) = service is up
  if [ "$reg_status" = "405" ] || [ "$reg_status" = "422" ]; then
    pass "auth-service /register endpoint responds (end-to-end routing works)"
  elif [ "$reg_status" = "200" ] || [ "$reg_status" = "201" ]; then
    pass "auth-service /register responds"
  else
    fail "auth-service /register not reachable (status: $reg_status)"
  fi
}

# ── Stage 1: CI Pipeline ──────────────────────────────────────────────────────
check_stage_1() {
  header "Stage 1 — CI Pipeline (GitHub Actions + Self-Hosted Runner)"

  # GitHub Actions self-hosted runner inside VM
  local runner_status
  runner_status=$(multipass exec clearledger -- \
    sudo systemctl is-active actions.runner.*.service 2>/dev/null || echo "inactive")

  if [ "$runner_status" = "active" ]; then
    pass "GitHub Actions self-hosted runner is active"
  else
    fail "GitHub Actions runner is not running inside the VM.
    Fix: multipass exec clearledger -- sudo systemctl start actions.runner.*.service
    Setup: see stages/stage-1-ci-pipeline/README.md section 2"
  fi

  # Remind the learner what to verify on GitHub (cannot check these from the host)
  echo ""
  echo "  Verify on GitHub:"
  echo "    Infra repo: github.com/YOUR_USERNAME/clearledger-infra (must exist)"
  echo "    Secrets:    github.com/YOUR_USERNAME/clearledger/settings/secrets/actions"
  echo "    Required:   DOCKER_USERNAME, DOCKER_PASSWORD, INFRA_REPO_TOKEN"
  echo "    Runner:     github.com/YOUR_USERNAME/clearledger → Settings → Actions → Runners"
}

# ── Stage 2: GitOps / ArgoCD ──────────────────────────────────────────────────
check_stage_2() {
  header "Stage 2 — GitOps (ArgoCD)"

  if pod_running "argocd-server" "argocd"; then
    pass "ArgoCD server is running"
  else
    fail "ArgoCD not running — install from stable manifest"
  fi

  # ArgoCD application exists
  if kubectl get application clearledger -n argocd &>/dev/null; then
    pass "ArgoCD Application 'clearledger' exists"

    local sync_status
    sync_status=$(kubectl get application clearledger -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    local health_status
    health_status=$(kubectl get application clearledger -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    if [ "$sync_status" = "Synced" ]; then
      pass "ArgoCD sync status: Synced"
    else
      warn "ArgoCD sync status: $sync_status (expected: Synced)"
    fi

    if [ "$health_status" = "Healthy" ]; then
      pass "ArgoCD health status: Healthy"
    else
      warn "ArgoCD health status: $health_status (expected: Healthy)"
    fi
  else
    fail "ArgoCD Application 'clearledger' not found — apply infra/argocd/clearledger-app.yaml"
  fi

  # Prove selfHeal is enabled
  local self_heal
  self_heal=$(kubectl get application clearledger -n argocd \
    -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null || echo "false")
  if [ "$self_heal" = "true" ]; then
    pass "selfHeal is enabled — cluster drift is auto-reverted"
  else
    warn "selfHeal is not enabled — manual kubectl changes will not be reverted"
  fi
}

# ── Stage 3: Security Gates ───────────────────────────────────────────────────
check_stage_3() {
  header "Stage 3 — Security Gates"

  # Check pipeline file exists and has security jobs
  if [ -f ".github/workflows/ci.yaml" ]; then
    pass ".github/workflows/ci.yaml exists"

    for gate in "gitleaks" "semgrep" "checkov" "trivy" "cosign"; do
      if grep -qi "$gate" .github/workflows/ci.yaml; then
        pass "Pipeline includes $gate"
      else
        fail "Pipeline missing $gate gate in .github/workflows/ci.yaml"
      fi
    done
  else
    fail "No CI pipeline file at .github/workflows/ci.yaml"
  fi

  # Pre-commit hooks
  if [ -f ".pre-commit-config.yaml" ]; then
    pass ".pre-commit-config.yaml exists"
    if command -v pre-commit &>/dev/null; then
      if pre-commit run --all-files --show-diff-on-failure &>/dev/null 2>&1; then
        pass "pre-commit hooks pass on current codebase"
      else
        warn "pre-commit hooks found issues — run: pre-commit run --all-files"
      fi
    else
      warn "pre-commit not installed on host — run: pip install pre-commit && pre-commit install"
    fi
  else
    warn ".pre-commit-config.yaml not found"
  fi

  # Cosign keys
  if [ -f "infra/cosign.pub" ]; then
    pass "cosign.pub exists in infra/"
  else
    warn "cosign.pub not found — generate with: cosign generate-key-pair"
  fi
}

# ── Stage 4: Kyverno ─────────────────────────────────────────────────────────
check_stage_4() {
  header "Stage 4 — Admission Control (Kyverno)"

  if pod_running "kyverno" "kyverno"; then
    pass "Kyverno is running"
  else
    fail "Kyverno not running — helm install kyverno kyverno/kyverno -n kyverno --create-namespace"
  fi

  # Policies
  local expected_policies=(
    "disallow-root-containers"
    "require-resource-limits"
    "require-signed-images"
    "disallow-privilege-escalation"
    "drop-all-capabilities"
  )

  for policy in "${expected_policies[@]}"; do
    if kubectl get clusterpolicy "$policy" &>/dev/null; then
      local action
      action=$(kubectl get clusterpolicy "$policy" \
        -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null)
      if [ "$action" = "Enforce" ]; then
        pass "Policy $policy — Enforce mode"
      else
        warn "Policy $policy exists but is in $action mode (expected: Enforce)"
      fi
    else
      fail "Policy $policy not found — apply infra/policies/$policy.yaml"
    fi
  done

  # Test that a root pod is rejected
  local test_result
  test_result=$(kubectl apply --dry-run=server -f - 2>&1 <<'TESTPOD' || true
apiVersion: v1
kind: Pod
metadata:
  name: health-check-root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
TESTPOD
)

  if echo "$test_result" | grep -qi "denied\|webhook"; then
    pass "Kyverno correctly rejects pods without securityContext"
  else
    warn "Kyverno dry-run did not reject root pod — policies may not be enforcing"
  fi

  # kube-bench CIS benchmark evidence (Stage 4)
  local baseline
  baseline="stages/stage-4-admission-control/scripts/kube-bench-baseline.json"
  if [ -f "$baseline" ]; then
    pass "kube-bench baseline exists ($baseline)"
  else
    fail "kube-bench baseline missing — expected $baseline"
    return
  fi

  if [ -x "stages/stage-4-admission-control/scripts/run-kube-bench.sh" ]; then
    if bash stages/stage-4-admission-control/scripts/run-kube-bench.sh >/dev/null 2>&1; then
      pass "kube-bench matches baseline (no new FAIL regressions)"
    else
      fail "kube-bench regressions detected — run: bash stages/stage-4-admission-control/scripts/run-kube-bench.sh"
    fi
  else
    warn "run-kube-bench.sh not executable — chmod +x stages/stage-4-admission-control/scripts/run-kube-bench.sh"
  fi
}

# ── Stage 5: Vault ────────────────────────────────────────────────────────────
check_stage_5() {
  header "Stage 5 — Secrets Management (Vault)"

  if pod_running "vault" "vault"; then
    pass "Vault pod is running"
  else
    fail "Vault not running — helm install vault hashicorp/vault ..."
  fi

  # Vault unsealed
  local vault_status
  vault_status=$(kubectl exec -n vault vault-0 -- \
    vault status -format=json 2>/dev/null | jq -r .sealed 2>/dev/null || echo "unknown")

  if [ "$vault_status" = "false" ]; then
    pass "Vault is unsealed"
  elif [ "$vault_status" = "true" ]; then
    fail "Vault is sealed — secrets cannot be injected. Unseal with: vault operator unseal"
  else
    warn "Could not determine Vault seal status"
  fi

  # K8s auth configured
  local k8s_auth
  k8s_auth=$(kubectl exec -n vault vault-0 -- \
    vault auth list -format=json 2>/dev/null | jq -r '.["kubernetes/"]' 2>/dev/null || echo "null")

  if [ "$k8s_auth" != "null" ] && [ -n "$k8s_auth" ]; then
    pass "Vault Kubernetes auth method is enabled"
  else
    fail "Vault Kubernetes auth not configured — see Stage 5 README Step 2"
  fi

  # K8s Secrets deleted (Stage 5 removes them)
  if kubectl get secret auth-service-secret -n clearledger &>/dev/null; then
    warn "auth-service-secret still exists as K8s Secret — Stage 5 not fully applied"
  else
    pass "auth-service-secret removed — Vault is the secret source"
  fi

  # Vault agent injected files
  local auth_pod
  auth_pod=$(kubectl get pod -n clearledger -l app=auth-service -o name | head -1)
  if [ -n "$auth_pod" ]; then
    if kubectl exec -n clearledger "$auth_pod" -c auth-service -- \
      test -f /vault/secrets/database_url 2>/dev/null; then
      pass "Vault injected /vault/secrets/database_url into auth-service"
    else
      fail "Vault secret file not found in auth-service pod — check Vault agent logs"
    fi
  fi
}

# ── Stage 6: Falco ────────────────────────────────────────────────────────────
check_stage_6() {
  header "Stage 6 — Runtime Security (Falco)"

  # Falco daemonset
  local falco_desired falco_ready
  falco_desired=$(kubectl get daemonset falco -n falco \
    -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
  falco_ready=$(kubectl get daemonset falco -n falco \
    -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

  if [ "$falco_desired" = "$falco_ready" ] && [ "$falco_ready" -gt 0 ]; then
    pass "Falco DaemonSet: $falco_ready/$falco_desired nodes"
  else
    fail "Falco DaemonSet not ready: $falco_ready/$falco_desired"
  fi

  # Custom rules loaded
  if kubectl get configmap clearledger-falco-rules -n falco &>/dev/null; then
    pass "ClearLedger custom Falco rules ConfigMap exists"
  else
    fail "Custom rules not loaded — apply infra/falco/clearledger-rules.yaml"
  fi

  # Network policies
  for policy in default-deny-all allow-auth-service allow-ledger-service allow-notification-service; do
    if kubectl get networkpolicy "$policy" -n clearledger &>/dev/null; then
      pass "NetworkPolicy $policy exists"
    else
      fail "NetworkPolicy $policy missing — apply infra/manifests/netpol/"
    fi
  done

  # Services still reachable after network policies applied
  if http_ok "http://clearledger.local/auth/health"; then
    pass "auth-service reachable after network policies"
  else
    fail "auth-service unreachable — network policy may be too restrictive"
  fi

  if http_ok "http://clearledger.local/notifications/health"; then
    pass "notification-service reachable after network policies"
  else
    fail "notification-service unreachable — check allow-notification-service policy"
  fi
}

# ── Stage 6.5: Chaos Engineering ─────────────────────────────────────────────
check_stage_65() {
  header "Stage 6.5 — Chaos Engineering (LitmusChaos)"

  if kubectl get namespace litmus &>/dev/null; then
    pass "litmus namespace exists"
  else
    fail "litmus namespace missing — install LitmusChaos (Stage 6.5 README)"
  fi

  if kubectl get serviceaccount litmus-admin -n clearledger &>/dev/null; then
    pass "litmus-admin ServiceAccount exists in clearledger"
  else
    fail "litmus-admin SA missing — apply stages/stage-6.5-chaos-engineering/infra/chaos/litmus-rbac.yaml"
  fi

  if kubectl get pods -n litmus --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | grep -q "."; then
    pass "LitmusChaos pods are running"
  else
    warn "No LitmusChaos pods running — helm install may be pending"
  fi

  if http_ok "http://clearledger.local/auth/health"; then
    pass "auth-service healthy (baseline before chaos)"
  else
    fail "auth-service not reachable — fix Stage 6 before chaos testing"
  fi
}

# ── Stage 7: Observability ────────────────────────────────────────────────────
check_stage_7() {
  header "Stage 7 — Observability (Grafana + Prometheus + Loki)"

  # Prometheus
  if kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus" \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q "."; then
    pass "Prometheus is running"
  else
    fail "Prometheus not running"
  fi

  # Grafana
  if http_ok "http://grafana.local"; then
    pass "Grafana reachable at http://grafana.local"
  else
    fail "Grafana not reachable — check ingress and /etc/hosts"
  fi

  # Loki
  if kubectl get pods -n monitoring -l "app=loki" \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q "."; then
    pass "Loki is running"
  else
    warn "Loki not running — log aggregation unavailable"
  fi

  # Alert rules
  if kubectl get prometheusrule clearledger-security-alerts -n monitoring &>/dev/null; then
    pass "ClearLedger alerting rules exist"
  else
    warn "Alerting rules not applied — apply stages/stage-7-observability/infra/monitoring/alerting-rules.yaml"
  fi

  # Dashboards imported
  local dashboard_count
  dashboard_count=$(curl -s \
    "http://admin:admin123@grafana.local/api/search?tag=clearledger" \
    2>/dev/null | jq length 2>/dev/null || echo "0")

  if [ "$dashboard_count" -ge 4 ]; then
    pass "ClearLedger dashboards imported ($dashboard_count found)"
  elif [ "$dashboard_count" -gt 0 ]; then
    warn "$dashboard_count ClearLedger dashboard(s) imported (expected 4)"
  else
    warn "No ClearLedger dashboards imported — import JSON files from stages/stage-7-observability/infra/dashboards/"
  fi
}

# ── Stage 7.5: OpenTelemetry ───────────────────────────────────────────────────
check_stage_75() {
  header "Stage 7.5 — OpenTelemetry (Distributed Tracing)"

  if kubectl get deployment otel-collector -n monitoring &>/dev/null; then
  local otel_ready
  otel_ready=$(kubectl get deployment otel-collector -n monitoring \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "${otel_ready:-0}" -ge 1 ]; then
      pass "OTel Collector is running ($otel_ready replica(s))"
    else
      fail "OTel Collector not ready — apply stages/stage-7.5-opentelemetry/infra/otel/"
    fi
  else
    fail "OTel Collector deployment missing — apply stages/stage-7.5-opentelemetry/infra/otel/"
  fi

  if kubectl get configmap grafana-datasource-tempo -n monitoring &>/dev/null; then
    pass "Grafana Tempo datasource ConfigMap exists"
  else
    warn "Tempo datasource ConfigMap missing — Grafana may not show Tempo"
  fi

  if kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q "."; then
    pass "Tempo is running"
  else
    warn "Tempo not running — install via helm (Stage 7.5 README)"
  fi

  if kubectl get deployment auth-service -n clearledger \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}' \
    2>/dev/null | grep -q otel-collector; then
    pass "auth-service has OTEL_EXPORTER_OTLP_ENDPOINT configured"
  else
    warn "OTel env vars not found on auth-service — redeploy with updated manifests"
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  echo -e "\n${BOLD}─────────────────────────────────────────${NC}"
  echo -e "${BOLD}Health Check Summary${NC}"
  echo -e "${GREEN}✓ Passed: $PASS${NC}"
  [ "$WARN" -gt 0 ] && echo -e "${YELLOW}⚠ Warnings: $WARN${NC}"
  [ "$FAIL" -gt 0 ] && echo -e "${RED}✗ Failed: $FAIL${NC}"
  echo -e "${BOLD}─────────────────────────────────────────${NC}"

  if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All checks passed. Ready for the next stage.${NC}"
  elif [ "$FAIL" -eq 0 ]; then
    echo -e "${YELLOW}${BOLD}Warnings present but no failures. Review warnings before proceeding.${NC}"
  else
    echo -e "${RED}${BOLD}Fix the failures above before moving to the next stage.${NC}"
    exit 1
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
STAGE=${1:-"help"}

echo -e "${BOLD}ClearLedger DevSecOps Lab — Health Check${NC}"
echo -e "Running checks for stage: ${CYAN}${STAGE}${NC}"

case "$STAGE" in
  0) check_stage_0 ;;
  1) check_stage_0; check_stage_1 ;;
  2) check_stage_1; check_stage_2 ;;
  3) check_stage_2; check_stage_3 ;;
  4) check_stage_3; check_stage_4 ;;
  5) check_stage_4; check_stage_5 ;;
  6) check_stage_5; check_stage_6 ;;
  6.5|65) check_stage_6; check_stage_65 ;;
  7) check_stage_65; check_stage_7 ;;
  7.5|75) check_stage_7; check_stage_75 ;;
  8) check_stage_75 ;;
  all)
    check_stage_0
    check_stage_1
    check_stage_2
    check_stage_3
    check_stage_4
    check_stage_5
    check_stage_6
    check_stage_65
    check_stage_7
    check_stage_75
    ;;
  help|*)
    echo ""
    echo "Usage: bash scripts/health-check.sh [stage]"
    echo ""
    echo "  bash scripts/health-check.sh 0      # Stage 0: Raw Kubernetes"
    echo "  bash scripts/health-check.sh 1      # Stage 1: CI Pipeline"
    echo "  bash scripts/health-check.sh 2      # Stage 2: GitOps"
    echo "  bash scripts/health-check.sh 3      # Stage 3: Security Gates"
    echo "  bash scripts/health-check.sh 4      # Stage 4: Kyverno"
    echo "  bash scripts/health-check.sh 5      # Stage 5: Vault"
    echo "  bash scripts/health-check.sh 6      # Stage 6: Falco"
    echo "  bash scripts/health-check.sh 6.5    # Stage 6.5: Chaos Engineering"
    echo "  bash scripts/health-check.sh 7      # Stage 7: Observability"
    echo "  bash scripts/health-check.sh 7.5    # Stage 7.5: OpenTelemetry"
    echo "  bash scripts/health-check.sh all    # All stages"
    echo ""
    exit 0
    ;;
esac

print_summary
