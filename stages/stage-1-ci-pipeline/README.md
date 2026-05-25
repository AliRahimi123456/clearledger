# Stage 1 — CI Pipeline (GitHub Actions + Self-Hosted Runner)

> **The problem you felt in Stage 0:** Every code change requires you to
> manually build an image, push it, and run kubectl. There is no audit trail.
> Anyone can push any image. Nothing is automatic.
>
> **What changes here:** A push to GitHub automatically builds all four images,
> pushes them to Docker Hub, and updates the image tags in the infra repo on
> GitHub. You still deploy manually. One pain point removed.

---

## What You Will Learn

- How to set up a CI pipeline with GitHub Actions
- How to install a self-hosted runner — the piece most tutorials skip
- The GitOps image update pattern — CI updates Git, not the cluster
- Why separating CI (build) from CD (deploy) matters

---

## What You Are Installing

| Component | Where it runs | What it does |
|---|---|---|
| GitHub Actions | GitHub (cloud) | Hosts the pipeline YAML, shows run results |
| Self-hosted runner | Inside the Multipass VM | Executes the jobs — needed so the runner can reach the local cluster |
| Docker Hub | Cloud | Stores the built images |

---

## Prerequisites

- Stage 0 complete — cluster running, ClearLedger deployed
- A GitHub account (free)
- A Docker Hub account (free)

---

## Steps

### 1. Create the Infra Repo on GitHub

The pipeline updates a separate repo (`clearledger-infra`) with new image tags after each build. ArgoCD (Stage 2) watches this repo and syncs the cluster.

Go to github.com → New Repository → Name: `clearledger-infra` → Public → Create.

Push the Kubernetes manifests to it:

```bash
mkdir -p /tmp/clearledger-infra
cp -r infra/* /tmp/clearledger-infra/
cd /tmp/clearledger-infra
git init
git remote add origin https://github.com/YOUR_USERNAME/clearledger-infra.git
git add . && git commit -m "feat: initial manifests" && git push -u origin main
cd -
```

---

### 2. Push the App Repo to GitHub

Go to github.com → New Repository → Name: `clearledger` → Public → Create.

Do not initialize with README or .gitignore — the repo already has these.

```bash
git remote add origin https://github.com/YOUR_USERNAME/clearledger.git
git branch -M main
git push -u origin main
```

---

### 3. Install the Self-Hosted Runner Inside the VM

> Without a runner inside your VM, GitHub Actions has no way to reach your
> local cluster. This is the step every tutorial skips.

**What is a self-hosted runner?**

GitHub Actions normally runs jobs on GitHub's cloud servers. A self-hosted runner is a small program you install inside the VM. It connects outbound to GitHub, picks up jobs, and executes them — inside the VM where it can reach the local cluster.

```
GitHub (cloud)
  triggers pipeline on push
  ↓
Self-hosted runner (inside VM)
  builds images, pushes to Docker Hub
  updates image tags in clearledger-infra on GitHub
```

**Step 1 — Generate a runner token on GitHub**

Go to: github.com/YOUR_USERNAME/clearledger → Settings → Actions → Runners → New self-hosted runner

Select: Linux → x64. Copy the token shown (expires in 1 hour).

**Step 2 — Install the runner inside the VM**

```bash
multipass shell clearledger
```

Inside the VM:

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner

curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-linux-x64-2.317.0.tar.gz

tar xzf ./actions-runner-linux-x64.tar.gz

./config.sh \
  --url https://github.com/YOUR_USERNAME/clearledger \
  --token YOUR_RUNNER_TOKEN \
  --name clearledger-runner \
  --labels clearledger,self-hosted,linux \
  --work _work \
  --unattended

sudo ./svc.sh install
sudo ./svc.sh start
```

**Step 3 — Install Docker inside the VM**

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu
newgrp docker
docker --version
```

**Step 4 — Exit and verify**

```bash
exit
```

Go to: github.com/YOUR_USERNAME/clearledger → Settings → Actions → Runners

You should see `clearledger-runner` with status **Idle**.

---

### 4. Set Up GitHub Secrets

Go to: github.com/YOUR_USERNAME/clearledger → Settings → Secrets and variables → Actions → New repository secret

Generate a PAT for the infra repo first:

Go to: github.com/settings/tokens → Generate new token (classic) → repo scope → Copy the token.

Add these three secrets:

| Secret name | Value | Purpose |
|---|---|---|
| `DOCKER_USERNAME` | Your Docker Hub username | Pipeline logs in to push images |
| `DOCKER_PASSWORD` | Your Docker Hub access token | Pipeline authenticates with Docker Hub |
| `INFRA_REPO_TOKEN` | The GitHub PAT from above | Pipeline pushes image tag updates to clearledger-infra |

---

### 5. Activate the Pipeline

Push any change to trigger the pipeline:

```bash
echo "# Pipeline activated $(date)" >> README.md
git add README.md
git commit -m "ci: activate GitHub Actions pipeline"
git push origin main
```

Watch the run at: github.com/YOUR_USERNAME/clearledger/actions

Expected — all jobs green in ~8 minutes:

```
✓ Build + Scan auth-service
✓ Build + Scan ledger-service
✓ Build + Scan notification-service
✓ Build + Scan frontend
✓ Update manifests → GitHub
```

After the pipeline succeeds, check github.com/YOUR_USERNAME/clearledger-infra — the image tags in the deployment manifests should have changed to the current commit SHA.

The cluster has not changed. That is the gap Stage 2 closes.

```bash
make check-1
```

---

## How It Fits Together

```
GitHub (cloud)
  clearledger          ← app repo (code lives here, pipeline runs here)
  clearledger-infra    ← infra repo (ArgoCD watches this in Stage 2)

Self-hosted runner (inside VM)
  builds images, pushes to Docker Hub
  updates clearledger-infra image tags on GitHub

ArgoCD (inside cluster — Stage 2)
  watches clearledger-infra on GitHub
  syncs cluster to match
```

---

## Troubleshooting

**Runner shows Offline on GitHub**
```bash
multipass exec clearledger -- sudo systemctl restart actions.runner.*.service
```

**Jobs fail with "docker: command not found"**
```bash
multipass exec clearledger -- bash -c \
  "curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker ubuntu"
```

**update-manifests fails with 401 on clearledger-infra**

Regenerate the PAT and update `INFRA_REPO_TOKEN` in GitHub Secrets.

**Pipeline triggers but no runner picks it up**

Verify labels match: pipeline uses `runs-on: [self-hosted, clearledger]`, runner was configured with `--labels clearledger,self-hosted,linux`.

---

## Before You Move On

```bash
bash scripts/health-check.sh 1
```

## → Next: [Stage 2 — GitOps with ArgoCD](../stage-2-gitops/README.md)
