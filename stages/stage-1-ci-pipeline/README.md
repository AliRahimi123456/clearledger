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

You use two GitHub repositories:

| Repo | What lives there | Who changes it |
|---|---|---|
| `clearledger` | App source code, Dockerfiles, tests, pipeline YAML, lab docs | You |
| `clearledger-infra` | Kubernetes manifests only | The CI pipeline, then ArgoCD reads it |

Think of the split like this:

```text
clearledger
  "Here is the application code"

clearledger-infra
  "Here is the exact version that should run in Kubernetes"
```

The pipeline builds images from `clearledger`, pushes those images to Docker Hub, then updates image tags in `clearledger-infra`. It does **not** deploy directly to Kubernetes. ArgoCD closes that gap in Stage 2.

Go to github.com → New Repository → Name: `clearledger-infra` → Public → Create.

Push only `infra/manifests/` to it (not `infra/deferred-by-stage/` — that folder is for Stage 6+):

```bash
mkdir -p /tmp/clearledger-infra
cp -r infra/manifests /tmp/clearledger-infra/
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

**Step 2 — Enter the VM**

```bash
multipass shell clearledger
```

> **Check your prompt before continuing.**
> It must change to `ubuntu@clearledger:~$`.
> If it still shows your Mac username, you are on the wrong machine.
> The runner binary is Linux-only — running it on macOS gives:
> `cannot execute binary file`

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

What those last two commands mean:

```text
sudo ./svc.sh install
  Registers the runner with systemd inside the VM.
  Without this, `sudo ./svc.sh status` says: not installed.

sudo ./svc.sh start
  Starts the runner service in the background.
  After this, it keeps running even when you close the terminal.
```

Check it locally:

```bash
cd ~/actions-runner
sudo ./svc.sh status
```

If you see `not installed`, run:

```bash
cd ~/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

If `install` fails, rerun `./config.sh` with a fresh GitHub runner token, then run install/start again.

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

The workflow needs credentials for Docker Hub and for the second GitHub repo.

Create the values like this:

- `DOCKER_USERNAME`: your Docker Hub username, from hub.docker.com → Account Settings.
- `DOCKER_PASSWORD`: a Docker Hub access token, from hub.docker.com → Account Settings → Security → New Access Token. Use this instead of your normal password.
- `INFRA_REPO_TOKEN`: a GitHub PAT, from GitHub profile photo → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → Generate new token (classic) → select `repo` scope. The pipeline uses this to push commits to `clearledger-infra`.

Copy tokens immediately. Docker Hub and GitHub only show token values once.

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
bash scripts/runner-vm-state.sh start
# or restart after config changes:
multipass exec clearledger -- bash -lc \
  'svc=$(systemctl list-units --type=service --all --no-legend "actions.runner.*.service" | awk "{print \$1}" | head -1); sudo systemctl restart "$svc"'
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
make check-1
```

Green output = ready for Stage 2.

### DevSecOps lesson

Automate build and **record intent in Git** — do not `kubectl` deploy. CI produces signed, scanned images and updates `clearledger-infra`; the cluster gap you feel when tags change but pods do not is intentional. Stage 2 closes it with GitOps.

Full note: [LAB-GUIDE § Stage 1 lesson](../../docs/LAB-GUIDE.md#devsecops-lesson--stage-1-in-one-paragraph)

## → Next: [Stage 2 — GitOps with ArgoCD](../stage-2-gitops/README.md)
