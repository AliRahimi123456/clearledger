#!/usr/bin/env bash
# Query GitHub Actions runner state inside the Multipass VM.
# All systemctl/glob logic runs on Linux inside the VM so host shell
# (macOS zsh, Git Bash on Windows, WSL) never expands actions.runner.*.
#
# Usage:
#   bash scripts/runner-vm-state.sh state   # systemd:active:SVC | process:running | missing | no-multipass | no-vm
#   bash scripts/runner-vm-state.sh start   # start systemd service (no-op if already active)
#   bash scripts/runner-vm-state.sh status  # human-readable status for make runner-status
#   bash scripts/runner-vm-state.sh logs    # last 50 log lines

set -euo pipefail

VM_NAME="${RUNNER_VM_NAME:-clearledger}"
RUNNER_UNIT_GLOB="actions.runner.*.service"

_runner_unit_in_vm() {
  multipass exec "$VM_NAME" -- bash -lc "
    systemctl list-units --type=service --all --no-legend '${RUNNER_UNIT_GLOB}' 2>/dev/null \
      | awk '{print \$1}' | head -1
  " 2>/dev/null || true
}

_state_in_vm() {
  multipass exec "$VM_NAME" -- bash -lc "
    svc=\$(systemctl list-units --type=service --all --no-legend '${RUNNER_UNIT_GLOB}' 2>/dev/null \
      | awk '{print \$1}' | head -1)
    if [ -n \"\$svc\" ] && systemctl is-active \"\$svc\" >/dev/null 2>&1; then
      echo \"systemd:active:\${svc}\"
    elif pgrep -f 'actions-runner/bin/Runner.Listener' >/dev/null 2>&1; then
      echo 'process:running'
    else
      echo 'missing'
    fi
  " 2>/dev/null || echo "missing"
}

cmd="${1:-state}"

if ! command -v multipass >/dev/null 2>&1; then
  case "$cmd" in
    state) echo "no-multipass"; exit 0 ;;
    *) echo "multipass not found — install Multipass (see QUICKSTART.md)" >&2; exit 1 ;;
  esac
fi

if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
  case "$cmd" in
    state) echo "no-vm"; exit 0 ;;
    *) echo "Multipass VM '${VM_NAME}' not found — launch it first (see QUICKSTART.md)" >&2; exit 1 ;;
  esac
fi

case "$cmd" in
  state)
    _state_in_vm
    ;;
  start)
    svc="$(_runner_unit_in_vm)"
    if [ -z "$svc" ]; then
      echo "No actions.runner systemd unit found. See stages/stage-1-ci-pipeline/README.md section 2." >&2
      exit 1
    fi
    multipass exec "$VM_NAME" -- bash -lc "sudo systemctl start '${svc}' && systemctl is-active '${svc}'"
    ;;
  status)
    state="$(_state_in_vm)"
    case "$state" in
      systemd:active:*)
        svc="${state#systemd:active:}"
        multipass exec "$VM_NAME" -- bash -lc "sudo systemctl status '${svc}' --no-pager" 2>/dev/null \
          || echo "Runner service ${svc} is active"
        ;;
      process:running)
        echo "Runner process is running (manual start — systemd service not active)"
        multipass exec "$VM_NAME" -- bash -lc "pgrep -af 'actions-runner/bin/Runner.Listener'" 2>/dev/null \
          || true
        echo ""
        echo "Recommended: bash scripts/runner-vm-state.sh start"
        ;;
      missing)
        echo "Runner not running. Install or start it — see stages/stage-1-ci-pipeline/README.md section 2."
        exit 1
        ;;
    esac
    ;;
  logs)
    svc="$(_runner_unit_in_vm)"
    if [ -n "$svc" ]; then
      multipass exec "$VM_NAME" -- bash -lc "journalctl -u '${svc}' --lines=50 --no-pager" 2>/dev/null
    elif multipass exec "$VM_NAME" -- bash -lc "[ -f /home/ubuntu/actions-runner/_diag/manual-runner.log ]" 2>/dev/null; then
      multipass exec "$VM_NAME" -- bash -lc "tail -50 /home/ubuntu/actions-runner/_diag/manual-runner.log" 2>/dev/null
    else
      echo "Runner not installed. See Stage 1 README."
      exit 1
    fi
    ;;
  *)
    echo "Usage: bash scripts/runner-vm-state.sh {state|start|status|logs}" >&2
    exit 1
    ;;
esac
