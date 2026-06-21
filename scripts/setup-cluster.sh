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
VM_IMAGE="22.04"

# Defaults: Stages 0–7.5 on a single-node lab (24GB+ host). Override without editing this file:
#   scripts/setup-cluster.local.env  (gitignored — copy from setup-cluster.local.env.example)
#   CLEARLEDGER_VM_CPUS=8 CLEARLEDGER_VM_MEMORY=16G CLEARLEDGER_VM_DISK=80G make setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/setup-cluster.local.env" ]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/setup-cluster.local.env"
fi
VM_CPUS="${CLEARLEDGER_VM_CPUS:-6}"
VM_MEMORY="${CLEARLEDGER_VM_MEMORY:-12G}"
VM_DISK="${CLEARLEDGER_VM_DISK:-80G}"

echo "==> Creating Multipass VM: $VM_NAME (${VM_CPUS} CPUs, ${VM_MEMORY} RAM, ${VM_DISK} disk)"
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

echo "==> Configuring disk safety (log rotation, image GC, journald cap)..."
multipass exec "$VM_NAME" -- bash -s << 'DISKSAFETY'
set -euo pipefail

KUBELET_ARGS="/var/snap/microk8s/current/args/kubelet"
JOURNALD_CONF="/etc/systemd/journald.conf"
NEEDS_MICROK8S_RESTART=0
NEEDS_JOURNALD_RESTART=0

ensure_kubelet_arg() {
  local arg="$1"
  local key="${arg%%=*}"

  if sudo grep -qxF "$arg" "$KUBELET_ARGS" 2>/dev/null; then
    return 0
  fi

  if sudo grep -q "^${key}=" "$KUBELET_ARGS" 2>/dev/null; then
    sudo sed -i "s|^${key}=.*|${arg}|" "$KUBELET_ARGS"
  else
    echo "$arg" | sudo tee -a "$KUBELET_ARGS" >/dev/null
  fi
  NEEDS_MICROK8S_RESTART=1
}

for arg in \
  "--container-log-max-size=10Mi" \
  "--container-log-max-files=3" \
  "--image-gc-high-threshold=80" \
  "--image-gc-low-threshold=60"; do
  ensure_kubelet_arg "$arg"
done

if sudo grep -qxF "SystemMaxUse=300M" "$JOURNALD_CONF" 2>/dev/null; then
  :
elif sudo grep -q "^SystemMaxUse=" "$JOURNALD_CONF" 2>/dev/null; then
  sudo sed -i 's/^SystemMaxUse=.*/SystemMaxUse=300M/' "$JOURNALD_CONF"
  NEEDS_JOURNALD_RESTART=1
elif sudo grep -q "^#SystemMaxUse=" "$JOURNALD_CONF" 2>/dev/null; then
  sudo sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=300M/' "$JOURNALD_CONF"
  NEEDS_JOURNALD_RESTART=1
else
  echo "SystemMaxUse=300M" | sudo tee -a "$JOURNALD_CONF" >/dev/null
  NEEDS_JOURNALD_RESTART=1
fi

if [ "$NEEDS_JOURNALD_RESTART" -eq 1 ]; then
  sudo systemctl restart systemd-journald
  echo "journald capped at SystemMaxUse=300M"
else
  echo "journald already capped at SystemMaxUse=300M"
fi

if [ "$NEEDS_MICROK8S_RESTART" -eq 1 ]; then
  echo "Applying kubelet disk-safety args (restart required)..."
  sudo microk8s stop
  sudo microk8s start
  sudo microk8s status --wait-ready
  echo "kubelet disk-safety args applied"
else
  echo "kubelet disk-safety args already configured"
fi
DISKSAFETY

echo "==> Configuring VM network (DNS for CI/Docker — pinned resolvers)..."
VM_NAME="${VM_NAME}" bash "${SCRIPT_DIR}/configure-vm-network.sh"

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
