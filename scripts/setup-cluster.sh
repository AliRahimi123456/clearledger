#!/usr/bin/env bash
# setup-cluster.sh
# Provisions the Multipass VM and bootstraps MicroK8s inside it.
# Called by `make setup`, which also runs setup-hosts.sh afterwards.

set -euo pipefail

# Remove any tracked files that should be ignored
# This handles the case where .cursor/ or __pycache__ were
# committed before .gitignore rules were added
if git rev-parse --git-dir >/dev/null 2>&1; then
  git rm -r --cached .cursor/ 2>/dev/null || true
  git rm -r --cached "**/__pycache__" 2>/dev/null || true
fi

VM_NAME="clearledger"
VM_CPUS="4"
VM_MEMORY="8G"
VM_DISK="50G"
VM_IMAGE="22.04"

echo "==> Creating Multipass VM: $VM_NAME"
multipass launch \
  --name $VM_NAME \
  --cpus $VM_CPUS \
  --memory $VM_MEMORY \
  --disk $VM_DISK \
  $VM_IMAGE

echo "==> Bootstrapping MicroK8s inside the VM..."
multipass exec $VM_NAME -- bash -s << 'INNER'
set -euo pipefail

sudo snap install microk8s --classic --channel=1.29/stable
sudo usermod -aG microk8s ubuntu
newgrp microk8s << 'NEWGRP'
microk8s enable dns ingress storage helm3 rbac
echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
echo "alias helm='microk8s helm3'" >> ~/.bashrc
source ~/.bashrc
microk8s kubectl wait --for=condition=ready node --all --timeout=120s
echo "Cluster is ready."
NEWGRP
INNER

echo "==> Exporting kubeconfig to ~/.kube/$VM_NAME-config"
mkdir -p ~/.kube
multipass exec $VM_NAME -- microk8s config > ~/.kube/$VM_NAME-config

KUBECONFIG_LINE="export KUBECONFIG=~/.kube/$VM_NAME-config"
SHELL_RC="$HOME/.zshrc"
[ -n "${BASH_VERSION:-}" ] && SHELL_RC="$HOME/.bashrc"

if ! grep -qF "KUBECONFIG=~/.kube/$VM_NAME-config" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "# Added by ClearLedger setup" >> "$SHELL_RC"
  echo "$KUBECONFIG_LINE" >> "$SHELL_RC"
  echo "==> Added KUBECONFIG to $SHELL_RC"
fi

export KUBECONFIG=~/.kube/$VM_NAME-config

echo ""
echo "✓ Cluster ready."
echo ""
echo "Run this in your current terminal (already set for future terminals):"
echo "  export KUBECONFIG=~/.kube/$VM_NAME-config"
echo "  kubectl get nodes"
