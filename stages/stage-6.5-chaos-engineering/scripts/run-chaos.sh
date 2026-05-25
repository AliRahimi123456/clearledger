#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CHAOS_DIR="${REPO_ROOT}/stages/stage-6.5-chaos-engineering/infra/chaos"

echo "Running ClearLedger Chaos Engineering tests..."
echo "This verifies the system survives failures, not just detects them."
echo ""

# Experiment 1: Kill an auth-service pod
echo "Experiment 1: Pod delete (auth-service)"
echo "Killing one auth-service replica for 30 seconds..."
kubectl apply -f "${CHAOS_DIR}/auth-service-pod-delete.yaml"

# Verify service is still responding DURING chaos
sleep 10
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  http://clearledger.local/auth/health --max-time 5 || echo "000")
if [ "$STATUS" = "200" ]; then
  echo -e "  ${GREEN}✓ auth-service /health responds 200 with one pod killed${NC}"
else
  echo -e "  ${RED}✗ auth-service /health returned $STATUS — no resilience${NC}"
fi

# Wait for chaos to end and verify recovery
sleep 30
PODS=$(kubectl get pods -n clearledger -l app=auth-service \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${PODS:-0}" -ge 2 ]; then
  echo -e "  ${GREEN}✓ auth-service recovered: $PODS replicas running${NC}"
else
  echo -e "  ${RED}✗ auth-service did not recover: only $PODS replica(s)${NC}"
fi

# Check Falco for any alerts triggered by the chaos
echo ""
echo "Checking Falco for chaos-triggered alerts..."
kubectl logs -n falco daemonset/falco --since=2m 2>/dev/null | grep -i "clearledger" || \
  echo "  No ClearLedger alerts during chaos (expected)"

echo ""
echo "Chaos tests complete. Check http://grafana.local for MTTR data."
echo ""
echo "To run additional experiments manually (one at a time):"
echo "  kubectl apply -f ${CHAOS_DIR}/ledger-service-network-latency.yaml  # from clearledger-experiments.yaml"
echo "  kubectl apply -f ${CHAOS_DIR}/notification-service-memory-hog.yaml  # extract from clearledger-experiments.yaml"
