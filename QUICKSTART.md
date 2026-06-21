# Quickstart

Get the cluster running. Then work through **one stage at a time** in [docs/LAB-GUIDE.md](docs/LAB-GUIDE.md) — do not read the full guide upfront (~6,000 lines).

---

## Quick Reference

```
make setup      # Start here — provision cluster
make stage-0    # First stage
make check-0    # Verify stage 0 works
make snapshot STAGE=0 && make snapshots   # after each check-N — confirm checkpoint exists
make open-ui    # Open the web UI
make teardown   # Clean up
```

After every `make check-N`: snapshot → list → confirm `clearledger.stageN` before advancing. Full ritual: [LAB-GUIDE — Saving your progress](docs/LAB-GUIDE.md#saving-your-progress).

Full command list: run `make` with no arguments.

**Local integration testing (no Kubernetes):** `docker-compose.integration.yml` at the repo root — see `scripts/dast/README.md`.

---

## Choose Your Path

### Path A — Automatic (recommended)

```bash
make setup
export KUBECONFIG=~/.kube/clearledger-config
kubectl get nodes   # should show Ready
```

Then open [LAB-GUIDE.md — Stage 0](docs/LAB-GUIDE.md#stage-0--the-running-system) and continue from §0.2 (cluster is already provisioned).

**Rule:** every stage in the lab guide ends with a **✋ Hands-on checkpoint**. Run it yourself before `make check-N`. Skipping checkpoints is the main reason learners quit at Stage 1 or 2.

| Stage | Checkpoint (in LAB-GUIDE) | You prove |
|---|---|---|
| 0 | §0.3, §0.5.5 | Images on Docker Hub; pods Running before ingress |
| 1 | §1.3, §1.6 | Infra repo has secrets + `secretKeyRef`; runner picks up jobs |
| 2 | Pre-sync checklist, post-sync | Git correct before ArgoCD; app Healthy after sync |
| 4 | §4.2 | Cosign public key pasted into policy YAML |
| 5 | §5.4b, §5.4 checkpoint | Secrets removed from Git; Vault annotations present |

**Note:** `make setup` runs the same steps as Path B and configures VM DNS via `scripts/configure-vm-network.sh` (Mac + Multipass). On Linux or WSL2 with MicroK8s on the host, run `bash scripts/configure-vm-network.sh --inside-vm` after provisioning.

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

**If you used Path A (`make setup`), skip Steps 2–4** — the cluster is already running. Continue at [LAB-GUIDE §0.2](docs/LAB-GUIDE.md#02--understand-the-application-before-deploying-it).

<details>
<summary>Manual launch (Path B only — if <code>make setup</code> failed)</summary>

```bash
multipass launch \
  --name clearledger \
  --cpus 6 \
  --memory 12G \
  --disk 80G \
  22.04
```

</details>

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
