#!/usr/bin/env bash
# Guided Stage 7 demo — generate real Falco, Kyverno, and app data for Grafana dashboards.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
NAMESPACE="${NAMESPACE:-clearledger}"
GRAFANA_URL="${GRAFANA_URL:-http://grafana.local}"
APP_URL="${APP_URL:-http://clearledger.local}"
SKIP_PROMPT="${SKIP_PROMPT:-0}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pause() {
  if [ "${SKIP_PROMPT}" = "1" ]; then
    return 0
  fi
  read -r -p "$1"
}

auth_pod() {
  kubectl get pod -n "${NAMESPACE}" -l app=auth-service \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

echo -e "${BOLD}ClearLedger — Stage 7 dashboard data generator${NC}"
echo ""
echo "This script runs the same hands-on lab as docs/LAB-GUIDE.md §7.4:"
echo "  Kyverno block → Falco shell → failed logins → compliance check."
echo "Open Grafana first: ${GRAFANA_URL} (admin / admin123), time range Last 15 minutes."
echo "Full write-up with expected outputs: docs/LAB-GUIDE.md — Stage 7."
echo ""
pause "Press Enter when Grafana is open… "

echo ""
echo -e "${BOLD}${CYAN}Step 1 — Kyverno policy violation${NC}"
echo "Simulating someone bypassing CI with kubectl apply (Stage 4 scenario)."
echo ""
cat <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: stage7-root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
YAML
echo ""
pause "Press Enter to apply the bad pod (expect admission webhook denial)… "
if cat <<'YAML' | kubectl apply -f - 2>&1 | tee /tmp/stage7-kyverno.out
apiVersion: v1
kind: Pod
metadata:
  name: stage7-root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
YAML
then
  echo -e "${YELLOW}⚠ Pod was created — Kyverno may not be enforcing. Run make check-4.${NC}"
else
  echo -e "${GREEN}✓ Kyverno blocked the pod (expected).${NC}"
fi
echo ""
echo "Open Grafana → Dashboards → tag: clearledger → ${BOLD}ClearLedger - Kyverno Policy Violations${NC}"
echo "Direct link: ${GRAFANA_URL}/d/clearledger-kyverno-violations?from=now-15m&to=now"
echo "Look for: Policy Violations (last hour) > 0 within ~2 minutes."
echo ""
pause "Press Enter after you checked the Kyverno dashboard… "

echo ""
echo -e "${BOLD}${CYAN}Step 2 — Falco runtime alert${NC}"
AUTH_POD="$(auth_pod || true)"
if [ -z "${AUTH_POD}" ]; then
  echo "✗ No running auth-service pod. Deploy the app first."
  exit 1
fi
echo "Target pod: ${AUTH_POD}"
echo "Running: kubectl exec … -- /bin/sh -c 'id && exit'"
pause "Press Enter to trigger the Falco shell alert… "
# Re-resolve pod name — auth pods may roll between Step 1 and Step 2.
AUTH_POD="$(auth_pod || true)"
if [ -z "${AUTH_POD}" ]; then
  echo "✗ No running auth-service pod (pod rolled during demo). Retry: kubectl get pod -n ${NAMESPACE} -l app=auth-service"
  exit 1
fi
kubectl exec -n "${NAMESPACE}" "${AUTH_POD}" -c auth-service -- /bin/sh -c 'id && exit' || true
echo ""
echo "Open: ${GRAFANA_URL}/d/clearledger-security-events?from=now-15m&to=now"
echo "Look for: CRITICAL row in Recent CRITICAL / WARNING Events (wait 30–60s for Loki)."
echo ""
echo -e "${BOLD}Portfolio screenshot #1:${NC} Security Event Timeline with at least one CRITICAL Falco alert visible."
echo ""
pause "Press Enter after the Falco timeline shows your alert… "

echo ""
echo -e "${BOLD}${CYAN}Step 3 — App traffic + failed logins${NC}"
echo "Generating HTTP traffic against ${APP_URL}…"
for i in $(seq 1 15); do
  curl -s "${APP_URL}/auth/health" >/dev/null || true
  curl -s "${APP_URL}/notifications/health" >/dev/null || true
  curl -s -X POST "${APP_URL}/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"email":"attacker@evil.com","password":"wrong"}' >/dev/null || true
done
echo -e "${GREEN}✓ Sent health checks + failed login attempts.${NC}"
echo ""
echo "If you have not run build-metrics-images.sh yet, request-rate panels may stay empty."
echo "Run: bash stages/stage-7-observability/scripts/build-metrics-images.sh"
echo ""
echo "Open: ${GRAFANA_URL}/d/clearledger-service-health?from=now-15m&to=now"
echo "Look for: Failed Login Attempts > 0 (Loki). Request Rate fills after metrics images roll out."
echo ""
echo -e "${BOLD}Portfolio screenshot #2:${NC} Service Health dashboard with Failed Login Attempts > 0."
echo ""
pause "Press Enter when Service Health shows login failures… "

echo ""
echo -e "${BOLD}${CYAN}Step 4 — Compliance posture (single pane)${NC}"
echo "Open: ${GRAFANA_URL}/d/clearledger-compliance?from=now-1h&to=now"
echo "You should see: Policy Violations > 0, Runtime Threats > 0, Failed Auth Attempts > 0."
echo ""
echo -e "${BOLD}Portfolio screenshot #3:${NC} Compliance Posture with all three top-row stats non-zero."
echo ""
pause "Press Enter when compliance dashboard looks populated… "

echo ""
echo -e "${BOLD}${CYAN}Step 5 — Health check (Stage 7 observability)${NC}"
SKIP_CHAOS_CHECK=1 bash "${ROOT_DIR}/scripts/health-check.sh" 7
echo ""
echo -e "${GREEN}${BOLD}Stage 7 demo complete.${NC}"
echo ""
echo "If a dashboard shows 'skipping rendering' in the browser console:"
echo "  • Use the direct /d/<uid>/<slug> links above (ASCII hyphens, not em-dashes)."
echo "  • Re-run: bash stages/stage-7-observability/scripts/install-observability.sh"
echo "  • See docs/troubleshooting.md — Stage 7"
