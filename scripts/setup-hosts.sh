#!/usr/bin/env bash
# setup-hosts.sh
# Adds /etc/hosts entries for all ClearLedger lab domains.
# Run after the VM is created and has an IP.

set -euo pipefail

VM_NAME="clearledger"

echo "==> Getting VM IP address..."
VMIP=$(multipass info $VM_NAME | grep IPv4 | awk '{print $2}')

if [ -z "$VMIP" ]; then
  echo "ERROR: Could not determine VM IP. Is the VM running?"
  echo "  multipass list"
  exit 1
fi

echo "VM IP: $VMIP"

DOMAINS=(
  "clearledger.local"
  "argocd.local"
  "grafana.local"
  "vault.local"
  "falco.local"
)

echo "==> Adding /etc/hosts entries..."
for domain in "${DOMAINS[@]}"; do
  if grep -q "$domain" /etc/hosts; then
    echo "  Skipping $domain (already exists)"
  else
    echo "$VMIP  $domain" | sudo tee -a /etc/hosts
    echo "  Added: $VMIP  $domain"
  fi
done

echo ""
echo "✓ /etc/hosts updated."
echo ""
echo "Test with:"
echo "  curl -s http://clearledger.local/auth/health"
echo "  (after deploying — see stages/stage-0-raw-kubernetes/README.md)"
