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
  "litmus.local"
)

echo "==> Adding /etc/hosts entries..."
for domain in "${DOMAINS[@]}"; do
  if grep -qE "[[:space:]]${domain}([[:space:]]|$)" /etc/hosts; then
    echo "  Skipping $domain (already exists)"
  else
    if echo "$VMIP  $domain" | sudo tee -a /etc/hosts >/dev/null; then
      echo "  Added: $VMIP  $domain"
    else
      echo ""
      echo "Could not write /etc/hosts (sudo required). Add manually:"
      echo "  echo \"$VMIP  $domain\" | sudo tee -a /etc/hosts"
      exit 1
    fi
  fi
done

echo ""
echo "✓ /etc/hosts updated."
echo ""
echo "Test with:"
echo "  curl -s -o /dev/null -w '%{http_code}' http://clearledger.local/auth/health"
echo "  curl -s -o /dev/null -w '%{http_code}' http://litmus.local/"
