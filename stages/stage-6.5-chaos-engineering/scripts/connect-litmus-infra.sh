#!/usr/bin/env bash
# Connect this Kubernetes cluster to Litmus ChaosCenter (fixes empty Overview / blank UI).
# Called automatically by install-litmus.sh. Safe to re-run.
set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LITMUS_URL="${LITMUS_URL:-http://litmus.local}"
LITMUS_USER="${LITMUS_USER:-admin}"
LITMUS_PASSWORD="${LITMUS_PASSWORD:-litmus}"
ENV_NAME="${LITMUS_ENV_NAME:-clearledger-lab}"
INFRA_NAME="${LITMUS_INFRA_NAME:-clearledger-cluster}"
RELEASE_NAME="${LITMUS_AGENT_RELEASE:-clearledger-chaos-infra}"

echo "→ Logging in to ChaosCenter (${LITMUS_USER}@${LITMUS_URL})…"
LOGIN_JSON=$(curl -sf "${LITMUS_URL}/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${LITMUS_USER}\",\"password\":\"${LITMUS_PASSWORD}\"}") || {
  echo "Login failed. Set LITMUS_PASSWORD to the password you chose at first login (default: litmus)."
  exit 1
}

TOKEN=$(echo "${LOGIN_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")
PROJECT_ID=$(echo "${LOGIN_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['projectID'])")

echo "→ Ensuring environment '${ENV_NAME}' exists…"
curl -sf -X POST "${LITMUS_URL}/backend/query" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{\"query\":\"mutation { createEnvironment(projectID: \\\"${PROJECT_ID}\\\", request: { environmentID: \\\"${ENV_NAME}\\\", name: \\\"${ENV_NAME}\\\", type: NON_PROD, description: \\\"ClearLedger lab\\\" }) { environmentID } }\"}" \
  >/dev/null 2>&1 || true

if ! kubectl get sa litmus-admin -n litmus &>/dev/null; then
  kubectl apply -f "${STAGE_DIR}/infra/chaos/litmus-rbac.yaml"
fi
kubectl label sa litmus-admin -n litmus app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
kubectl annotate sa litmus-admin -n litmus \
  meta.helm.sh/release-name="${RELEASE_NAME}" \
  meta.helm.sh/release-namespace=litmus --overwrite 2>/dev/null || true

echo "→ Installing chaos agent (subscriber connects UI to this cluster)…"
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ 2>/dev/null || true
helm upgrade --install "${RELEASE_NAME}" litmuschaos/litmus-agent \
  --namespace litmus \
  --set INFRA_NAME="${INFRA_NAME}" \
  --set INFRA_DESCRIPTION="ClearLedger homelab cluster" \
  --set LITMUS_URL=http://chaos-litmus-frontend-service.litmus.svc.cluster.local:9091 \
  --set LITMUS_BACKEND_URL=http://chaos-litmus-server-service.litmus.svc.cluster.local:9002 \
  --set LITMUS_USERNAME="${LITMUS_USER}" \
  --set "LITMUS_PASSWORD=${LITMUS_PASSWORD}" \
  --set LITMUS_PROJECT_ID="${PROJECT_ID}" \
  --set LITMUS_ENVIRONMENT_ID="${ENV_NAME}" \
  --set SA_EXISTS=true \
  --set NS_EXISTS=true \
  --set SKIP_SSL=true \
  --set crds.create=false \
  --set event-tracker.enabled=false \
  --wait --timeout 5m

# event-tracker needs extra CRDs we skip in homelab (crds.create=false). Subscriber waits
# for all agent pods to be Ready — patch COMPONENTS so PENDING does not stick forever.
kubectl patch cm subscriber-config -n litmus --type merge -p \
  '{"data":{"COMPONENTS":"DEPLOYMENTS: [\"app=chaos-exporter\", \"name=chaos-operator\", \"app=workflow-controller\"]"}}' \
  2>/dev/null || true
kubectl delete pod -n litmus -l app.kubernetes.io/name=subscriber --ignore-not-found \
  --wait=false 2>/dev/null || true

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=subscriber -n litmus --timeout=120s 2>/dev/null || \
  kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=subscriber -n litmus --timeout=120s 2>/dev/null || true

CONFIRMED=$(kubectl get cm subscriber-config -n litmus -o jsonpath='{.data.IS_INFRA_CONFIRMED}' 2>/dev/null || echo "false")
echo ""
if [ "${CONFIRMED}" = "true" ]; then
  echo "✓ Cluster connected (subscriber confirmed agent)"
else
  echo "⚠ Agent not confirmed yet — check: kubectl logs -n litmus -l app.kubernetes.io/name=subscriber --tail=20"
fi
echo "  Open: ${LITMUS_URL}"
echo "  Environments → ${ENV_NAME} → infrastructure should show Active (not Pending)"
echo "  Then follow LAB-GUIDE §6.5.2"
