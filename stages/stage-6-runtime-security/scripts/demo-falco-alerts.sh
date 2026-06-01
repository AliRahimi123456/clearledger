#!/usr/bin/env bash
# Guided demo: trigger a ClearLedger Falco alert and teach how to read it.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-clearledger}"
FALCO_NS="${FALCO_NS:-falco}"
UI_URL="${FALCO_UI_URL:-http://falco.local}"
REDIS_POD="${FALCO_REDIS_POD:-falco-falcosidekick-ui-redis-0}"
SKIP_PROMPT="${SKIP_PROMPT:-0}"

auth_pod() {
  kubectl get pod -n "${NAMESPACE}" -l app=auth-service \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

open_ui() {
  if command -v open >/dev/null 2>&1; then
    open "${UI_URL}" 2>/dev/null || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${UI_URL}" 2>/dev/null || true
  fi
}

ui_event_count() {
  kubectl exec -n "${FALCO_NS}" "${REDIS_POD}" -- redis-cli DBSIZE 2>/dev/null | tr -d '\r'
}

snapshot_event_keys() {
  kubectl exec -n "${FALCO_NS}" "${REDIS_POD}" -- redis-cli KEYS 'event:*' 2>/dev/null \
    | tr -d '\r' | sort
}

wait_for_new_ui_alert() {
  local before_file="$1"
  local rule_pattern="$2"
  local timeout="${3:-45}"
  local elapsed=0
  while [ "${elapsed}" -lt "${timeout}" ]; do
    while IFS= read -r key; do
      [ -z "${key}" ] && continue
      grep -qxF "${key}" "${before_file}" 2>/dev/null && continue
      local rule output
      rule="$(kubectl exec -n "${FALCO_NS}" "${REDIS_POD}" -- \
        redis-cli HGET "${key}" rule 2>/dev/null | tr -d '\r')"
      if [[ "${rule}" == *"${rule_pattern}"* ]]; then
        output="$(kubectl exec -n "${FALCO_NS}" "${REDIS_POD}" -- \
          redis-cli HGET "${key}" output 2>/dev/null | tr -d '\r')"
        printf '%s\n' "${output}"
        return 0
      fi
    done < <(snapshot_event_keys)
    sleep 2
    elapsed=$((elapsed + 2))
    printf "."
  done
  echo ""
  return 1
}

pause_if_interactive() {
  if [ "${SKIP_PROMPT}" = "1" ]; then
    return 0
  fi
  read -r -p "$1"
}

print_context() {
  echo -e "${BOLD}Why this demo exists${NC}"
  echo "  Stages 1–5 secure what gets *deployed*. Stage 6 watches what running code *does*."
  echo "  Kyverno never saw your kubectl exec — no new pod was created."
  echo "  Falco saw a shell spawn inside auth-service via a Linux syscall (eBPF)."
  echo ""
  echo -e "${BOLD}Attack story you are simulating${NC}"
  echo "  Attacker exploited the app → ran 'sh -c id' inside the container → reconnaissance."
  echo ""
}

print_after_alert() {
  echo -e "${BOLD}Now read the alert like an operator${NC}"
  echo "  1. Refresh ${UI_URL} — new row at top"
  echo "  2. Priority: Critical (not Notice from argocd)"
  echo "  3. Rule:    Shell Spawned in ClearLedger Container"
  echo "  4. Output:  pod=${AUTH_POD}  cmd=sh -c id && exit"
  echo "  5. Tags:    clearledger, shell, attack"
  echo ""
  echo "  Ask: Is a shell in auth-service expected? (No.) Who ran it? (You, via kubectl exec.)"
  echo "  Ask: Which control failed? (None pre-deploy — runtime detection caught it.)"
  echo ""
  echo "  Full walkthrough: docs/LAB-GUIDE.md §6.2 \"After the demo\""
  echo "  Next: §6.4 network policies — detection + prevention"
}

require_cluster() {
  if ! kubectl get ns "${FALCO_NS}" >/dev/null 2>&1; then
    echo "Falco namespace '${FALCO_NS}' not found. Run install-falco.sh first."
    exit 1
  fi
  if ! kubectl get pod -n "${FALCO_NS}" "${REDIS_POD}" >/dev/null 2>&1; then
    echo "Falcosidekick Redis pod '${REDIS_POD}' not found. Re-run install-falco.sh."
    exit 1
  fi
  local pod
  pod="$(auth_pod || true)"
  if [ -z "${pod}" ]; then
    echo "No running auth-service pod in ${NAMESPACE}. Deploy the app first (Stages 1–2)."
    exit 1
  fi
  AUTH_POD="${pod}"
}

run_scenario() {
  local title="$1"
  local cmd="$2"
  local rule_pattern="$3"
  local ui_rule="$4"

  echo ""
  echo -e "${BOLD}${CYAN}━━ ${title} ━━${NC}"
  echo ""
  local baseline
  baseline="$(ui_event_count)"
  local before_file
  before_file="$(mktemp)"
  snapshot_event_keys > "${before_file}"
  echo "Events in UI now: ${baseline}"
  echo ""
  echo "Baseline noise you can ignore: Notice rows from argocd (K8s API connections)."
  echo "What you are about to create: Critical row — shell inside YOUR app pod."
  echo ""
  pause_if_interactive "Press Enter when the Events tab is open and you noted the current count… "

  echo ""
  echo -e "${YELLOW}Simulating post-exploit shell in 3…${NC}"
  sleep 1
  echo "2…"
  sleep 1
  echo -e "${YELLOW}1… refresh the Events tab in ~10 seconds${NC}"
  sleep 1

  # shellcheck disable=SC2086
  eval "${cmd}"

  echo ""
  echo -n "Falco matching syscall → rule → UI store"
  local output
  if output="$(wait_for_new_ui_alert "${before_file}" "${rule_pattern}")"; then
    echo ""
    echo -e "${GREEN}✓ Runtime detection confirmed${NC}"
    echo "  Rule:   ${ui_rule}"
    echo "  Output: ${output}" | fold -s -w 100 | sed 's/^/          /'
    echo ""
    print_after_alert
  else
    echo ""
    echo "No new ClearLedger alert within 45s."
    echo "  • bash stages/stage-6-runtime-security/scripts/install-falco.sh"
    echo "  • Confirm exec uses -c auth-service"
    echo "  • docs/troubleshooting.md — Stage 6"
  fi
  rm -f "${before_file}"
}

echo -e "${BOLD}ClearLedger — Stage 6 runtime detection demo${NC}"
echo ""
print_context

require_cluster
echo "Target pod: ${AUTH_POD} (namespace ${NAMESPACE})"
echo ""

echo "Opening ${UI_URL} (login: admin / admin)…"
open_ui
echo ""
echo "Split screen: terminal (left) · Events tab (right)"
echo ""
pause_if_interactive "Press Enter when logged in… "

run_scenario \
  "Simulated attack — shell spawn after compromise" \
  "kubectl exec -n ${NAMESPACE} ${AUTH_POD} -c auth-service -- /bin/sh -c 'id && exit'" \
  "Shell Spawned in ClearLedger" \
  "Shell Spawned in ClearLedger Container"

echo ""
echo -e "${GREEN}${BOLD}Demo complete.${NC}"
echo "Screenshot the Critical row — not ArgoCD Notice noise."
