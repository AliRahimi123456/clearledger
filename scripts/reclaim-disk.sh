#!/usr/bin/env bash
# reclaim-disk.sh
# Safely reclaims disk inside the ClearLedger Multipass VM.
# Prunes unused container images and vacuums journald — never touches PVCs or running workloads.

set -euo pipefail

VM_NAME="${VM_NAME:-clearledger}"

if ! command -v multipass >/dev/null 2>&1; then
  echo "ERROR: multipass not found — install Multipass (https://multipass.run)" >&2
  exit 1
fi

if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
  echo "ERROR: Multipass VM '${VM_NAME}' not found — run make setup" >&2
  exit 1
fi

echo "==> Reclaiming disk inside VM: ${VM_NAME}"
multipass exec "$VM_NAME" -- bash -s << 'INNER'
set -euo pipefail

print_disk() {
  echo "--- Disk usage (/) ---"
  df -h / | awk 'NR==1 || NR==2'
  echo ""
}

print_disk
echo "BEFORE reclaim"

echo ""
echo "==> Pruning unused container images (microk8s ctr — in-use images are kept)..."
if command -v microk8s >/dev/null 2>&1; then
  sudo microk8s ctr -n k8s.io images prune 2>/dev/null || \
    sudo microk8s ctr image prune 2>/dev/null || \
    echo "WARN: image prune skipped (ctr unavailable or cluster stopped)"
else
  echo "WARN: microk8s not installed — skipping image prune"
fi

echo ""
echo "==> Vacuuming journald to 200M..."
sudo journalctl --vacuum-size=200M

echo ""
print_disk
echo "AFTER reclaim"
INNER

echo ""
echo "Done. Run 'make doctor' to check disk health."
