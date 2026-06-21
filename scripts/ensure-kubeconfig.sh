#!/usr/bin/env bash
# Refresh host kubeconfig from the ClearLedger MicroK8s VM (fixes stale API IP).
set -euo pipefail

VM_NAME="${VM_NAME:-clearledger}"
OUT="${KUBECONFIG:-${HOME}/.kube/${VM_NAME}-config}"

mkdir -p "$(dirname "${OUT}")"
multipass exec "${VM_NAME}" -- microk8s config > "${OUT}"
chmod 600 "${OUT}"

echo "✓ Wrote ${OUT}"
echo "  server: $(grep -E '^\s+server:' "${OUT}" | head -1 | awk '{print $2}')"
echo ""
echo "Use for this shell:"
echo "  export KUBECONFIG=${OUT}"
