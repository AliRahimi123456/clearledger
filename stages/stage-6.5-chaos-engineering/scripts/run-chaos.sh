#!/usr/bin/env bash
# Stage 6.5 — pod-delete chaos on auth-service (Litmus ChaosEngine)
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CHAOS_DIR="${REPO_ROOT}/stages/stage-6.5-chaos-engineering/infra/chaos"
HEALTH_URL="${CHAOS_HEALTH_URL:-http://clearledger.local/auth/health}"
ENGINE_NAME="auth-service-pod-delete"
ENGINE_NS="litmus"

count_auth_pods() {
  kubectl get pods -n clearledger -l app=auth-service \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' '
}

check_health() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" --max-time 5 2>/dev/null || true)
  if [ "${code}" = "200" ]; then
    echo "200"
    return
  fi
  if command -v multipass >/dev/null 2>&1 && multipass list 2>/dev/null | grep -q clearledger; then
    code=$(multipass exec clearledger -- curl -s -o /dev/null -w '%{http_code}' \
      http://clearledger.local/auth/health --max-time 5 2>/dev/null || true)
    if [ "${code}" = "200" ]; then
      echo "200"
      return
    fi
  fi
  echo "${code:-000}"
}

require_prereqs() {
  kubectl get ns litmus >/dev/null 2>&1 || { echo "litmus not installed — run install-litmus.sh"; exit 1; }
  kubectl get chaosexperiment pod-delete -n litmus >/dev/null 2>&1 \
    || { echo "pod-delete experiment missing — run install-litmus.sh"; exit 1; }

  local running wait=0
  running="$(count_auth_pods)"
  while [ "${running:-0}" -lt 2 ] && [ "${wait}" -lt 180 ]; do
    sleep 5
    wait=$((wait + 5))
    running="$(count_auth_pods)"
  done
  [ "${running:-0}" -ge 2 ] || { echo "need 2 Running auth-service pods — make fix-65-prereqs"; exit 1; }
}

wait_for_engine() {
  local elapsed=0
  while [ "${elapsed}" -lt 120 ]; do
    local s
    s="$(kubectl get chaosengine "${ENGINE_NAME}" -n "${ENGINE_NS}" \
      -o jsonpath='{.status.engineStatus}' 2>/dev/null || true)"
    [ "${s}" = "completed" ] || [ "${s}" = "stopped" ] && return 0
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}

echo -e "${BOLD}Stage 6.5 — auth-service pod-delete${NC}"
echo ""

require_prereqs
echo "Preflight: $(count_auth_pods) auth-service pods Running"
echo ""

kubectl delete chaosengine "${ENGINE_NAME}" -n "${ENGINE_NS}" --ignore-not-found >/dev/null 2>&1 || true
sleep 2

echo "Applying ChaosEngine ${ENGINE_NAME} (namespace ${ENGINE_NS})"
kubectl apply -f "${CHAOS_DIR}/auth-service-pod-delete.yaml"
echo ""
echo "Watching ${HEALTH_URL}"
echo ""

health_ok=0
for i in 1 2 3 4 5 6; do
  code="$(check_health)"
  pods="$(count_auth_pods)"
  if [ "${code}" = "200" ]; then
    health_ok=$((health_ok + 1))
    echo -e "  ${i}0s  ${GREEN}health=${code}${NC}  pods=${pods}"
  else
    echo -e "  ${i}0s  ${RED}health=${code}${NC}  pods=${pods}"
  fi
  sleep 10
done

wait_for_engine >/dev/null 2>&1 || true
echo ""

final_pods="$(count_auth_pods)"
verdict="$(kubectl get chaosresult -n litmus -o jsonpath='{.items[0].status.experimentStatus.verdict}' 2>/dev/null || echo "?")"
phase="$(kubectl get chaosresult -n litmus -o jsonpath='{.items[0].status.experimentStatus.phase}' 2>/dev/null || echo "?")"

echo "Result:"
echo "  ChaosResult: ${phase} / ${verdict}"
echo "  Recovery:    ${final_pods} auth-service pod(s) Running"
echo "  Health:      ${health_ok}/6 checks returned 200"
echo ""

chaos_pass=false
echo "${verdict}" | grep -qi pass && chaos_pass=true

if [ "${health_ok}" -ge 1 ] && [ "${final_pods:-0}" -ge 2 ]; then
  echo -e "${GREEN}${BOLD}PASS${NC}"
  exit 0
elif [ "${chaos_pass}" = true ] && [ "${final_pods:-0}" -ge 2 ]; then
  echo -e "${YELLOW}${BOLD}PASS (chaos ok; health checks did not all reach 200)${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}FAIL${NC}"
  exit 1
fi
