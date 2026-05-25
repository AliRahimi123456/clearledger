# Quickstart

Get the cluster running. Then read Stage 0.

---

## Quick Reference

```
make setup      # Start here — provision cluster
make stage-0    # First stage
make check-0    # Verify stage 0 works
make open-ui    # Open the web UI
make teardown   # Clean up
```

Full command list: run `make` with no arguments.

**Local integration testing (no Kubernetes):** `docker-compose.integration.yml` at the repo root — see `scripts/dast/README.md`.

---

## Choose Your Path

### Path A — Automatic (recommended)

```bash
bash scripts/setup-cluster.sh
bash scripts/setup-hosts.sh
cd stages/stage-0-raw-kubernetes && cat README.md
```

**Note:** Path A runs the same commands as Path B. Use Path B if a step in Path A fails and you need to debug it.

### Path B — Manual (if you want to understand each step)

The steps below are the manual sequence.

---

## Step 1 — Install Dependencies

| Tool | macOS | Linux | Windows (PowerShell Admin) |
|---|---|---|---|
| Multipass | `brew install --cask multipass` | `sudo snap install multipass` | [multipass.run/install](https://multipass.run/install) |
| kubectl | `brew install kubectl` | `sudo snap install kubectl --classic` | `winget install Kubernetes.kubectl` |
| Helm | `brew install helm` | `sudo snap install helm --classic` | `winget install Helm.Helm` |
| Docker | [Docker Desktop](https://docs.docker.com/desktop/) | [docs.docker.com](https://docs.docker.com/engine/install/) | [Docker Desktop](https://docs.docker.com/desktop/) |

---

## Step 1b — Docker Hub Setup (Required Before Stage 1)

1. Create a free account at hub.docker.com if you don't have one.

2. Create four public repositories on Docker Hub:
   - YOUR_USERNAME/clearledger-auth-service
   - YOUR_USERNAME/clearledger-ledger-service
   - YOUR_USERNAME/clearledger-notification-service
   - YOUR_USERNAME/clearledger-frontend

3. Generate an access token at hub.docker.com → Account Settings → Security
   → New Access Token (read/write permissions).
   Save it — you will not see it again.

4. Add secrets to GitHub when you reach Stage 1:
   - DOCKER_USERNAME: your Docker Hub username
   - DOCKER_PASSWORD: the access token (not your account password)
   - INFRA_REPO_TOKEN: a GitHub PAT with `repo` scope (created at github.com/settings/tokens)

> **Two repos, one platform:** `clearledger` holds application code and runs the CI pipeline.
> `clearledger-infra` holds Kubernetes manifests — ArgoCD (Stage 2) watches it and keeps
> the cluster in sync. Both repos live on GitHub. The self-hosted runner inside the VM
> pushes image tag updates to `clearledger-infra` after each successful build.

That is all. No local registry configuration required.

---

## Step 2 — Launch the Cluster

```bash
multipass launch \
  --name clearledger \
  --cpus 4 \
  --memory 8G \
  --disk 50G \
  22.04
```

---

## Step 3 — Bootstrap MicroK8s Inside the VM

```bash
multipass shell clearledger
```

Inside the VM:

```bash
sudo snap install microk8s --classic --channel=1.29/stable
sudo usermod -aG microk8s ubuntu
newgrp microk8s
microk8s enable dns ingress storage helm3
echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
echo "alias helm='microk8s helm3'" >> ~/.bashrc
source ~/.bashrc
kubectl get nodes
# NAME          STATUS   ROLES    AGE   VERSION
# clearledger   Ready    <none>   2m    v1.29.x
exit
```

---

## Step 4 — Connect kubectl on Your Host

```bash
multipass exec clearledger -- microk8s config > ~/.kube/clearledger-config
export KUBECONFIG=~/.kube/clearledger-config
kubectl get nodes
```

Add the export to your shell profile (`~/.zshrc`, `~/.bashrc`) to persist it.

---

## Step 5 — Add /etc/hosts Entries

```bash
VMIP=$(multipass info clearledger | grep IPv4 | awk '{print $2}')
echo "VM IP: $VMIP"

# macOS / Linux:
sudo tee -a /etc/hosts << EOF
$VMIP  clearledger.local
$VMIP  argocd.local
$VMIP  grafana.local
$VMIP  vault.local
$VMIP  falco.local
EOF
```

**Windows (PowerShell as Administrator):**
```powershell
$ip = "REPLACE_WITH_VM_IP"
$entries = @(
  "$ip  clearledger.local",
  "$ip  argocd.local",
  "$ip  grafana.local",
  "$ip  vault.local",
  "$ip  falco.local"
)
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value ($entries -join "`n")
```

---

## Step 6 — Install Pre-commit Hooks

```bash
pip install pre-commit
pre-commit install
# Now every commit runs Gitleaks, YAML lint, and private key detection locally
# before it reaches CI
```

## Step 7 — Start Stage 0

```bash
cd stages/stage-0-raw-kubernetes
cat README.md
```

---

## Teardown

```bash
./scripts/teardown.sh
```

Or manually:
```bash
multipass delete clearledger
multipass purge
```
