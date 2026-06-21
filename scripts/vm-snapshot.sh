#!/usr/bin/env bash
# vm-snapshot.sh — Multipass snapshot/restore for the ClearLedger lab VM.
# Requires Multipass 1.13+ (snapshot support).

set -euo pipefail

VM_NAME="${VM_NAME:-clearledger}"
MIN_MULTIPASS_VERSION="1.13"

usage() {
  echo "Usage: $0 snapshot|restore|list <stage-number>" >&2
  echo "  snapshot 7   — save VM as clearledger snapshot stage7" >&2
  echo "  restore 7    — restore clearledger.stage7 (destructive)" >&2
  echo "  list         — show saved snapshots" >&2
}

snapshot_name() {
  printf 'stage%s' "$1"
}

multipass_version() {
  multipass version 2>/dev/null | awk '/^multipass/{print $2}' | cut -d+ -f1 | head -1
}

snapshots_supported() {
  if ! command -v multipass >/dev/null 2>&1; then
    echo "ERROR: multipass not found — install from https://multipass.run/install" >&2
    return 1
  fi

  local mp_ver
  mp_ver="$(multipass_version)"
  if [ -z "$mp_ver" ]; then
    echo "WARN: could not detect Multipass version — snapshot commands need Multipass ${MIN_MULTIPASS_VERSION}+." >&2
    echo "Upgrade: https://multipass.run/install" >&2
    return 2
  fi

  if ! printf '%s\n' "${MIN_MULTIPASS_VERSION}" "$mp_ver" | sort -C -V 2>/dev/null; then
    echo "Snapshots require Multipass ${MIN_MULTIPASS_VERSION} or newer (you have: ${mp_ver})." >&2
    echo "Upgrade: https://multipass.run/install" >&2
    return 2
  fi

  return 0
}

require_vm() {
  if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
    echo "ERROR: Multipass VM '${VM_NAME}' not found — run make setup first." >&2
    return 1
  fi
}

validate_stage() {
  local stage="$1"
  if [[ ! "$stage" =~ ^[0-9]+$ ]]; then
    echo "ERROR: stage must be a number (e.g. 7, 65, 75). Got: ${stage}" >&2
    return 1
  fi
}

do_snapshot() {
  local stage="$1"
  local name
  name="$(snapshot_name "$stage")"

  require_vm
  echo "==> Stopping VM: ${VM_NAME}"
  multipass stop "$VM_NAME"

  echo "==> Taking snapshot: ${name}"
  multipass snapshot "$VM_NAME" --name "$name"

  echo "==> Starting VM: ${VM_NAME}"
  multipass start "$VM_NAME"

  echo ""
  echo "✓ Snapshot saved: ${VM_NAME}.${name}"
  echo "  Restore with: make restore STAGE=${stage}"
}

do_restore() {
  local stage="$1"
  local name target
  name="$(snapshot_name "$stage")"
  target="${VM_NAME}.${name}"

  require_vm
  echo "==> Stopping VM: ${VM_NAME}"
  multipass stop "$VM_NAME"

  echo "==> Restoring ${target} (--destructive — current VM state will be discarded)"
  multipass restore "$target" --destructive

  echo "==> Starting VM: ${VM_NAME}"
  multipass start "$VM_NAME"

  echo ""
  echo "✓ Restored ${target}"
  echo "  Refresh kubeconfig if needed: bash scripts/ensure-kubeconfig.sh"
}

do_list() {
  if multipass info "$VM_NAME" --snapshots >/dev/null 2>&1; then
    multipass info "$VM_NAME" --snapshots
    return 0
  fi

  multipass list --snapshots 2>/dev/null || {
    echo "No snapshots found (or VM '${VM_NAME}' does not exist)."
  }
}

ACTION="${1:-}"
STAGE="${2:-}"

case "$ACTION" in
  snapshot|restore)
    if [ -z "$STAGE" ]; then
      usage
      exit 1
    fi
    validate_stage "$STAGE"
    rc=0
    snapshots_supported || rc=$?
    if [ "$rc" -eq 2 ]; then
      exit 0
    fi
    if [ "$rc" -ne 0 ]; then
      exit "$rc"
    fi
    if [ "$ACTION" = snapshot ]; then
      do_snapshot "$STAGE"
    else
      do_restore "$STAGE"
    fi
    ;;
  list|snapshots)
    rc=0
    snapshots_supported || rc=$?
    if [ "$rc" -eq 2 ]; then
      exit 0
    fi
    if [ "$rc" -ne 0 ]; then
      exit "$rc"
    fi
    do_list
    ;;
  -h|--help|help|"")
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown action: ${ACTION}" >&2
    usage
    exit 1
    ;;
esac
