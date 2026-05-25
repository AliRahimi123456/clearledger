#!/usr/bin/env bash
# teardown.sh
# Deletes the Multipass VM and optionally removes /etc/hosts entries.
# Run this when you are done with the lab or want to start fresh.

set -euo pipefail

VM_NAME="clearledger"

echo "==> Stopping and deleting VM: $VM_NAME"
multipass delete $VM_NAME
multipass purge

echo ""
echo "==> Cleaning up kubeconfig..."
rm -f ~/.kube/$VM_NAME-config

echo ""
read -p "Remove /etc/hosts entries? (y/N): " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
  DOMAINS=(
    "clearledger.local"
    # gitea.local removed — infra repo moved to GitHub
    "argocd.local"
    "grafana.local"
    "vault.local"
    "falco.local"
  )
  for domain in "${DOMAINS[@]}"; do
    sudo sed -i '' "/$domain/d" /etc/hosts 2>/dev/null || \
      sudo sed -i "/$domain/d" /etc/hosts 2>/dev/null || true
    echo "  Removed: $domain"
  done
fi

echo ""
echo "✓ Teardown complete."
echo ""
echo "To start fresh:"
echo "  ./scripts/setup-cluster.sh"
