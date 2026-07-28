# How to Build a Real-World DevSecOps Platform from Homelab to AWS: A Complete Hands-On Project

*The DevSecOps Handbook*

You will build a fintech transaction ledger from scratch and progressively transform it into a production-ready DevSecOps platform, ending with a deployment on AWS.

The app processes credit and debit transactions, fires compliance alerts, and stores everything in a database. You build the infrastructure around it yourself: automation, scanning, policy enforcement, secrets management, threat detection, and observability. By the time you finish, you can talk through every decision in an interview because you made each one.

This guide does not hand you a pre-built solution. It makes you feel each problem before introducing the tool that solves it.

All the code, manifests, scripts, and stage-by-stage READMEs live in the companion repository. Clone it before you start:

```bash
git clone https://github.com/Osomudeya/clearledger.git
cd clearledger
```

Everything in this article refers to files inside that repo.

---

## Prerequisites

You need these tools installed on your machine before Stage 0:

- Multipass: creates a lightweight Ubuntu VM so Kubernetes has enough resources
- kubectl: talks to your Kubernetes cluster from your terminal
- Helm: installs apps into Kubernetes
- Docker Desktop: builds container images
- jq: formats JSON output so it is readable

You also need free accounts on GitHub and Docker Hub.

For knowledge, you should be comfortable with:

- Basic Linux command line: navigating directories, reading files, running scripts
- Git: clone, commit, push
- What a container is and roughly how Docker builds one

You do not need prior Kubernetes, security, or cloud experience. This guide builds that from Stage 0.

Your machine needs at least 24 GB of RAM, 6 CPU cores, and 80 GB of free disk space. See [How to Set Up Your Machine](#heading-how-to-set-up-your-machine) for the exact install commands.

The companion repo is at [github.com/Osomudeya/clearledger](https://github.com/Osomudeya/clearledger). Star it, clone it, then continue.

---

## Table of Contents

- [What You Are Building](#heading-what-you-are-building)
- [How to Work Through This Lab](#heading-how-to-work-through-this-lab)
- [Tools You Will Meet](#heading-tools-you-will-meet)
- [How to Choose Your Path](#heading-how-to-choose-your-path)
- [Who This Is For](#heading-who-this-is-for)
- [How to Set Up Your Machine](#heading-how-to-set-up-your-machine)
- [How to Start the Lab](#heading-how-to-start-the-lab)
- [How to Manage Disk Space](#heading-how-to-manage-disk-space)
- [How to Try the App Without Kubernetes](#heading-how-to-try-the-app-without-kubernetes)
- [How to Configure Local Domain Names](#heading-how-to-configure-local-domain-names)
- [Stage 0 — The Running System](#heading-stage-0-the-running-system)
- [Stage 1 — CI Pipeline](#heading-stage-1-ci-pipeline-github-actions-self-hosted-runner)
  - [Private repos — what syncs where](#heading-private-repos-what-syncs-where)
- [Stage 2 — GitOps with ArgoCD](#heading-stage-2-gitops-with-argocd)
- [Stage 3 — Security Gates](#heading-stage-3-security-gates)
- [Stage 4 — Admission Control](#heading-stage-4-admission-control-kyverno)
- [Stage 5 — Secrets Management](#heading-stage-5-secrets-management-vault)
- [Stage 6 — Runtime Security](#heading-stage-6-runtime-security-falco)
- [Stage 6.5 — Chaos Engineering (Optional)](#heading-stage-65-chaos-engineering-optional)
- [Stage 7 — Security Observability](#heading-stage-7-security-observability)
- [Stage 7.5 — OpenTelemetry (Optional)](#heading-stage-75-opentelemetry-optional)
- [Stage 8 — AWS Migration](#heading-stage-8-aws-migration)
- [Troubleshooting](#heading-troubleshooting)
- [Compliance Reference](#heading-compliance-reference)
- [Interview Preparation](#heading-interview-preparation)
- [AWS Cost Reference](#heading-aws-cost-reference)
- [Conclusion](#heading-conclusion)

---

## What You Are Building

ClearLedger is a fintech transaction ledger built with three FastAPI microservices, PostgreSQL, Redis, and a web frontend.

Users can register, sign in, record credit and debit transactions, view their account balance, and receive compliance alerts whenever a transaction exceeds a predefined threshold.

The application is intentionally simple. Its purpose is not to teach fintech. It gives you a realistic system that you will secure and operate like a production platform.

The project consists of four components:

- **auth-service:** Handles user registration, login, and JWT authentication.
- **ledger-service:** Processes transactions, maintains account balances, and stores transaction history.
- **notification-service:** Listens for large transactions through Redis and generates compliance alerts.
- **frontend:** A web interface for logging in, viewing balances, submitting transactions, and reviewing alerts.

By the end of this handbook, every one of these services will still exist. What changes is how they are built, deployed, secured, and operated.

The application is simply the vehicle. DevSecOps is the destination.

### How the Platform Evolves

You will not install every tool on day one.
Instead, the platform grows the same way production systems usually do: a problem appears first, then a solution is introduced.

You begin with a manually deployed Kubernetes application. From there, each stage solves one real operational problem.

**Stage 0: Raw Kubernetes**

The application runs, but everything is deployed manually. This lets you understand the system before introducing automation.

**Stage 1: Continuous Integration**

Building container images becomes automatic whenever code is pushed, eliminating manual build steps.

**Stage 2: GitOps**

Deployments are no longer performed with kubectl. Git becomes the single source of truth, preventing configuration drift.

**Stage 3: Security Gates**

Every commit passes through security scanning so vulnerable code, secrets, and misconfigurations are stopped before deployment.

**Stage 4: Admission Control**

Even if something bypasses the pipeline, Kubernetes policies prevent insecure workloads from entering the cluster.

**Stage 5: Secrets Management**

Application credentials move out of Kubernetes Secrets into Vault, removing sensitive data from Git and cluster storage.

**Stage 6: Runtime Security**

Falco continuously watches running containers and detects suspicious behavior after deployment.

**Stage 6.5 (Optional): Chaos Engineering**

Failures are introduced deliberately to verify that the platform can recover instead of simply detecting problems.

**Stage 7: Observability**

Metrics, logs, and dashboards provide visibility into the health, performance, and security of the platform.

**Stage 7.5 (Optional): OpenTelemetry**

Distributed tracing follows requests across every service, revealing how a single transaction moves through the system.

**Stage 8: AWS Migration**

The same architecture is deployed on AWS using EKS, ECR, RDS, and an Application Load Balancer without changing how the application itself works.

If you simply want to explore the application before touching Kubernetes, an optional Docker Compose stack lets you run everything locally on your machine.

The guiding principle of this handbook is simple: every stage makes you feel the problem before introducing the tool that solves it.

---

## How to Work Through This Lab

This handbook makes you feel each problem before introducing the tool that solves it. Three habits will carry you through every stage.

**Read before you run.** The paragraphs before each command explain *why* you are running it. Skipping them means you can reproduce the steps but not explain them, and explaining them is what gets you hired. The commands are proof you understood.

**Choose with a reason.** Every tool here solves a specific problem. Why use Vault instead of Kubernetes Secrets? Why split code and manifests into two repos? Don't just follow the steps: ask *what breaks if we skip this?* If you understand the problem, you'll remember the solution.

**Go in order and verify every checkpoint.** Each stage depends on the one before it. When something breaks, read the error. Getting stuck and debugging is part of the learning: employers want to hear "I hit X error and fixed it by doing Y."

**At every ✋ Hands-on checkpoint:**

1. Run the command.
2. Compare your output with **Expected**.
3. If it doesn't match, fix it before continuing.
4. When `make check-N` passes: `make snapshot STAGE=N && make snapshots`. Only continue after you see `clearledger.stageN`.

**Avoid these mistakes:**

- Don't skip a checkpoint because it passed before.
- Don't run `make restore` without checking available snapshots first.
- Replace `your-username` with your real Docker Hub or GitHub username everywhere it appears.
- Run runner commands inside the VM (prompt shows `ubuntu@clearledger`), not on your Mac.

Take screenshots at each **portfolio checkpoint**. These moments become your proof that the platform runs, blocks, detects, syncs, and observes real activity.

---

## Tools You Will Meet

Come back to this list when a new name appears and you wonder *why now*. Each entry is one line: what it does and when it appears.

**On your laptop:** Multipass creates the Ubuntu VM. Docker builds images. `make` wraps long commands into `make setup` / `make check-N`. `/etc/hosts` entries like `clearledger.local` let your browser reach the cluster.

**The app:** Three Python APIs (auth, ledger, notifications) + a web frontend. Postgres stores data; Redis lets ledger publish alerts without calling notification directly. nginx ingress routes browser traffic to the right service.

| Tool | One-line role | Stage |
|---|---|---|
| MicroK8s / kubectl | Kubernetes cluster inside the VM; `kubectl` talks to it | 0 |
| `clearledger` (repo) | App code + CI workflow — what you build | 1 |
| `clearledger-infra` (repo) | Kubernetes YAML only — what the cluster should run; CI updates it, ArgoCD deploys it | 1 |
| GitHub Actions + self-hosted runner | Builds images and updates infra repo on every push; runner lives in the VM to reach the local cluster | 1 |
| ArgoCD | Watches `clearledger-infra`, syncs the cluster to match Git, reverts unauthorized changes | 2 |
| Gitleaks | Blocks commits that contain secrets (API keys, tokens) | 3 |
| Semgrep | SAST — catches unsafe Python patterns (injection, hardcoded credentials) | 3 |
| Checkov | IaC scanning — misconfigs in Dockerfiles and Kubernetes YAML | 3 |
| Trivy | Image scanning — known CVEs in pip/npm packages and the built container | 3 |
| Syft + Grype | SBOM generation and vulnerability check on the artifact itself | 3 |
| Cosign | Signs container images; Stage 4 rejects unsigned ones at deploy time | 3 |
| Kyverno | Admission control — blocks non-compliant pods at the cluster gate (root containers, missing limits, unsigned images) | 4 |
| Vault | Stores credentials outside Git and etcd; injects them into pods via a sidecar at startup | 5 |
| Falco | eBPF runtime detection — alerts when a shell starts or a sensitive file is read inside a running container | 6 |
| Network policies | Kubernetes firewall between pods — limits blast radius if one service is compromised | 6 |
| LitmusChaos | Kills pods deliberately to prove the app recovers (optional) | 6.5 |
| Prometheus / Grafana / Loki | Metrics, dashboards, and log search — turns security events into evidence | 7 |
| OpenTelemetry + Tempo | Distributed traces — shows where one request spent its time across services (optional) | 7.5 |
| Terraform / EKS / ECR / RDS | Infrastructure as code for the AWS migration; same app, cloud-managed backing services | 8 |

Each stage adds a new security layer. The tools are not interchangeable: scanners check code and images before deployment, ArgoCD keeps the cluster synced to Git, Vault handles secrets, Kyverno blocks unsafe workloads before they run, and Falco watches for suspicious behavior after they are running. That is why the order matters.
---

## How to Choose Your Path

Pick one path from your host RAM before you provision a cluster. Switching mid-lab after OOM kills or disk pressure wastes a day. Choose upfront.

| Your situation | Path | What you get |
|---|---|---|
| **8 GB RAM**, or unsure this laptop can carry the lab | **Docker Compose first** | The real app: register, post a transaction, see the compliance alert fire. Then decide on a cluster. → `make integration-up` · [Local integration stack](#heading-how-to-try-the-app-without-kubernetes) |
| **16 GB RAM** on the host | **Lite local cluster** (Stages 0–5) | This setup includes Kubernetes, CI/CD, GitOps, security checks, admission control, and Vault. To use fewer resources, copy `scripts/setup-cluster.local.env.example` to `scripts/setup-cluster.local.env`, lower the CPU, memory, or disk values, then run `make setup`. |
| **Under 16 GB** host RAM and you need Kubernetes, or you want all 8 stages | **Cloud VM** | Provision a remote machine (4–8 vCPU, 16–32 GB RAM), clone the repo, run the lab there, `make teardown` when done. Stages 6.5 / 7 / 7.5 (chaos + full observability) need 24 GB on the host, use this path if your laptop cannot spare that. |

The default path in this guide assumes 24 GB+ RAM and the full local VM (Before You Start). If that is not you, start from the row that matches your machine.

---

## How to Save Your Progress

**Mac + Multipass only:** `make snapshot` and `make restore` require Multipass.
If you're using Linux without Multipass, skip snapshots and use Path B if something goes wrong.

This lab takes several days to complete.

Your source code lives on your computer, so rebuilding or deleting the VM does not delete your Git repository, commits, manifests, or configuration files.

The VM stores your running environment, including deployed pods, Vault secrets, Postgres data, and Grafana dashboards.

### Save Your Progress

After completing each stage, create a snapshot before moving on.

```bash
make snapshot STAGE=7
make snapshots
```

Always run `make snapshots` to confirm the snapshot was created.

### Restore Your Progress

If the VM becomes unusable, restore the latest working snapshot.

```bash
make snapshots
make restore STAGE=7

export KUBECONFIG=~/.kube/clearledger-config
make check-7
```

### What Happens If the VM Breaks?

You keep:

- Your Git repository
- Your commits
- `.env`
- `setup-cluster.local.env`
- `clearledger-infra` on GitHub

You lose anything stored inside the VM after your last snapshot, including:

- Running pods
- Vault secrets
- Postgres data
- Grafana and Loki data

That's why it's a good idea to create a snapshot after every completed stage.

**Path A: You Have a Snapshot (Recommended)**

Restore the latest working snapshot and continue from that stage.

```bash
make snapshots
make restore STAGE=6

export KUBECONFIG=~/.kube/clearledger-config
make check-6
```

**Path B: No Snapshot**

Rebuild the lab.

```bash
make teardown
make setup

export KUBECONFIG=~/.kube/clearledger-config
```

Your Git repositories are still intact, but the Kubernetes cluster starts empty. Continue the handbook from the stage you had reached and rebuild the platform from there.

If you run into problems such as disk space issues, failed snapshots, Mac sleep or restart problems, Vault authentication errors, or pods stuck in CrashLoopBackOff, see [troubleshooting.md](troubleshooting.md) for detailed recovery steps.

---

## Who This Is For

**Junior DevOps (0–2 yrs):** do every stage in order. Do not skip the pain point sections. Expect Stage 0–2 to take a full day each, Stages 3–7 half a day each, Stage 8 a few hours. That is normal. Do not rush.

**Mid-level DevOps (2–4 yrs):** skim Stages 0–2 to understand the app, focus time on Stages 3–7 where the security layers are.

**Interview preparation:** complete through Stage 4, then read `docs/interview-prep.md`. The questions are based on exactly what is in this lab.

---

## How to Set Up Your Machine

Requirements are in [Prerequisites](#heading-prerequisites) above. Confirm 24 GB RAM, 6 CPU cores, and 80 GB free disk before installing.

### Install the Required Tools

| Tool | What it does | macOS | Linux | Windows |
|---|---|---|---|---|
| Multipass | Creates lightweight Ubuntu VMs on your laptop | `brew install --cask multipass` | `sudo snap install multipass` | [multipass.run/install](https://multipass.run/install) |
| kubectl | Talks to your Kubernetes cluster from your terminal | `brew install kubectl` | `sudo snap install kubectl --classic` | `winget install Kubernetes.kubectl` |
| Helm | Package manager for Kubernetes (like apt/brew but for cluster apps) | `brew install helm` | `sudo snap install helm --classic` | `winget install Helm.Helm` |
| Docker Desktop | Builds container images on your machine | [docker.com](https://docs.docker.com/desktop/) | [docker.com](https://docs.docker.com/engine/install/) | [docker.com](https://docs.docker.com/desktop/) |
| jq | Formats JSON output so you can read it | `brew install jq` | `sudo apt install jq` | `winget install jqlang.jq` |

> **Windows users:** Run all commands inside WSL2 Ubuntu. Do not use PowerShell for this lab because the setup uses `make` and Bash scripts.

Verify everything before continuing:

```bash
multipass --version
kubectl version --client
helm version
docker --version
jq --version
```

If any command fails, install the missing tool before continuing.

---

## How to Start the Lab

The main lab path starts at [Stage 0: the Running System](#heading-stage-0-the-running-system).

Use this one-command setup:

```bash
make setup
export KUBECONFIG=~/.kube/clearledger-config
kubectl get nodes
```

Expected: one node named `clearledger` with STATUS `Ready`.

`make setup` provisions the Multipass VM, installs MicroK8s, applies disk-safety caps, and updates `/etc/hosts`. Takes 3–5 minutes.

---

## How to Manage Disk Space

The lab runs on a single-node MicroK8s VM with a fixed disk (80 GB by default). Over days or weeks (especially after CI builds, Helm upgrades, and Stage 7 observability) container images, logs, and journald can fill the root filesystem. Pods then fail with `Evicted`, `ImagePullBackOff`, or mysterious `Pending` states.

`make setup` applies preventive caps automatically (log rotation, image GC thresholds, journald cap). See [Disk health in troubleshooting.md](troubleshooting.md#disk-health-long-running-lab-vm) for the full table and recovery steps.

**Check disk health:**

```bash
make doctor    # PASS / WARN / FAIL + PVC and Prometheus TSDB sizes
```

**Reclaim safe cruft inside the VM (does not delete PVCs):**

```bash
make reclaim
```

If `make doctor` still reports FAIL after reclaim, you may need `make teardown && make setup` and restore from a snapshot. Full guidance: [troubleshooting.md. VM disk full](troubleshooting.md#vm-disk-full-or-pods-evicted-disk-pressure).

---

## How to Try the App Without Kubernetes

If your machine doesn't have enough resources for Kubernetes, you can run ClearLedger with Docker Compose.

```bash
docker compose -f docker-compose.integration.yml up --build -d
```

Open:

http://localhost:3000

When you're ready, stop the stack and continue with Stage 0.

```bash
docker compose -f docker-compose.integration.yml down
```

### How to Sign In for the First Time

1. **Register**: the database starts empty after each fresh `up` (or `down -v`).
2. Use a real-looking email (Pydantic rejects `@*.local`), for example:
   - Email: `test@clearledger.io`
   - Password: `SecurePass123`
3. **Sign in** with the same credentials.

Wrong password shows *Incorrect email or password*. If you see a stale error, hard-refresh or run `localStorage.removeItem('cl_token')` in the browser console.

### How to Run the Demo Flow

1. Register and sign in at http://localhost:3000
2. Submit a few credits and debits (for example, Salary +$5000, Rent −$1200)
3. Confirm balance updates and history lists entries
4. Submit a transaction **≥ $10,000**: the Alerts panel should show `LARGE_TRANSACTION`

Optional smoke test against the same base URL:

```bash
BASE_URL=http://localhost:3000 bash scripts/dast/smoke.sh
```

When you continue the main lab, deploy to Kubernetes as in Stage 0 and use **clearledger.local**: the UI and APIs behave the same. Only the hostname and backing infra change.

---

## How to Configure Local Domain Names

Add the ClearLedger hostnames to your hosts file.

### macOS or Linux with Multipass

Run:

```bash
sudo bash scripts/setup-hosts.sh
```

Or do it manually:

```bash
VMIP=$(multipass info clearledger | grep IPv4 | awk '{print $2}')

echo "$VMIP  clearledger.local argocd.local grafana.local vault.local falco.local litmus.local" | sudo tee -a /etc/hosts
```

Verify after Stage 0:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/auth/health
```

Expected: `200`

### WSL2

Find your WSL IP:

```bash
ip -4 addr show eth0 | grep inet
```

Use the IP shown (or `127.0.0.1` if it works on your machine), then add it to `/etc/hosts`:

```bash
LAB_IP=<YOUR_IP>

echo "$LAB_IP  clearledger.local argocd.local grafana.local vault.local falco.local litmus.local" | sudo tee -a /etc/hosts
```

If you use Chrome or Edge on Windows instead of inside WSL, add the same line to:

`C:\Windows\System32\drivers\etc\hosts`

Verify:

```bash
curl http://clearledger.local/auth/health
```

---

## Stage 0 — The Running System

**Starting point:** Nothing is deployed yet. You're about to build a Kubernetes cluster and deploy ClearLedger manually.

**Goal:** By the end of this stage, ClearLedger will be running on Kubernetes. You'll be able to register a user, submit transactions, and see compliance alerts, all deployed by hand, with no automation.

Every deployment, update, and fix is manual. That is intentional. Before automating a platform, you need to understand how it works without automation.

---

### 0.1: Provision the cluster

**What you are doing:** creating a virtual machine on your laptop that runs its own Kubernetes cluster. Think of it as a miniature data center inside your computer.

**Multipass** creates lightweight Ubuntu VMs. **MicroK8s** is a minimal Kubernetes distribution that runs inside that VM. Together they give you a real cluster without needing cloud resources.

**Recommended: one command (do this):**

```bash
make setup
export KUBECONFIG=~/.kube/clearledger-config
kubectl get nodes
```

Expected:

```
NAME          STATUS   ROLES    AGE   VERSION
clearledger   Ready    <none>   2m    v1.29.x
```

`make setup` runs `scripts/setup-cluster.sh` (VM + MicroK8s + disk-safety caps) and `scripts/setup-hosts.sh` (`/etc/hosts` entries). Takes 3–5 minutes.

Disk-safety (log rotation, image GC thresholds, journald cap) is configured automatically, see Disk health in [troubleshooting.md](troubleshooting.md#disk-health-long-running-lab-vm)

If STATUS is `NotReady`, wait 60 seconds and try again.

<details>
<summary>Manual setup (only if <code>make setup</code> failed and you need to debug step by step)</summary>

```bash
multipass launch \
  --name clearledger \
  --cpus 6 --memory 12G --disk 80G \
  22.04
```

Get the VM IP (needed for `/etc/hosts`):

```bash
multipass info clearledger | grep IPv4
```

Add hosts entries. See the [Domain Names](#heading-how-to-configure-local-domain-names) section above, or run `sudo bash scripts/setup-hosts.sh`.

```bash
multipass shell clearledger
```

Inside the VM:

```bash
sudo snap install microk8s --classic --channel=1.29/stable
sudo usermod -aG microk8s ubuntu && newgrp microk8s
microk8s enable dns ingress storage helm3 rbac
echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
echo "alias helm='microk8s helm3'" >> ~/.bashrc
source ~/.bashrc
kubectl get nodes
exit   # back to your host machine
```

Connect kubectl from your host:

```bash
multipass exec clearledger -- microk8s config > ~/.kube/clearledger-config
export KUBECONFIG=~/.kube/clearledger-config
kubectl get nodes
```

</details>

---

### 0.2 — Understand the application before deploying it

Open these files before running a single `kubectl` command. Reading the code first builds context that makes everything else make sense.

| File | What it does |
|---|---|
| [`app/auth-service/main.py`](../app/auth-service/main.py) | Register, login, verify JWT |
| [`app/ledger-service/main.py`](../app/ledger-service/main.py) | Transactions, balance — calls auth-service to verify every request |
| [`app/notification-service/main.py`](../app/notification-service/main.py) | Subscribes to Redis, fires alerts when amount ≥ $10,000 |
| [`app/frontend/src/app.js`](../app/frontend/src/app.js) | SPA — calls the same API as the curl commands |
| [`app/auth-service/Dockerfile`](../app/auth-service/Dockerfile) | Non-root user, pinned base image, HEALTHCHECK |

Notice in every Dockerfile: `USER appuser`. The container does not run as root. This matters more than you think right now: in Stage 4, Kyverno will automatically reject any container that tries to run as root. You are seeing the security requirement before you see the enforcement.

Also look at [`infra/manifests/auth-service/secret.yaml`](../infra/manifests/auth-service/secret.yaml). The database password is `changeme-stage0` encoded in base64. Decode it:

```bash
echo "Y2hhbmdlbWUtc3RhZ2Uw" | base64 -d
# changeme-stage0
```

That password is sitting in a YAML file anyone with repo access can read. base64 is encoding, not encryption. It is trivially reversible. Remember this moment. It is why Stage 5 exists.

---

### 0.3 — Docker Hub setup

You need a container registry: a place to store the built images so the cluster can pull them. Docker Hub is the simplest option. You will replace it with a private registry (ECR) in Stage 8.

Create four public repositories on Docker Hub (free account, hub.docker.com):

```
YOUR_USERNAME/clearledger-auth-service
YOUR_USERNAME/clearledger-ledger-service
YOUR_USERNAME/clearledger-notification-service
YOUR_USERNAME/clearledger-frontend
```

Generate an access token: hub.docker.com → Account Settings → Security → New Access Token (Read/Write/Delete). Save it. You will not see it again.

```bash
docker login
# Username: your Docker Hub username
# Password: the access token (NOT your account password)
```

Build and push all four services:

```bash
# Replace your-username with your Docker Hub username — the same string everywhere in this lab
export DOCKER_USERNAME=your-username
echo "Using DOCKER_USERNAME=$DOCKER_USERNAME"
```

**✋ Hands-on checkpoint. Docker Hub username**

```bash
# Must print your real username, not the literal text "your-username"
echo "$DOCKER_USERNAME"
```

Expected: one line with your Docker Hub name (for example, `veeno-demo`). If you see `your-username`, stop and fix `export` before building.

Build and push all four services:

```bash
docker build -t $DOCKER_USERNAME/clearledger-auth-service:v0.1.0 ./app/auth-service
docker build -t $DOCKER_USERNAME/clearledger-ledger-service:v0.1.0 ./app/ledger-service
docker build -t $DOCKER_USERNAME/clearledger-notification-service:v0.1.0 ./app/notification-service
docker build -t $DOCKER_USERNAME/clearledger-frontend:v0.1.0 ./app/frontend

docker push $DOCKER_USERNAME/clearledger-auth-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-ledger-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-notification-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-frontend:v0.1.0
```

**✋ Hands-on checkpoint: images on Docker Hub**

1. Open hub.docker.com → your profile → **Repositories**.
2. Confirm all four `clearledger-*` repos exist and each shows tag **`v0.1.0`**.
3. On your laptop, run:

```bash
docker pull $DOCKER_USERNAME/clearledger-auth-service:v0.1.0
```

Expected: `Status: Downloaded newer image` or `Image is up to date`, not `repository does not exist` or `denied`.

---

### 0.4 — Look at the manifests before applying them

Kubernetes uses manifest files (YAML) to describe the resources it should create. Instead of clicking buttons, you declare the desired state, and Kubernetes creates it.

Before deploying ClearLedger, take a quick look at these manifests:

- `infra/manifests/namespace.yaml`: Creates the `clearledger` namespace.
- `infra/manifests/postgres/`: Deploys PostgreSQL.
- `infra/manifests/redis/redis.yaml`: Deploys Redis.
- `infra/manifests/auth-service/`: Deploys the authentication service.
- `infra/manifests/ledger-service/`: Deploys the ledger service.
- `infra/manifests/notification-service/`: Deploys the notification service.
- `infra/manifests/frontend/`: Deploys the web application.
- `infra/manifests/ingress.yaml`: Routes external browser traffic to the right service.
- `infra/manifests/rbac/rbac.yaml`: Defines who may do what inside the cluster.

You'll understand how Ingress routing and RBAC work in the two optional sections after §0.6. For now, just see how the app is described before Kubernetes creates it.

---

### 0.5 — Deploy ClearLedger (layer by layer)

Deploy in **six layers**. Finish each layer before starting the next. Run `kubectl get pods -n clearledger` after layers 2, 3, and 6 to confirm progress.

Set a short path variable and confirm your username is still set:

```bash
export DOCKER_USERNAME=your-username   # skip if already set in §0.3
STAGE0=stages/stage-0-raw-kubernetes/infra/manifests
```

---

#### 0.5.1 — Layer 1: Namespace and RBAC

Nothing else can be created until the namespace exists. RBAC must exist before workloads reference ServiceAccounts.

```bash
kubectl apply -f infra/manifests/namespace.yaml
kubectl apply -f infra/manifests/rbac/rbac.yaml
```

**Verify:**

```bash
kubectl get namespace clearledger
kubectl get serviceaccount -n clearledger
# Expected: auth-service, ledger-service, notification-service, clearledger-viewer
```

---

#### 0.5.2 — Layer 2: PostgreSQL

The database must be running before auth-service or ledger-service start. Both services connect to Postgres on startup to run migrations and serve requests, and they will crash-loop if the database is not there yet.

```bash
kubectl apply -f infra/manifests/postgres/postgres-secret.yaml
kubectl apply -f infra/manifests/postgres/postgres.yaml

kubectl wait --for=condition=ready pod -l app=postgres \
  -n clearledger --timeout=120s
```

Expected after `kubectl apply`:

```
secret/postgres-secret created
persistentvolumeclaim/postgres-pvc created
statefulset.apps/postgres created
service/postgres created
```

Expected when `kubectl wait` succeeds: the command exits with no output (exit code 0). If it times out, see **If postgres stays Pending** below before continuing.

**Verify:**

```bash
kubectl get pods -n clearledger -l app=postgres
kubectl get pvc -n clearledger
```

Expected:

```
NAME         READY   STATUS    RESTARTS   AGE
postgres-0   1/1     Running   0          45s

NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS        AGE
postgres-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWO            microk8s-hostpath   45s
```

**If postgres stays Pending** (`kubectl wait` times out, pod shows `0/1 Pending`, PVC shows `Pending`):

Postgres needs a **PersistentVolumeClaim**: disk space on the cluster. MicroK8s provides that through the **`hostpath-storage`** addon. If `make setup` was interrupted or you used manual setup without `microk8s enable storage`, the PVC has nothing to bind to and the pod never schedules.

Check the events: you'll usually see something like:

```
Warning  FailedScheduling  ...  pod has unbound immediate PersistentVolumeClaims
Normal   FailedBinding     ...  no persistent volumes available for this claim and no storage class is set
```

Fix it on the VM, then restart the postgres pod. Run this **from your host**: the same command on macOS, Linux, or Windows PowerShell (Multipass is installed on the host; it executes inside the VM for you):

```bash
# Enable storage (and ingress/rbac if make setup skipped them)
multipass exec clearledger -- microk8s enable storage ingress rbac

# Confirm a default StorageClass exists
kubectl get storageclass
# Expected: microk8s-hostpath (default)

# Kick the pod so it reschedules against the new storage class
kubectl delete pod postgres-0 -n clearledger

kubectl wait --for=condition=ready pod -l app=postgres \
  -n clearledger --timeout=120s
kubectl get pods -n clearledger -l app=postgres
# Expected: postgres-0   1/1   Running
```

Do not continue to auth-service or ledger-service until postgres is `Running`. They will crash-loop without a database.

---

#### 0.5.3 — Layer 3: Redis

**Why Redis is here: a quick scenario.** Imagine a customer posts a $15,000 debit. Ledger-service saves it to Postgres, then publishes a message to Redis: *"large transaction, user X, amount 15000."* Notification-service is listening on that channel. It picks up the message and records a compliance alert: the one you'll see in the UI later when you curl `/notifications/alerts`.

Ledger-service and notification-service don't call each other directly. Redis sits in the middle as a **message bus**: ledger publishes, notification subscribes. That's why Redis must be running before you deploy notification-service (and why you deploy it now, alongside Postgres, before the app layer).

```bash
kubectl apply -f infra/manifests/redis/redis.yaml
```

**Verify:**

```bash
kubectl get pods -n clearledger -l app=redis
```

Expected:

```
NAME                     READY   STATUS    RESTARTS   AGE
redis-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

---

#### 0.5.4 — Layer 4: Application secrets

Credentials live in Kubernetes Secrets for Stage 0 (Stage 5 moves them to Vault).

```bash
kubectl apply -f infra/manifests/auth-service/secret.yaml
kubectl apply -f infra/manifests/ledger-service/secret.yaml
```

**Verify:**

```bash
kubectl get secrets -n clearledger | grep -E 'auth-service|ledger-service'
```

Expected (AGE will differ; **DATA** counts must match):

```
auth-service-secret     Opaque   2      64s
ledger-service-secret   Opaque   1      8s
```

`auth-service-secret` holds two keys (`database_url`, `jwt_secret`). `ledger-service-secret` holds one (`database_url`). Stage 5 replaces these with Vault, for now they live in the cluster as Kubernetes Secrets.

---

#### 0.5.5 — Layer 5: Application workloads

You're about to start the four app services: auth, ledger, notification, and frontend. Postgres, Redis, and the Secrets from the last two layers are already in place. Now Kubernetes needs to pull your Docker Hub images and run them as pods.

**Two files per service (mostly).** A **Deployment** tells Kubernetes *which container image to run* and *how many copies*. A **Service** gives that app a stable name inside the cluster (for example, `auth-service` → so ledger can find auth without knowing pod IP addresses). You apply the Deployment first, then the Service.

**Why the `sed` command?** The deployment YAML files in Git contain a placeholder: literally the text `DOCKER_USERNAME`, because everyone's Docker Hub username is different. You already set yours in §0.3 (`export DOCKER_USERNAME=YOUR_DOCKERHUB_USERNAME`). The `sed` line swaps that placeholder for your real username **on the fly**, as the manifest is sent to Kubernetes. You never edit the file in Git. If you skip `sed` and apply the raw file, Kubernetes tries to pull an image called `DOCKER_USERNAME/clearledger-auth-service`, which does not exist.

**Why `stages/stage-0-raw-kubernetes/` and not `infra/manifests/`?** Those copies are for GitOps later; using them now causes a CrashLoop. The `STAGE0` variable already points at the right folder.

Deploy each service in order. Run these from the repo root with `DOCKER_USERNAME` still exported:

**1. auth-service**: login and registration

```bash
sed "s|DOCKER_USERNAME|${DOCKER_USERNAME}|g" \
  "$STAGE0/auth-service/deployment.yaml" | kubectl apply -f -
kubectl apply -f infra/manifests/auth-service/service.yaml
```

**2. ledger-service**: transactions and balance (needs Postgres + the secret you created in §0.5.4)

```bash
sed "s|DOCKER_USERNAME|${DOCKER_USERNAME}|g" \
  "$STAGE0/ledger-service/deployment.yaml" | kubectl apply -f -
kubectl apply -f infra/manifests/ledger-service/service.yaml
```

**3. notification-service**: listens on Redis for large-transaction alerts (no database secret in this one)

```bash
sed "s|DOCKER_USERNAME|${DOCKER_USERNAME}|g" \
  "$STAGE0/notification-service/deployment.yaml" | kubectl apply -f -
kubectl apply -f infra/manifests/notification-service/service.yaml
```

**4. frontend**: the web UI (Deployment and Service are in one file here)

```bash
sed "s|DOCKER_USERNAME|${DOCKER_USERNAME}|g" \
  "$STAGE0/frontend/deployment.yaml" | kubectl apply -f -
```

**Verify** (all app pods should reach `Running`: auth and ledger may take ~30s while they connect to Postgres):

```bash
kubectl get pods -n clearledger
```

Expected. You should see postgres and redis from earlier layers **plus** new pods for each app (exact pod names vary):

```
NAME                                      READY   STATUS    RESTARTS   AGE
postgres-0                                1/1     Running   0          15m
redis-xxxxxxxxxx-xxxxx                    1/1     Running   0          10m
auth-service-xxxxxxxxxx-xxxxx             1/1     Running   0          45s
auth-service-xxxxxxxxxx-xxxxx             1/1     Running   0          45s
ledger-service-xxxxxxxxxx-xxxxx           1/1     Running   0          40s
ledger-service-xxxxxxxxxx-xxxxx           1/1     Running   0          40s
notification-service-xxxxxxxxxx-xxxxx     1/1     Running   0          35s
frontend-xxxxxxxxxx-xxxxx                 1/1     Running   0          30s
```

If auth-service or ledger-service is `CrashLoopBackOff`, check logs:

```bash
kubectl logs -n clearledger deploy/auth-service --tail=20
```

Common cause: you applied `infra/manifests/*/deployment.yaml` instead of the Stage 0 files above: logs may show `DATABASE_URL is not set`. Re-run the `sed` + `kubectl apply` commands in this section.

**✋ Hands-on checkpoint: workloads before ingress**

```bash
kubectl get deployment -n clearledger
kubectl get pods -n clearledger --field-selector=status.phase!=Running
```

Expected: four Deployments (`auth-service`, `ledger-service`, `notification-service`, `frontend`) with `READY` matching desired replicas (auth and ledger show `2/2`). The second command prints **nothing**: no pods stuck in Pending or CrashLoopBackOff.

---

#### 0.5.6 — Layer 6: Ingress

Exposes the cluster to `http://clearledger.local`.

```bash
kubectl apply -f infra/manifests/ingress.yaml
```

**Verify:**

```bash
kubectl get ingress -n clearledger
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/
# Expected: 200
```

---

#### 0.5.7 — Watch until stable

```bash
kubectl get pods -n clearledger -w
```

Expected final state (press Ctrl+C to stop watching once all pods show `Running`):

```
NAME                                  READY   STATUS    RESTARTS
auth-service-xxx                      1/1     Running   0
auth-service-yyy                      1/1     Running   0
frontend-xxx                          1/1     Running   0
ledger-service-xxx                    1/1     Running   0
ledger-service-yyy                    1/1     Running   0
notification-service-xxx              1/1     Running   0
postgres-0                            1/1     Running   0
redis-xxx                             1/1     Running   0
```

Pod stuck in `Pending` or `CrashLoopBackOff`? These two commands show you what went wrong:

```bash
kubectl describe pod POD_NAME -n clearledger
kubectl logs POD_NAME -n clearledger --previous
```

---

### 0.6 — Verify the running system

Use **one test account** for both browser and curl so nothing conflicts:

| Field | Value |
|---|---|
| Email | `test@clearledger.io` |
| Password | `SecurePass123` |

If you already registered in the browser with a **different** password, either sign in with that password or pick a new email: the curl commands below must use the **same** email and password you actually registered with.

**Browser verification (recommended):**

Open `http://clearledger.local` in your browser. You should see the ClearLedger login screen.

1. Click **Register** and create an account with **`test@clearledger.io`** / **`SecurePass123`** (same as the curl block below. Pydantic rejects obviously fake emails like `test@test.com`)
2. Sign in with that email and password
3. On first login the dashboard auto-seeds demo transactions. Wait a few seconds for them to appear
4. Look at the **Current Balance** card. It should show a dollar amount with a sparkline chart
5. Look at **Transaction History**. You should see entries like "Salary (Acme Corp", "Rent) May 2026", and so on
6. Look at the **Alerts** panel at the bottom. You should see `LARGE_TRANSACTION` alerts with a red badge. Two of the demo transactions exceed $10,000, which triggers the compliance alert automatically
7. Submit your own transaction over $10,000: watch the alert count increase in real time

**What to look for:**

- Balance updates immediately after each transaction
- Credits show as green `+$` amounts, debits show as red `−$` amounts
- The Alerts badge count increases when you submit a transaction ≥ $10,000
- Each alert shows the amount, direction, and timestamp

**Take a screenshot of the dashboard showing transactions and at least one alert.** This is the first piece of your portfolio.

**Alternatively via curl** (same account: useful if the browser is not cooperating):

```bash
# Register (skip if you already registered in the browser with the same email)
curl -s -X POST http://clearledger.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' | jq .
```

Expected: `{"user_id":"...","email":"test@clearledger.io"}`, or an error that the email is already registered (fine if you used the browser first).

```bash
# Login — save the token (must match the password you registered with)
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' \
  | jq -r .access_token)
echo "Token: ${TOKEN:0:30}..."
```

If `TOKEN` is empty or login returns `401`, your browser password does not match: re-register with the table above or use your actual password in the `-d` JSON.

```bash
# Create a large transaction (triggers notification alert)
curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":15000,"direction":"debit","description":"Property payment"}' | jq .
```

Expected: a transaction object with `id`, `amount: 15000`, `direction: "debit"`

```bash
# Check balance
curl -s http://clearledger.local/ledger/balance \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Confirm the notification alert fired
curl -s http://clearledger.local/notifications/alerts | jq .
```

Expected (curl-only path, no browser demo seed): at least one alert for the $15,000 transaction, for example, `{"total":1,"alerts":[{"type":"LARGE_TRANSACTION","amount":15000,...}]}`. If you already used the browser, `total` may be **3 or more** (two demo alerts plus yours), that is also correct.

> **If you see `{"detail":"Unauthorized"}`:** your token has expired. JWTs are short-lived for security. This is intentional. Re-run the login command above to get a fresh token, then retry the failed command. This only affects the `$TOKEN` variable in your current terminal session. If you open a new terminal, you need to run the login command again because `$TOKEN` does not persist across sessions.

```bash
make check-0
```

---

### Understanding Ingress (optional)

Read this after §0.6 if you want to understand how `clearledger.local` reaches your pods.

Your cluster runs four application services: frontend, auth-service, ledger-service, and notification-service. Each has an internal **Service** address inside the cluster, but none are reachable from your browser until an **Ingress** routes external traffic.

The Ingress is the front door: when a request hits `clearledger.local`, Kubernetes looks at the URL path and forwards to the right service. Requests to `/auth` go to auth-service, `/ledger` to ledger-service, `/notifications` to notification-service, and `/` to the frontend.

Open [`infra/manifests/ingress.yaml`](./infra/manifests/ingress.yaml) and read the comments. The API paths use a **rewrite:** `/auth/login` becomes `/login` before it reaches auth-service, so backend routes stay simple.

You'll add more hostnames later (`grafana.local`, `argocd.local`, etc.): each gets its own Ingress manifest in a later stage. This file is only the ClearLedger app.

---

### Understanding RBAC (optional)

Ingress controls **outside** traffic: which service gets a browser request. **RBAC** controls **inside** the cluster: what a pod (or someone with `kubectl`) may do when talking to the Kubernetes API.

Open [`infra/manifests/rbac/rbac.yaml`](../infra/manifests/rbac/rbac.yaml); the comments at the top mirror this walkthrough.

**Step 1. Give each app an identity.** Every pod runs as a **ServiceAccount**. When auth-service calls the Kubernetes API, the cluster knows *which* app is asking.

**Step 2 (Define what that identity may do.** A **Role** lists allowed actions) for example, auth-service may `get` and `list` **Endpoints** so it can discover Postgres. It may *not* read Secrets or touch other namespaces.

**Step 3. Attach permissions to the identity.** A **RoleBinding** connects a ServiceAccount to a Role.

**Step 4. Separate humans from apps.** A **viewer** ServiceAccount can inspect pods and services for debugging, but cannot read Secrets.

**Step 5. Lock down the default.** Pods without `serviceAccountName` fall back to the namespace **default** account: here, deliberately given **zero** permissions.

If auth-service were compromised, tight RBAC limits blast radius to what that app was ever allowed to do.

---

### 0.7 — Why manual deploys can't be trusted

In Stage 0, you built and deployed the app by hand. Now you will make one small code change and deploy it again. This shows the problem with manual deployments: they are hard to track, hard to roll back, and hard to prove. Stages 1 and 2 fix that with CI and GitOps.

**Step 1. Make a visible change.**

Open `app/auth-service/main.py` and find the `/health` endpoint. Change the return value so you can tell the new version is running:

```python
# Before
return {"status": "ok", "service": settings.service_name}

# After — add a version field
return {"status": "ok", "service": settings.service_name, "version": "0.2.0"}
```

Save the file. This simulates a developer shipping a small fix.

**Step 2. Build, push, and deploy by hand.**

```bash
docker build -t $DOCKER_USERNAME/clearledger-auth-service:v0.2.0 ./app/auth-service
docker push $DOCKER_USERNAME/clearledger-auth-service:v0.2.0
kubectl set image deployment/auth-service \
  auth-service=$DOCKER_USERNAME/clearledger-auth-service:v0.2.0 \
  -n clearledger
```

Wait about 30 seconds for Kubernetes to pull the new image and restart the pods:

```bash
kubectl rollout status deployment/auth-service -n clearledger
```

**Step 3. Verify your change is live.**

```bash
curl -s http://clearledger.local/auth/health | jq .
```

Expected: `{"status":"ok","service":"auth-service","version":"0.2.0"}`

If you still see the old response without `"version"`, wait a few more seconds and retry. Kubernetes is still rolling out the new pods.

**Step 4. Notice what manual deploy doesn't give you.**

You deployed a change. It works. But think about what just happened:

- **Who deployed this?** There is no record. You ran `kubectl` from your laptop. If three people have cluster access, no one knows who changed what.
- **What changed?** The only evidence is the Docker Hub tag `v0.2.0`. Nothing links that tag to a specific commit or code review.
- **What if `v0.2.0` is broken?** You would need to remember the previous tag, then run `kubectl set image` again to roll back. What if you do not remember the tag? What if the previous image was deleted?
- **What if someone else runs `kubectl apply` with `v0.1.0` while you are pushing `v0.2.0`?** The cluster silently reverts to the old version. No error. No notification. You think your fix is live, but it is not.
- **Where is the audit trail?** Nowhere. In a regulated environment (banking, healthcare, government), you need proof of who deployed what and when. Right now you have nothing.

Manual deploys can work for a demo. They don't hold up for a team or a regulated environment. Keep these gaps in mind. They are why the next stages exist.

**Step 5. Revert your change before continuing.**

Undo the health endpoint change in `app/auth-service/main.py` (remove `"version": "0.2.0"`). Do not rebuild: the cluster will keep running `v0.2.0` for now, and Stage 1 will take over image management.

Stage 1 automates the build. Stage 2 fixes the deployment.

### What You Learned in Stage 0

- How to provision a local Kubernetes cluster with Multipass and MicroK8s
- How Kubernetes manifests describe the desired state of your system
- How an Ingress routes external traffic to internal services
- How to build, push, and deploy container images manually
- **Why manual deploys can't be trusted** — no audit trail, no rollback, no consistency

**What you can now put on your CV / say in an interview:**

> Deployed a multi-service application to Kubernetes by hand: namespace, RBAC, a StatefulSet database, Deployments, Services, and path-based Ingress routing, and can explain why each layer deploys in that order.

`make snapshot STAGE=0 && make snapshots`. Confirm `clearledger.stage0`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

---

## Stage 1 — CI Pipeline (GitHub Actions + Self-Hosted Runner)

> In Stage 0 you built and deployed by hand. Stage 1 automates the build: a `git push` runs a pipeline that builds images, scans them, pushes to Docker Hub, and records the new tag in `clearledger-infra`.

**Goal:** every push to GitHub automatically builds images, pushes them to Docker Hub, and updates image tags in `clearledger-infra`.

> **Am I ready for Stage 1?**
>
> Run these **yourself** before §1.1:
>
> ```bash
> make check-0
> echo "$DOCKER_USERNAME"    # must not be empty or "your-username"
> curl -s -o /dev/null -w "%{http_code}" http://clearledger.local/auth/health
> ```
>
> Expected: health check green; `echo` prints your Docker Hub user; curl prints `200`.
>
> - [ ] Docker Hub account with four `clearledger-*` repositories (see [QUICKSTART.md §1b](../QUICKSTART.md#step-1b--docker-hub-setup-required-before-stage-1))
> - [ ] GitHub account; you can create repos and personal access tokens
> - [ ] ~2–4 hours for runner install + first green pipeline (this is the hardest stage for beginners)
>
> **Done when:** `make check-1` passes **and** you manually confirmed the five items in §1.7 below.
> **Then save:** `make snapshot STAGE=1` → `make snapshots` (confirm `clearledger.stage1`).

### What You Need to Know First

In Stage 0, your laptop was the deployment system.

You typed `docker build`, `docker push`, and `kubectl set image` yourself. That worked for a demo, but it is not how teams should ship software. Manual builds create too many unanswered questions:

- Did this image come from the latest code?
- Did someone build it from a dirty working tree?
- Did the build work the same way on another machine?
- Which commit produced the image currently running?
- Who pushed the image, and when?

**CI (Continuous Integration)** fixes the build side of that problem. It means: every time code is pushed, an automated system builds, checks, and packages it the same way every time.

Think of CI as a factory line:

```text
Developer pushes code
        ↓
GitHub detects the push
        ↓
GitHub Actions starts the pipeline
        ↓
Runner executes the jobs
        ↓
Docker images are built and pushed
        ↓
Infra manifests are updated with the new image tags  (in clearledger-infra — §1.3)
```

The important idea: **the build no longer depends on your laptop**. Your laptop writes code. The pipeline produces the release artifact.

A CI system has three parts:

1. **Pipeline host**: the control plane. It notices a push and decides which workflow to run. In this lab, that is **GitHub Actions**.
2. **Pipeline file**: the instructions. It is a YAML file at `.github/workflows/ci.yaml` that says what jobs to run.
3. **Runner**: the worker machine. It actually executes the commands in the pipeline.

GitHub Actions normally uses GitHub-hosted runners in the cloud. In this lab, that is not enough. Your Kubernetes cluster lives inside a local Multipass VM. GitHub's cloud runner cannot reach it. You also need the runner inside the VM to build Docker images using the local Docker daemon.

So you install a **self-hosted runner** inside the VM. It connects outbound to GitHub, waits for work, then executes pipeline jobs locally where it can reach everything.

**Two repos, `clearledger` (code + CI) and `clearledger-infra` (Kubernetes YAML only).** You create the second in §1.3.

```text
GitHub — clearledger (app repo)
  stores your code
  starts the workflow on git push
        ↓
Self-hosted runner (inside Multipass VM)
  builds Docker images
  pushes images to Docker Hub
  updates image tags in clearledger-infra  ← you create this in §1.3
        ↓
GitHub — clearledger-infra (infra repo)
  stores Kubernetes YAML with the new image tags
  ArgoCD watches this repo in Stage 2 (not yet)
```

> **Stages 1–7 vs Stage 8: two pipelines, one repo.** This chapter uses `.github/workflows/ci.yaml` on your **self-hosted** runner (Docker Hub → `clearledger-infra`). Stage 8 adds a second workflow, `.github/workflows/ci-aws.yaml`, that runs on **GitHub-hosted** `ubuntu-latest` runners (ECR → in-repo kustomization). Fresh starters **do not** set anything extra (homelab CI is the default until you opt into AWS in §8. See [§8) CI routing and `CLEARLEDGER_CI_TARGET`](#heading-ci-routing-stages-17-vs-stage-8).

---

### 1.1 — Push the app repo to GitHub (not `clearledger-infra` yet)

This step is **repo #1, `clearledger`** (application code + CI workflow). You are pushing the clone on your laptop: the same folder where you ran Stage 0 (`make setup`, `kubectl apply`, and so on).

**`clearledger-infra` comes later in §1.3.** That second repo holds Kubernetes manifests only. Do not create it here.

First, put the application repo somewhere GitHub Actions can see it.

Go to GitHub → **New Repository**:

- Repository name: **`clearledger`** (exact name, not `clearledger-infra`)
- Visibility: **Public or Private**. Both work with the self-hosted runner and GitHub Actions. ArgoCD never reads this repo (see [Private repos: what syncs where](#heading-private-repos-what-syncs-where) in §1.3).
- Do **not** initialize with a README or `.gitignore`

The repo already has those files locally. If GitHub creates its own, your first push may fail because the histories do not match.

Run from your **local `clearledger` project root** on your Mac (where `app/`, `infra/`, and `.github/workflows/ci.yaml` live):

```bash
cd ~/Desktop/personal-projects/devsecops/clearledger   # your clone path
git remote add origin https://github.com/YOUR_USERNAME/clearledger.git
git branch -M main
git push -u origin main
```

If `git remote add` fails because `origin` already exists:

```bash
git remote -v
git remote set-url origin https://github.com/YOUR_USERNAME/clearledger.git
git push -u origin main
```

Verify in the browser: `https://github.com/YOUR_USERNAME/clearledger`.

You should see `app/`, `infra/manifests/`, `docs/`, and `.github/workflows/ci.yaml`. That confirms GitHub can trigger the pipeline on your next push.

**What you proved:** the **app repo** is on GitHub. CI will run from here. Deployment manifests for GitOps land in **`clearledger-infra`** in §1.3.

### 1.2 — Install the Self-Hosted Runner Inside the VM

The workflow file tells GitHub *what* to run. The runner is *where* it runs.

This lab uses a self-hosted runner because your infrastructure is local. GitHub's cloud servers cannot reach your MicroK8s cluster or Docker daemon inside the Multipass VM. The runner solves that by living inside the VM. It connects outbound to GitHub to pick up jobs, then executes everything locally.

```
GitHub (cloud) — clearledger app repo
  sees the git push
  schedules a workflow job
  ↓
Self-hosted runner (inside VM)
  receives the job
  builds Docker images
  pushes images to Docker Hub
  updates image tags in clearledger-infra  ← §1.3 creates this repo
```

If the runner is missing or offline, the pipeline cannot execute. The workflow may sit queued, or it may fail because no matching runner is available.

**Step 1. Open GitHub’s runner setup page (keep this tab open)**

GitHub gives you a full copy-paste install guide on one page. Use it: don’t hunt for URLs or tokens elsewhere.

1. Open **`https://github.com/YOUR_USERNAME/clearledger`**
2. **Settings** → **Actions** → **Runners** → **New self-hosted runner**
3. Select **Linux** and **x64**

The page title should look like: **Add new self-hosted runner · YOUR_USERNAME/clearledger**.

That page has three sections you will use:

| Section on GitHub | What to do with it |
|---|---|
| **Download** | Copy the `mkdir`, `curl`, and `tar` commands into the VM in Step 4 (same versions as below) |
| **Configure** | Copy the **token** from the `./config.sh ... --token ...` line — do **not** run GitHub’s `./config.sh` as-is |
| **Using your self-hosted runner** | Ignore for now — the lab workflow needs the `clearledger` label (Step 4) |

Scroll to **Configure**. You will see something like:

```bash
./config.sh --url https://github.com/YOUR_USERNAME/clearledger --token AXXXXXXXXXXXXXXXXXXXXXXXXX
./run.sh
```

**The token is the long string after `--token`** (starts with `A`, about 26 characters). Copy **only** that string.

Keep this tab open until Step 4 finishes: the token expires in about **1 hour**. If it expires, click **New self-hosted runner** again for a fresh token.

**Step 2. Enter the VM**

```bash
multipass shell clearledger
```

> **STOP. Check your prompt before continuing.**
>
> After running `multipass shell clearledger`, your terminal prompt should change to something like:
> ```
> ubuntu@clearledger:~$
> ```
> If your prompt still shows your Mac username (for example, `mac@192` or `yourname@MacBook`), you are still on your host machine.
> The runner binary is compiled for Linux. Running it on macOS will fail with:
> `cannot execute binary file`
>
> Do not proceed until your prompt shows `ubuntu@clearledger`.

**Everything from Step 3 onwards runs inside the VM, not on your Mac.**

**Step 3. Install Docker inside the VM**

The runner will build Docker images. That means Docker must exist where the runner runs.

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu
newgrp docker

docker --version
```

Expected: Docker prints a version number (for example, `Docker version 29.x.x`).

**Verify Docker works for the `ubuntu` user now**: the runner does not exist yet (Step 4 creates `~/actions-runner`):

```bash
docker ps
```

Expected: a table header (CONTAINER ID, IMAGE, …), even if no containers are listed. **Not** `permission denied while trying to connect to the Docker API`.

If `docker ps` fails with permission denied, the `docker` group has not applied yet. Run `newgrp docker` again, or log out of the VM (`exit`) and `multipass shell clearledger` back in, then retry `docker ps`.

What you proved: the VM can run Docker without Docker Desktop on your Mac. Continue to Step 4 to install the runner.

**Step 4. Install and register the runner**

Still inside the VM (`ubuntu@clearledger` prompt).

**Download:** you can copy the commands from the **Download** section on GitHub’s runner page (Step 1), or run the block below. They should match. Paste into the VM, not your Mac.

**Configure:** use the lab command below, not GitHub’s `./config.sh` line. Paste your token from Step 1 and replace `YOUR_USERNAME`.

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner

curl -o actions-runner-linux-x64-2.335.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.335.1/actions-runner-linux-x64-2.335.1.tar.gz

tar xzf ./actions-runner-linux-x64-2.335.1.tar.gz

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

Do **not** run GitHub’s `./run.sh` for day-to-day use: the lab uses `sudo ./svc.sh` so the runner survives VM reboots. GitHub shows `./run.sh` for a quick test only.

Expected after `./config.sh`: `Runner successfully added` (or similar). If you see **Invalid token** or **Expired token**, go back to Step 1 in the browser and copy a fresh token.

The **`clearledger` label is required**. GitHub’s default `./config.sh` on the setup page does not add it. The workflow uses:

```yaml
runs-on: [self-hosted, clearledger]
```

GitHub schedules jobs by runner **labels**, not by runner name. A runner named `clearledger` without the `clearledger` label will stay online but jobs will remain queued with `Waiting for a runner to pick up this job`.

Check it locally from the same folder, still inside the VM:

```bash
cd ~/actions-runner
sudo ./svc.sh status
```

Expected: the service is installed and running.

**If a CI job fails with Docker socket permission denied** (the runner started before the `docker` group applied), restart it:

```bash
cd ~/actions-runner
sudo ./svc.sh stop && sudo ./svc.sh start
docker ps    # must work without sudo
```

If you see this:

```text
not installed
```

then `sudo ./svc.sh install` did not run successfully. Run:

```bash
cd ~/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

If `install` fails, rerun `./config.sh` with a fresh GitHub runner token, then run the install/start commands again.

**Step 5. Exit the VM**

```bash
exit
```

**Step 6. Verify the runner is connected**

Go to: github.com/YOUR_USERNAME/clearledger → Settings → Actions → Runners

You should see `clearledger-runner` with a green dot and status **Idle**. Open the runner details and confirm the labels include:

```text
self-hosted
Linux
X64
clearledger
```

If `clearledger` is missing, add it in the runner settings before rerunning the workflow. The runner name alone is not enough.

**✋ Hands-on checkpoint: runner ready for jobs**

Still on GitHub → Settings → Actions → Runners, confirm:

| Field | Expected |
|---|---|
| Status | **Idle** (green) |
| Labels | includes `self-hosted` **and** `clearledger` |
| OS | Linux |

Then trigger a dry run from your laptop (no code change needed):

```bash
git commit --allow-empty -m "test: verify runner picks up jobs"
git push
```

Open `https://github.com/YOUR_USERNAME/clearledger/actions`: within 30 seconds a workflow run should show **Queued** then **In progress**, not stuck on “Waiting for a runner.” If it waits more than 2 minutes, the labels are wrong: edit the runner on GitHub and add `clearledger`.

If it shows Offline:

```bash
multipass exec clearledger -- sudo systemctl status actions.runner.*.service
multipass exec clearledger -- journalctl -u actions.runner.*.service --lines=50
```

What you proved: GitHub can now send work into your local lab environment.

### 1.3 — Create the Infra Repo on GitHub

Now separate **application code** from **deployment state**. Stage 1 introduces a second GitHub repository alongside the `clearledger` app repo you pushed in §1.1.

You will use two repositories for the rest of the lab:

| Repo | What lives there | Who changes it | Why it exists |
|---|---|---|---|
| `clearledger` | App source code, Dockerfiles, tests, `.github/workflows/ci.yaml`, lab docs | You, the developer | This is where code changes start |
| `clearledger-infra` | Kubernetes manifests only: `deployment.yaml`, `service.yaml`, ingress, secrets templates | The CI pipeline, then ArgoCD reads it | This is the desired state of the cluster |

Think of **`clearledger`** as the question *“What is the application?”*. Python services, Dockerfiles, tests, and the CI workflow. Think of **`clearledger-infra`** as *“What exact version should be running in Kubernetes right now?”*. Deployments, Services, ingress rules, and the image tags that point at Docker Hub.

Teams split these on purpose. If you edit `README.md` in `clearledger`, that is a documentation change. It should not trigger a deployment. If you change `auth-service` code, the pipeline builds a new image (for example tag `abc123`) and, only after scans pass, records that tag in `clearledger-infra`:

```yaml
image: $DOCKER_USERNAME/clearledger-auth-service:abc123
```

That line is a **deployment contract**: Git now says the cluster *should* run `abc123`. In Stage 1, the cluster does not change yet. You will prove that in §1.6. In **Stage 2**, ArgoCD watches `clearledger-infra`, compares Git to what is running, and syncs the cluster when they differ. The app repo is where work begins. The infra repo is what production is supposed to look like.


#### Private repos — what syncs where

This lab uses two GitHub repos. **`clearledger`** is your main project repo: app code, CI pipeline, docs, policies, and lab files. This repo can be private.

**`clearledger-infra`** contains only Kubernetes manifests. ArgoCD watches this repo and uses it to deploy the app. For beginners, make this repo public so ArgoCD can read it without extra authentication.

The flow looks like this:

```text
clearledger
app code + infra/manifests/
        ↓
CI copies infra/manifests/
        ↓
clearledger-infra
Kubernetes manifests only
        ↓
ArgoCD syncs from this repo
        ↓
Kubernetes cluster
```

ArgoCD does not read the main `clearledger` repo. It only reads `clearledger-infra`. If `clearledger` is private, that is fine. If `clearledger-infra` is private, you must give ArgoCD GitHub credentials later. If you do not, ArgoCD may show `ComparisonError`.

Create the infra repo on GitHub:

1. Go to GitHub → **New Repository**
2. Name it **`clearledger-infra`**
3. Choose **Public**
4. Do not add a README
5. Click **Create**

Later, the CI pipeline will update `clearledger-infra` automatically. In Stage 1, the pipeline does not run `kubectl apply`; it updates Git. In Stage 2, ArgoCD reads that Git repo and applies it to the cluster.

**Before pushing:** set your Docker Hub username in Kustomize (image tags are resolved here, not in deployment YAML):

```bash
# Replace YOUR_DOCKERHUB_USERNAME with the same value as $DOCKER_USERNAME from §0.3
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/${DOCKER_USERNAME}/g" infra/manifests/kustomization.yaml
rm -f infra/manifests/kustomization.yaml.bak
```

Push only the Kubernetes manifests from `infra/manifests/` (not everything under `infra/`):

```bash
mkdir -p /tmp/clearledger-infra
cp -r infra/manifests /tmp/clearledger-infra/
cd /tmp/clearledger-infra
git init
git remote add origin https://github.com/YOUR_USERNAME/clearledger-infra.git
git add . && git commit -m "feat: initial manifests" && git push -u origin main
cd -
```

**✋ Hands-on checkpoint: infra repo on GitHub (do this before §1.4)**

On your laptop:

```bash
grep "docker.io/${DOCKER_USERNAME}/" infra/manifests/kustomization.yaml | wc -l
grep YOUR_DOCKERHUB_USERNAME infra/manifests/kustomization.yaml || echo "OK: placeholder replaced"
```

Expected: first command prints `4` (four image lines). Second prints `OK: placeholder replaced`, not four lines still saying `YOUR_DOCKERHUB_USERNAME`.

In the browser, open `https://github.com/YOUR_USERNAME/clearledger-infra/tree/main/manifests` and confirm **with your eyes**:

| File / folder | Must exist |
|---|---|
| `kustomization.yaml` | Yes — open it; `newName:` lines use **your** Docker Hub user |
| `auth-service/secret.yaml` | Yes — Stages 2–4 need this until Stage 5 |
| `ledger-service/secret.yaml` | Yes |
| `auth-service/deployment.yaml` | Yes — open it; must contain `secretKeyRef`, **not** `vault.hashicorp.com` |
| `netpol/` | **No** — if present, delete the folder on GitHub before Stage 2 |
| `vault/` | **No** — Vault rotation is Stage 5 only |

**Which folders matter?** You only pushed **`infra/manifests/`** to GitHub, that is correct. Everything else in this repo stays local for now. Some manifests for later stages (network policies, Vault extras) live under **`infra/deferred-by-stage/`** in the **`clearledger`** repo; you apply those by hand when you reach that stage: do **not** copy that folder into `clearledger-infra`, or ArgoCD would deploy things too early.

You might notice `stages/stage-1-ci-pipeline/` has no copy of the manifests. That is normal: the lab does not duplicate YAML there. The canonical copy is **`infra/manifests/`** in this repo, and the live GitOps copy is **`clearledger-infra`** on GitHub.

**What you proved:** Kubernetes config now has its own repo and Git history, separate from application code. CI will update `clearledger-infra` after each build; your app repo stays for code and the pipeline file.

### 1.4 — Set up GitHub Secrets

Go to: `github.com/YOUR_USERNAME/clearledger` → Settings → Secrets and variables → Actions → New repository secret

The workflow needs credentials for Docker Hub, GitHub, and image signing:

- Docker Hub, so it can push images.
- GitHub, so it can push image tag updates into `clearledger-infra`.
- Cosign, so it can sign the images after pushing them.

Do **not** paste these values into YAML files. Store them as GitHub Actions secrets.

**Secret 1, `DOCKER_USERNAME`**

This is just your Docker Hub username.

Example:

```text
veeno-demo
```

Get it from Docker Hub: hub.docker.com → profile menu → Account Settings.

**Secret 2, `DOCKER_PASSWORD`**

This should be a Docker Hub **access token**, not your normal Docker Hub password.

Create it here:

```text
hub.docker.com
→ Account Settings
→ Security
→ New Access Token
→ Description: clearledger-github-actions
→ Access permissions: Read, Write, Delete or Read/Write
→ Generate
```

Copy the token immediately. Docker Hub only shows it once.

**Secret 3, `INFRA_REPO_TOKEN`**

This is a GitHub Personal Access Token (PAT). The pipeline uses it to push commits to the second repo, `clearledger-infra`.

Create it here:

```text
GitHub profile settings
→ Settings
→ Developer settings
→ Personal access tokens
→ Tokens (classic)
→ Click "Generate new token"
→ Choose "Generate new token (classic)"
→ If GitHub asks for your password or 2FA, complete it
→ Note: clearledger-infra-ci
→ Expiration: choose a lab-friendly value
→ Select scope: repo
   This allows the pipeline to push to clearledger-infra.
→ Generate token
```

Copy the token immediately. GitHub only shows it once.

For this lab, `repo` scope is the simplest option. In production, you would use tighter permissions, such as a fine-grained token limited to only `clearledger-infra`.

**Secrets 4 and 5, `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD`**

Cosign signs container images after the pipeline pushes them to Docker Hub. Later, Stage 4 uses the public key with Kyverno so the cluster can verify that images came from your trusted pipeline.

Generate the key pair on your host machine, not inside the Multipass VM:

```bash
# macOS: brew install cosign
# Linux/WSL2: curl -sSL -o cosign https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 && chmod +x cosign && sudo mv cosign /usr/local/bin/
cosign generate-key-pair
```

This creates:

```text
cosign.key   # private key — never commit this
cosign.pub   # public key — keep for later Kyverno verification
```

When Cosign asks for a password, enter one and save it in your password manager. If you already generated a key without a password, regenerate it with a password for this lab.

Add these five secrets to the `clearledger` repo, not `clearledger-infra`:

| Secret name | Value | Purpose |
|---|---|---|
| `DOCKER_USERNAME` | Your Docker Hub username | Pipeline logs in to push images |
| `DOCKER_PASSWORD` | Your Docker Hub access token | Pipeline authenticates with Docker Hub |
| `INFRA_REPO_TOKEN` | The GitHub PAT from above | Pipeline pushes image tag updates to clearledger-infra |
| `COSIGN_PRIVATE_KEY` | Contents of `cosign.key` | Pipeline signs pushed container images |
| `COSIGN_PASSWORD` | Password used when creating the Cosign key | Unlocks the private key during signing |

**Repository variables (not secrets)** (optional) toggles for later stages. Add under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Stage 1 | When to enable |
|---|---|---|
| `ENABLE_ARGOCD_SYNC` | Leave **unset** | **Stage 2** — after ArgoCD’s first sync is healthy (see [Enable CI → ArgoCD handoff](#heading-how-to-enable-the-ci-to-argocd-handoff)) |
| `ENABLE_DAST` | Leave **unset** | **Stage 3** — after the app is live at `clearledger.local` (see [Enable DAST](#heading-enable-dast-optional-after-stage-2)) |

**Do not add either variable in Stage 1.** If you set them now, CI will try to refresh ArgoCD or run ZAP before the cluster is ready, and the pipeline output gets harder to read. The guide calls out the exact moment to turn each one on; you only need to remember that both exist.

What you proved: the pipeline can authenticate to external systems without hardcoding credentials in the repo.

### 1.5 — Understand the pipeline before activating it

Do not treat the workflow file as magic. Open `.github/workflows/ci.yaml` and read it before you run it.

The pipeline has two responsibilities:

1. Prove the code and images are safe enough to publish.
2. Update the infra repo with the new image tags.

Here is the security flow first:

```text
Developer pushes code to GitHub
        ↓
GitHub Actions starts workflow
        ↓
Self-hosted runner inside the Multipass VM picks up the job
        ↓
1. Scan secrets (Gitleaks)
        ↓
2. Run code security scans (Semgrep) + IaC scan (Checkov) — parallel
        ↓
3. Prepare scanners (install Trivy/Syft/Grype/Cosign once; refresh Trivy DB once)
        ↓
4. BUILD — docker build all four services (local tags only; nothing hits Docker Hub yet)
        ↓
5. SCAN — Trivy on all images; Syft + Grype SBOM on auth-service; upload evidence
        ↓
6. PUBLISH — push to Docker Hub + Cosign sign (only if scan passed)
        ↓
7. UPDATE MANIFESTS — commit new image tags to clearledger-infra
```

#### Build → scan → publish (prod-style gates)

Real teams **never push first and scan later**. The pipeline separates three concerns into three jobs in `.github/workflows/ci.yaml`:

| Job | What it does | If it fails… |
|---|---|---|
| `build-images` | `docker build` all services with tag `${{ github.sha }}` | No registry pollution — images never left the runner |
| `scan-images` | Trivy (all 4 images); Syft + Grype (auth only) | Publish is skipped — bad images never reach Docker Hub |
| `publish-images` | Runs `scripts/ci-publish-image.sh` — tag, push, Cosign sign | Only runs after scan passes |

You do **not** run `scripts/ci-publish-image.sh` yourself before pushing code. GitHub Actions checks out the repo and calls it inside `publish-images`.

**Why can `build-images` and `scan-images` be separate jobs?** Each job is a fresh checkout on GitHub-hosted runners. They do not share a disk. On **your** self-hosted runner, all three jobs run on the **same Multipass VM** and use the **same Docker engine**. Job 1 runs `docker build` and leaves the images on that machine. Job 2 runs Trivy against those same local images: no upload, no download. Job 3 pushes to Docker Hub only if the scan passed.

That is a practical lab setup: one persistent build machine with Docker installed, like a dedicated CI worker in a real office. In **Stage 8 (AWS)**, the pipeline uses GitHub-hosted runners instead: there, `build-images` saves the images to a file (`images.tar`) and passes that file to the next job as a workflow artifact, because those runners are throwaway VMs with no shared Docker cache.

Then comes the GitOps handoff:

```text
Secure images now exist in Docker Hub
        ↓
Runner checks out clearledger-infra from GitHub
        ↓
Deployment YAML image tags are updated
        ↓
Runner commits and pushes back to clearledger-infra
        ↓
Stage 1 ends here
```

**How the image tag ties to your code:** every pipeline run is triggered by a git commit. GitHub gives that commit a unique ID called the **SHA** (a long hex string like `a1b2c3d4e5f6789…`). The workflow sets `IMAGE_TAG` to that SHA and uses it everywhere:

1. **Build:** `docker build -t clearledger-auth-service:a1b2c3d4…`
2. **Publish:** push to Docker Hub as `YOUR_DOCKERHUB_USERNAME/clearledger-auth-service:a1b2c3d4…`
3. **Update manifests:** `kustomize edit set image …:a1b2c3d4…` in `clearledger-infra`
4. **Commit message:** `ci: deploy a1b2c3d4… — all gates passed`

So if production is running `YOUR_DOCKERHUB_USERNAME/clearledger-auth-service:a1b2c3d4…`, you paste that tag into GitHub (`https://github.com/YOUR_GITHUB_USERNAME/clearledger/commit/a1b2c3d4…`) and see the **exact source code** that built it. No guessing, no “maybe it was `latest`”. That one-to-one link is why teams use commit SHAs instead of floating tags like `v0.1.0` for deploys.

**The Kustomize placeholder.**

`auth-service/deployment.yaml` uses a label instead of a real image address:

```yaml
image: clearledger/auth-service:gitops
```

That label is not on Docker Hub. It tells Kustomize where to substitute. The real address lives in `kustomization.yaml`:

```yaml
images:
  - name: clearledger/auth-service          # matches the label above
    newName: docker.io/YOUR_DOCKERHUB_USERNAME/clearledger-auth-service
    newTag: abc123def456…                   # real commit SHA — CI writes this
```

When ArgoCD deploys, `kustomize build` swaps the label for the full address.

You edit `kustomization.yaml` once in §1.3 to set your Docker Hub username in `newName:`. After that, CI writes `newTag:` automatically on every green push. You never touch it by hand.

**Stage 1: CI updates GitHub, not the cluster**

After a green pipeline run, three things are true:

- New images exist on Docker Hub
- `clearledger-infra` on GitHub has new SHAs in `kustomization.yaml`
- Your Kubernetes cluster is **unchanged**. Still running whatever Stage 0 left there

CI never runs `kubectl apply`. It only commits to `clearledger-infra`. That is the whole Stage 1 lesson: build and scan are automated, but **deploy** is not: yet. Stage 2 installs ArgoCD, which reads `clearledger-infra` and updates the cluster for you.

**Kubernetes Checkov** runs in Stage 1 but does **not** block the pipeline. It uploads findings so you can see hardening work ahead. Stage 4 turns those kinds of rules into cluster enforcement with Kyverno.

> Jobs run on your self-hosted runner (`runs-on: [self-hosted, clearledger]`). Both `ENABLE_ARGOCD_SYNC` and `ENABLE_DAST` are unset in Stage 1. See §1.4 for when each gets flipped.

If a job fails, start with [`docs/troubleshooting.md#stage-1-ci-troubleshooting`](troubleshooting.md#stage-1-ci-troubleshooting) before editing the workflow.

---

#### Stage 1 security posture — what blocks vs what waits

Stage 1 is not “security off.” Some gates **stop the pipeline**; others **run for evidence** and tighten in later stages.

**Blocks the pipeline today**

- Gitleaks (secrets in Git)
- Semgrep (SAST on Python)
- Checkov on Dockerfiles
- Trivy (fixable HIGH/CRITICAL CVEs in images)
- Grype on auth-service SBOM (fixable HIGH+)
- Manifest update to `clearledger-infra` (must succeed)

**Runs but does not block yet**

- Checkov on Kubernetes manifests → enforced in **Stage 4** (Kyverno)
- Cosign sign + SLSA attest → enforced in **Stage 4** (unsigned images rejected)
- Syft SBOM generation → supply-chain evidence; you break gates on purpose in **Stage 3**
- ArgoCD refresh → **Stage 2** (`ENABLE_ARGOCD_SYNC=true`)
- DAST / ZAP → **Stage 3** (`ENABLE_DAST=true`)

**If you forget which stage fixes what**, search this guide for “Stage 1 security posture” or follow the stage order: Stage 3 breaks gates on purpose, Stage 4 connects Checkov findings to Kyverno, Stage 5 moves secrets off Git, Stage 6 adds runtime detection, Stage 7 adds dashboards. Run `make check-3` and `make check-4` after those stages to confirm hardening landed.

> **Design intent:** Stage 1 proves CI can build, scan, push, and update Git without you touching Docker manually. Later stages turn evidence into enforcement. The relaxations here are deliberate.

### 1.6 — Activate the pipeline

**Run this in the `clearledger` app repo, not `clearledger-infra`.**

§1.3 created `clearledger-infra` with only Kubernetes manifests. It has no `.github/workflows/` and no pipeline. If your shell prompt says `clearledger-infra`, or you used `/tmp/clearledger-infra`, you are in the wrong place.

```bash
cd /path/to/clearledger          # the app repo you pushed in §1.1
git remote -v                    # must show .../clearledger.git — NOT clearledger-infra
ls .github/workflows/ci.yaml     # must exist before you commit
```

The pipeline file already lives at `.github/workflows/ci.yaml`. Push any small change to **`clearledger`** on `main`:

```bash
echo "# Pipeline activated $(date)" >> README.md
git add README.md
git commit -m "ci: activate GitHub Actions pipeline"
git push origin main
```

Watch the run at: `https://github.com/YOUR_USERNAME/clearledger/actions` (app repo Actions tab, not the infra repo).

When the pipeline succeeds, it updates **`clearledger-infra`** for you. You do not need to push anything to the infra repo by hand for this step.

Expected: all jobs green in about 8 minutes.

```
✓ Build + Scan auth-service
✓ Build + Scan ledger-service
✓ Build + Scan notification-service
✓ Build + Scan frontend
✓ Update manifests → GitHub
```

DAST and the ArgoCD refresh step show as **skipped**: expected. Both toggles are unset until later (see §1.4).

Note: this lab includes `.gitleaksignore` because some intentional demo secrets are already present in git history. Gitleaks still runs normally. The ignore file only suppresses known lab fingerprints. Do not add new findings to it unless you have confirmed they are intentional test data.

Click into the job logs and look for the story. Do not just wait for green:

- Docker login succeeded
- Each service image built and pushed to Docker Hub
- `clearledger-infra` was checked out
- Deployment YAMLs were updated with the new SHA tag
- A commit was pushed back to `clearledger-infra`

After the pipeline succeeds, open `https://github.com/YOUR_USERNAME/clearledger-infra` and look at the deployment manifests. The image tags should now use the current commit SHA.

Now check the cluster:

```bash
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}' && echo
```

You may still see the old image. That is expected. This is the most important learning in Stage 1:

```text
GitHub pipeline succeeded.
Docker Hub has new images.
clearledger-infra has new image tags.
The Kubernetes cluster did not update automatically.
```

That is not a failure. It is the deployment gap. Stage 1 automated the build, but no controller is watching the infra repo yet. Stage 2 installs ArgoCD to close that gap.

### 1.7 — Hands-on checkpoint: prove Stage 1 is really done

Do not rely on a green workflow badge alone. Run each check yourself:

**1. Infra repo still has app secrets (critical for Stage 2)**

Open `https://github.com/YOUR_USERNAME/clearledger-infra/tree/main/manifests/auth-service`, `secret.yaml` must be visible.

On your laptop:

```bash
git clone --depth 1 https://github.com/YOUR_USERNAME/clearledger-infra.git /tmp/verify-infra
grep secretKeyRef /tmp/verify-infra/manifests/auth-service/deployment.yaml
grep secret.yaml /tmp/verify-infra/manifests/kustomization.yaml
rm -rf /tmp/verify-infra
```

Expected: `secretKeyRef` in deployment output; kustomization lists `auth-service/secret.yaml` and `ledger-service/secret.yaml`. If secrets are missing, re-push §1.3 manifests before Stage 2.

**2. Kustomize image tags updated by CI**

```bash
git clone --depth 1 https://github.com/YOUR_USERNAME/clearledger-infra.git /tmp/verify-infra
grep newTag /tmp/verify-infra/manifests/kustomization.yaml
rm -rf /tmp/verify-infra
```

Expected: `newTag` is a **40-character git SHA** (or your commit hash), not still `v0.1.0` only: unless you have not pushed since §0.3.

**3. Docker Hub has signed images from this pipeline**

Open hub.docker.com → `clearledger-auth-service` → **Tags**: latest tag should match the SHA from step 2.

**4 (Cluster unchanged (deployment gap) intentional)**

```bash
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}' && echo
```

Expected: still your **Stage 0** tag (for example, `veeno-demo/clearledger-auth-service:v0.1.0`), not the new SHA. That proves CI did not touch the cluster.

**5. Runner still idle**

GitHub → Settings → Actions → Runners → `clearledger-runner` → **Idle**.

```bash
make check-1
```

All five pass → Stage 2.

### What You Learned in Stage 1

- **CI removes your laptop from the build process.** Builds become repeatable, visible, and tied to Git commits.
- **A runner is the worker, not the pipeline itself.** GitHub schedules the job; the self-hosted runner executes it inside your VM.
- **Artifacts and desired state are different things.** Docker Hub stores built images. `clearledger-infra` on GitHub stores the Kubernetes manifests that say which image should run.
- **Good pipelines do not secretly mutate clusters.** This pipeline updates Git instead of running `kubectl`.
- **The gap that remains:** the infra repo changed, but the cluster did not. Someone still has to apply the change manually. Stage 2 fixes that with GitOps.

**What you can now put on your CV / say in an interview:**

> Built a CI pipeline on a self-hosted GitHub Actions runner that builds and pushes container images on every push, and can debug a workflow that fails before any job is created.

`make snapshot STAGE=1 && make snapshots`. Confirm `clearledger.stage1`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

---

> If you are finding this useful, let's connect on [LinkedIn](https://www.linkedin.com/in/YOUR_LINKEDIN_HANDLE). I write about DevOps weekly: real systems, real incidents, and interview tips on how to get hired. [Join the newsletter](https://YOUR_NEWSLETTER_URL).

<!-- TODO: replace YOUR_LINKEDIN_HANDLE with your real LinkedIn profile slug and YOUR_NEWSLETTER_URL with your real newsletter URL before publishing -->

---

## Stage 2 — GitOps with ArgoCD

> **Git is truth.** The infra repo says what *should* run. **ArgoCD** keeps the cluster matching that and fixes drift on its own.

**Goal:** Install ArgoCD so it watches `clearledger-infra` and deploys to the cluster. CI still only updates Git; it never runs `kubectl`.

> **Am I ready for Stage 2?**
>
> Complete §1.6 first. Then run:
>
> ```bash
> make check-1
> grep secretKeyRef infra/manifests/auth-service/deployment.yaml
> grep vault.hashicorp infra/manifests/auth-service/deployment.yaml && echo "STOP: Vault annotations present" || echo "OK"
> ```
>
> Expected: check-1 green; `secretKeyRef` present; `OK` (no Vault annotations in Stages 2–4).
>
> - [ ] `clearledger-infra` on GitHub has `auth-service/secret.yaml` and `ledger-service/secret.yaml`
> - [ ] Self-hosted runner **Idle** with label `clearledger`
> - [ ] Repository variable `ENABLE_ARGOCD_SYNC` is **not** set yet (Stage 1). You enable it after ArgoCD is installed below
>
> **Done when:** `make check-2` passes and `http://argocd.local` shows ArgoCD syncing `clearledger`.
> **Then save:** `make snapshot STAGE=2` → `make snapshots` (confirm `clearledger.stage2`).

### What You Need to Know First

**The gap from Stage 1:** CI already builds images and updates `clearledger-infra`. The cluster did not change until someone ran `kubectl`. This stage closes that last step.

| Who | Job |
|---|---|
| **CI** (Stage 1) | Build → scan → push images → update image tags in `clearledger-infra` |
| **ArgoCD** (Stage 2) | Watch `clearledger-infra` → apply manifests → cluster runs what Git says |

```text
push code → CI updates clearledger-infra → ArgoCD syncs cluster
```

### Pre-sync checklist — run before `argocd app sync`

ArgoCD applies whatever is in `clearledger-infra`. Wrong content causes red pods. Re-run the §1.7 checkpoint table to confirm GitHub-side content is still correct, then verify the laptop side:

```bash
# Application manifest must point at YOUR infra repo
grep repoURL stages/stage-2-gitops/argocd/clearledger-app.yaml

# Stage 0 workloads still healthy before ArgoCD takes over
kubectl get pods -n clearledger
curl -s -o /dev/null -w "%{http_code}" http://clearledger.local/auth/health
```

Expected: `repoURL` contains your GitHub username; all app pods `Running`; curl `200`. Only when both pass → install ArgoCD and sync below.

---

```bash
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd --server-side --force-conflicts -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s
```

**Why `--server-side --force-conflicts`?** Argo CD ships a very large `applicationsets.argoproj.io` CRD. A normal `kubectl apply` tries to stash the whole thing in an annotation, hits a 256 KiB limit, and errors with `metadata.annotations: Too long`. Server-side apply avoids that. It is [how Argo CD expects you to install](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/), not a lab workaround.

Get the admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

**Configure Argo CD for your NGINX ingress.** The browser talks HTTPS to ingress; ingress talks plain HTTP to the Argo CD server. Without this, the UI often breaks with `503` or `ERR_TOO_MANY_REDIRECTS` on live-update URLs (`/api/v1/stream/*`).

```bash
kubectl apply -f stages/stage-2-gitops/infra/argocd-cmd-params.yaml
kubectl apply -f stages/stage-2-gitops/infra/argocd-ingress.yaml
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
```

**Expected in `argocd-cmd-params-cm`:** `server.insecure: "true"`, `server.grpc.web: "true"`, `server.url: https://argocd.local`

Open **`https://argocd.local`**. Login: `admin` and the password from above. Accept the self-signed certificate warning if the browser shows one.

**Expected:** The Applications page loads. In the browser console (F12 → Console), you should not see `401` or `ERR_HTTP2_PROTOCOL_ERROR`. If the UI looks fine in a normal window, you are done: incognito is not required.

**If login fails with `401 Unauthorized`** (often after a config change or a bad earlier login), try a private/incognito window or clear site data for `argocd.local`, then log in again. Still stuck? See [troubleshooting.md. ArgoCD](troubleshooting.md#argocd-ui-401-or-err_http2_protocol_error).

Connect ArgoCD to the infra repo and apply the Application manifest:

**1. Edit `stages/stage-2-gitops/argocd/clearledger-app.yaml`**: set `spec.source.repoURL` to your infra repo (your GitHub username, not `git config user.name`).

**2. Register the repo with Argo CD:**

```bash
# macOS: brew install argocd
argocd login argocd.local --username admin --password YOUR_PASSWORD --insecure --grpc-web

# Public repo
argocd repo add https://github.com/YOUR_USERNAME/clearledger-infra.git --grpc-web

# Private repo — PAT from Stage 1 §1.4 (you saved it as GitHub secret INFRA_REPO_TOKEN)
export INFRA_REPO_TOKEN='ghp_...'   # paste here; GitHub only shows it once at creation
argocd repo add https://github.com/YOUR_USERNAME/clearledger-infra.git \
  --username git --password "$INFRA_REPO_TOKEN" --grpc-web
```

**Verify Argo CD can reach the repo** (do this before applying the Application):

```bash
argocd repo list --grpc-web
```

Look for your `clearledger-infra` URL with **TYPE** `git` and connection **Successful**. If it shows **Failed** or the repo is missing, Argo CD cannot sync: fix credentials before Stage 4 or any stage that depends on GitOps. After a VM restore or Argo CD reinstall, you may need to run `argocd repo add` again (credentials are stored in the cluster, not in Git).

**3. Apply and sync:**

```bash
kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
argocd app sync clearledger --grpc-web
```

### How to read the Argo CD UI (you are not just "looking at a UI")

After sync, open the **clearledger** application in the tree view. Three badges at the top tell you almost everything:

**APP HEALTH: Healthy**. Kubernetes thinks the workloads are running. Pods are up (or still starting if it says Progressing).

**SYNC STATUS: Synced**: the cluster matches `clearledger-infra` on GitHub at the commit shown (for example, `main (2c88aa1)`). Git is the source of truth and Argo CD applied it.

**LAST SYNC: Succeeded**: the most recent apply from Git worked. If this failed, click it for the error.

The **resource tree** below is the same app broken into pieces: namespace, secrets, services, deployments, ingress, and so on Green checkmarks = applied from Git. Click any box (for example, `deploy/auth-service`) → **Live Manifest** vs **Desired** to see what Argo CD thinks should run.

**Quick "is the app actually working?" test** (outside Argo CD):

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/auth/health
```

`200` = the app is reachable end-to-end, not only "green in Argo CD."

**When something is wrong:** HEALTH goes **Degraded** or **Progressing** for a long time; SYNC goes **OutOfSync**; a resource in the tree turns **red**. Click that resource → **Events** or **Logs**. The kubectl checks below double-check the same thing from the terminal.

Confirm ArgoCD is watching **all** workloads (not only ingress):

```bash
argocd app resources clearledger --grpc-web | grep Deployment
```

**Pass looks like your output:**

```text
apps    Deployment    clearledger    auth-service            No
apps    Deployment    clearledger    frontend                No
apps    Deployment    clearledger    ledger-service          No
apps    Deployment    clearledger    notification-service  No
apps    Deployment    clearledger    redis                   No
```

**How to read it:** each line is one Deployment Argo CD manages from `clearledger-infra/manifests/`. Seeing all five app deployments (plus `redis`) means it rendered the full `kustomization.yaml`, not just `ingress.yaml`.

The last column is **ORPHANED**. **`No` is good**: the resource belongs to this app. You would only worry if deployments were **missing** from this list, or if the UI showed **OutOfSync** / red health.

**✋ Hands-on checkpoint first sync healthy**

Run these four checks. **Pass looks like:**

```bash
kubectl get pods -n clearledger
# Every app pod 1/1 Running (postgres/redis may show older RESTARTS from VM reboots — OK)

kubectl get application clearledger -n argocd \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
# sync=Synced health=Healthy

curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/auth/health
# 200

kubectl logs -n clearledger deploy/auth-service --tail=5 2>/dev/null | head -3
# Lines like: GET /health HTTP/1.1" 200 OK
# Bad sign: DATABASE_URL is not set
```

**If all four pass → Stage 2 first sync is done.** Continue to **Enable CI → ArgoCD handoff** below, then `make check-2` and `make snapshot STAGE=2`.

### How to Enable the CI to ArgoCD Handoff

GitHub → your `clearledger` repo → **Settings → Secrets and variables → Actions → Variables** → **New repository variable**:

| Name | Value |
|---|---|
| `ENABLE_ARGOCD_SYNC` | `true` |

The next green pipeline run nudges ArgoCD after updating `clearledger-infra` (uses `microk8s kubectl` on the runner). That nudge is optional and non-fatal. If it cannot reach the cluster, the manifest push still succeeded and ArgoCD syncs on its next poll (~3 min).

Leave this **unset during Stage 1**, that is how you proved the cluster did not change until GitOps existed.

Leave **`ENABLE_DAST` unset** for now. Stage 3 walks you through turning on OWASP ZAP once the app is reliably live at `clearledger.local`.

If health is **Progressing** or pods are red → read the section below **before** taking screenshots or continuing to Stage 3.

### If the UI shows red pods or "Progressing" (read this before the screenshot)

This is a common first-sync surprise, not a broken install.

**Why it happens in Stage 2**

ArgoCD syncs whatever is in `clearledger-infra`. Deployments must use **`secretKeyRef`** (Stages 2–4), not Vault injection. If your infra repo has Vault annotations from an older lab copy, auth/ledger crash with `DATABASE_URL is not set` until Stage 5.

Network policies belong to **Stage 6** (runtime security). They live in `infra/deferred-by-stage/stage-6-runtime-security/netpol/` in this repo, **not** in `infra/manifests/`.

If `manifests/netpol/` is still in your **`clearledger-infra`** repo on GitHub (from an older copy of the lab), ArgoCD will keep applying it. Those policies use **default-deny** and break DNS for new pods, so you see red **0/1** pods and **Progressing** health.

**Fix for Stage 2**

Do **both** steps. Deleting only in the cluster is not enough: ArgoCD recreates policies from Git on the next sync.

**Step 1: remove from `clearledger-infra` on GitHub**

Delete the folder `manifests/netpol/` → commit: `chore: defer network policies to Stage 6`.

**Step 2: sync and restart**

```bash
argocd app sync clearledger --grpc-web
kubectl delete networkpolicy -n clearledger --all   # safe once Git no longer has netpol
kubectl rollout restart deployment/auth-service deployment/ledger-service -n clearledger
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
```

Network policies stay in **`clearledger`** under `infra/deferred-by-stage/` until you apply them in Stage 6.

When that looks good, continue below.

---

When sync finishes and health is **Healthy**, you should see the **clearledger** app in the UI with green **Healthy** and **Synced** badges: repo pointing at your `clearledger-infra` repo on `main`, path `manifests`, namespace `clearledger`. Open the app tile and the resource tree should show deployments, services, and ingresses reconciled with no red pods.

From the CLI, `argocd app get clearledger` should echo the same story: `Sync Status: Synced`, `Health Status: Healthy`, and each resource listed as synced.

### ArgoCD stuck OutOfSync (break-glass fix)

**Normal path:** CI copies full manifests + updates Kustomize tags → ArgoCD auto-syncs within ~3 minutes.

**If still OutOfSync after 10+ minutes:**

```bash
make fix-argocd
```

This re-syncs canonical manifests to `clearledger-infra` (Kustomize SHAs preserved), re-applies the Application, and triggers a hard refresh. **Do not** `kubectl apply` deployments: fix Git, let ArgoCD sync.

```bash
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web --prune
kubectl get application clearledger -n argocd -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
```

**Take a screenshot of that view**: the app tile or the resource tree is fine. That’s your portfolio proof that GitOps is actually running.

### Prove ArgoCD Self-Healing

Now prove that Git is the source of truth.

In this demo, you will change the running cluster by hand. You will **not** change Git. ArgoCD should notice that the cluster no longer matches `clearledger-infra`, then change it back.

Before you start, make sure the app is healthy and ArgoCD is managing the deployments:

```bash
argocd app resources clearledger --grpc-web | grep Deployment
```

Manually change the auth-service image in the cluster:

```bash
# Manually change the image in the cluster only (Git stays the same)
kubectl set image deployment/auth-service \
  auth-service=$DOCKER_USERNAME/clearledger-auth-service:fake-tag \
  -n clearledger
```

Check ArgoCD:

```bash
# ArgoCD should flip to OutOfSync within a minute or two
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
```

Wait for ArgoCD to fix the cluster. The fake image tag may briefly cause an image pull error; that is expected in this demo.

```bash
# Wait for selfHeal (default sync interval is ~3 minutes)
sleep 180
```

Confirm the image was changed back to the Git version:

```bash
# Cluster image should match clearledger-infra again — Git was never edited
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

If the image changed back, ArgoCD self-healing worked. You changed the cluster by hand, but ArgoCD restored it to match `clearledger-infra`.

That is GitOps: Git says what should run, and ArgoCD keeps the cluster matching Git.

```bash
make check-2
```

---

### How to Roll Back a Bad Deploy

> You just proved that ArgoCD reverts unauthorized cluster changes. Now flip it: **what if you pushed a bad commit yourself?** GitOps rollback is not a button. It is a git operation. This section explains why, shows you both methods, and has you practise each one before you need them under pressure.

#### How you know you need to roll back

These symptoms appearing within minutes of a push to `clearledger-infra` point at a bad commit:

- Pods stuck in `CrashLoopBackOff` or `Error`. Check with `kubectl get pods -n clearledger`
- `kubectl logs <pod> -n clearledger --previous` shows startup errors that were not there before
- ArgoCD health flips from `Healthy` to `Degraded` or stays on `Progressing`. Check with `argocd app get clearledger --grpc-web`
- The app returns 5xx errors or login stops working. Check with `curl -I http://clearledger.local/health`

If you see any of these within minutes of a push, assume the latest commit is the cause and roll back first: investigate second.

---

#### Why ArgoCD rollback is not just a button

ArgoCD has a rollback button in the UI and an `argocd app rollback` command. Both work. But only if you understand the interaction with `selfHeal`.

Your Application (`stages/stage-2-gitops/argocd/clearledger-app.yaml`) is configured with:

```yaml
syncPolicy:
  automated:
    selfHeal: true
```

**What `selfHeal: true` means in plain English**

Git (`clearledger-infra`) is the boss. The cluster must match Git. If someone changes the cluster without changing Git: manual `kubectl`, or the Argo CD **Rollback** button. Argo CD notices the mismatch and **puts the cluster back to whatever Git says**, usually within a few minutes.

So the UI rollback only changes the **cluster**. It does **not** change Git. With self-heal on, Argo CD sees “cluster ≠ Git” and re-applies Git, your rollback gets undone. You thought you rolled back; Git still says the bad version, so the bad version comes back.

**The GitOps rollback:** change Git (`git revert` in `clearledger-infra`). Then self-heal helps you: cluster and Git both point at the good version.

**Emergency UI rollback:** turn off auto-sync first, then rollback, then fix Git. Details below.

There are two correct ways to roll back, and the right one depends on how much time you have.

---

#### Method 1 — Git revert (preferred, always try this first)

This is the GitOps way. You do not touch the cluster. You change Git, and ArgoCD syncs the fix.

**When to use:** You have a few minutes. You can identify the bad commit in `clearledger-infra`.

**How it works:**

```
Bad commit pushed to clearledger-infra
        ↓
ArgoCD auto-synced it (cluster is now broken)
        ↓
You run: git revert <bad-commit> && git push
        ↓
ArgoCD auto-syncs the revert (cluster is fixed, selfHeal works with you)
        ↓
Git history shows the bad deploy AND the revert — full audit trail
```

**Step-by-step:**

```bash
# 1. Go to your clearledger-infra repo (wherever you cloned it)
cd ~/clearledger-infra      # adjust path if you cloned elsewhere
git pull                    # make sure you are up to date

# 2. Find the bad commit
git log --oneline -10

# Output looks like:
# abc1234 update ledger-service image to v1.4.0   ← this broke prod
# def5678 update auth-service image to v1.3.1     ← was fine
# 9a1b2c3 add vault rotation cronjob

# 3. Revert it — this creates a NEW commit, it does not delete history
git revert abc1234 --no-edit

# 4. Push — ArgoCD picks it up automatically within ~3 minutes
git push

# 5. Confirm the cluster recovered
kubectl get pods -n clearledger
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
# Expected: Sync Status: Synced, Health Status: Healthy
```

**Why this is preferred:**
- `selfHeal` works *with* you: the new `HEAD` is already the reverted state, nothing fights you
- Full audit trail. Git shows the bad deploy, the revert, and who did both
- No cluster commands needed: ArgoCD applies everything
- Compliant: regulators and on-call engineers can read exactly what happened from Git history alone

---

#### Method 2 — Emergency ArgoCD rollback (when the cluster is on fire)

Use this when the cluster is broken right now and you do not have time to push a Git fix. It pins the cluster to a previous known-good deployment immediately. You will still fix Git afterward. This is a stabilise-first step, not a permanent fix.

**When to use:** Incident in progress. Pods are crashing, users are affected, and you need the cluster back to a known-good state in under 30 seconds.

> **Before you start:** confirm your ArgoCD CLI session is still valid. If it expired, re-login first: an expired session will silently fail every command below.
> ```bash
> argocd account get-user-info --grpc-web
> # If you see "Unauthenticated", re-login:
> ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
>   -o jsonpath="{.data.password}" | base64 -d)
> argocd login argocd.local --username admin --password "$ARGOCD_PASSWORD" \
>   --insecure --grpc-web
> ```

**Step 1 (Disable auto-sync** (critical) skip this and selfHeal will undo your rollback within 3 minutes)

```bash
argocd app set clearledger --sync-policy none --grpc-web
# Confirm: automated sync is now off
argocd app get clearledger --grpc-web | grep "Sync Policy"
# Expected: Sync Policy: <none>
```

**Step 2. Find the last known-good deployment ID**

```bash
argocd app history clearledger --grpc-web

# Output looks like:
# ID   DATE                           REVISION
# 9    2026-06-05 10:12:00 +0000 UTC  abc1234  ← bad deploy (current)
# 8    2026-06-04 14:46:06 +0000 UTC  def5678  ← known good
# 7    2026-06-01 20:53:19 +0000 UTC  9a1b2c3

# Or check via kubectl (no argocd CLI needed):
kubectl get application clearledger -n argocd \
  -o jsonpath='{range .status.history[*]}{.id}{"\t"}{.deployedAt}{"\t"}{.revision}{"\n"}{end}'
```

Use the ID (the number on the left), not the SHA.

**Step 3. Roll back to the known-good ID**

```bash
argocd app rollback clearledger 8 --grpc-web
```

**Step 4. Confirm the cluster is stable**

```bash
kubectl get pods -n clearledger
# All pods should be Running

argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
# Sync Status:   OutOfSync  ← expected — cluster is at rev 8, Git is still at the bad HEAD
# Health Status: Healthy    ← this is what matters right now
```

`OutOfSync` is correct and expected at this point. The cluster is running the old known-good revision. Git still has the bad commit. You will fix that next.

**Step 5. Fix Git (do not leave it broken)**

```bash
cd ~/clearledger-infra
git pull
git revert <bad-commit-sha> --no-edit
git push
```

**Step 6. Re-enable auto-sync**

```bash
argocd app set clearledger \
  --sync-policy automated \
  --self-heal \
  --auto-prune \
  --grpc-web

# Trigger an immediate sync so you do not wait for the next auto-check
argocd app sync clearledger --grpc-web

# Confirm everything is clean
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
# Expected: Sync Status: Synced, Health Status: Healthy
```

> **Never leave auto-sync disabled longer than the incident.** It is your drift-detection and tamper-evidence mechanism: without it, unauthorized `kubectl` changes go undetected. Re-enable it the moment you push the Git fix.

---

#### Practise the rollback now (before you need it under pressure)

Do not wait for a real incident to run this for the first time. The steps below simulate a bad image tag deploy and walk you through Method 1 (the preferred path).

**Step 1. Push a bad image tag to `clearledger-infra`**

```bash
cd ~/clearledger-infra
git pull

# Edit manifests/notification-service/deployment.yaml
# Change the image tag to a tag that does not exist, e.g.:
#   image: docker.io/$DOCKER_USERNAME/clearledger-notification-service:broken-tag

# Commit and push it
git add manifests/notification-service/deployment.yaml
git commit -m "test: simulate bad deploy with nonexistent image tag"
git push
```

**Step 2. Watch ArgoCD sync the bad state**

```bash
# Give ArgoCD ~3 minutes to pick it up, or trigger immediately:
argocd app sync clearledger --grpc-web

# Watch the notification-service pod fail
kubectl get pods -n clearledger -w
# You will see: notification-service pod stuck in ImagePullBackOff or ErrImagePull
```

**Step 3. Roll back using Method 1**

```bash
cd ~/clearledger-infra

# Revert the bad commit
git revert HEAD --no-edit
git push

# ArgoCD will auto-sync — or trigger it:
argocd app sync clearledger --grpc-web

# Watch pods recover
kubectl get pods -n clearledger -w
# notification-service should return to Running
```

**Step 4. Verify**

```bash
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
# Expected: Sync Status: Synced, Health Status: Healthy

kubectl get pods -n clearledger
# All pods Running, no ImagePullBackOff
```

You have now practised a rollback end-to-end. The `git revert` commit is permanently in the infra repo's history: a real audit record of a simulated recovery.

---

#### Quick reference

**Use Method 1 (git revert) when:**
- A bad image tag or manifest was pushed to `clearledger-infra` and you have a few minutes
- Any config change in the infra repo caused pods to break
- This is almost always the right answer. It is fast, safe, and leaves a clean audit trail

**Use Method 2 (emergency ArgoCD rollback) when:**
- The cluster is broken right now, users are affected, and you need it stable in under 30 seconds
- You are not yet sure which commit caused the problem and need time to investigate: roll back to stabilise, then use `git log` to find the culprit, then fix forward with Method 1

**Neither method applies when:**
- A pod is crashing but nothing was pushed to the infra repo recently. This is not a rollback problem. Check `kubectl logs`, Vault connectivity, and network policies instead.

`revisionHistoryLimit: 10` in `stages/stage-2-gitops/argocd/clearledger-app.yaml` means ArgoCD always has 10 previous deployments available for emergency rollback. Increase it if your release cadence is high.

---

### What You Learned in Stage 2

- What GitOps means: Git is the single source of truth, and a tool enforces it
- What ArgoCD does: watches Git, compares it to the cluster, corrects drift automatically
- How the full flow works now: push code → CI builds image → CI updates infra repo → ArgoCD syncs cluster
- **No one runs `kubectl` to deploy anymore.** The pipeline updates Git, ArgoCD does the rest.
- **How to roll back safely:** `git revert` in the infra repo is the correct answer; ArgoCD emergency rollback is the break-glass option, and you must disable auto-sync first or selfHeal will silently undo it

**What you can now put on your CV / say in an interview:**

> Implemented GitOps with ArgoCD so cluster state is driven from Git, with drift detection, auto-sync, and a Git-based rollback of a bad deploy.

`make snapshot STAGE=2 && make snapshots`. Confirm `clearledger.stage2`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

---

## Stage 3 — Security Gates

Every push runs security checks. Some failures stop the pipeline right away. Others you learn from now and enforce in the cluster later (Stage 4).

**Goal:** understand six scanners: what each one looks at, what it catches, and how to read a failure. You will break each gate on purpose (§3.4) so a red CI job is not a surprise.

**Ready for Stage 3?**

- `make check-2` passes
- `ENABLE_ARGOCD_SYNC=true` on GitHub (you set this in Stage 2)
- `ENABLE_DAST` still **unset** (turn on later in this stage if you want)
- Argo CD at `http://argocd.local` shows **Synced**
- Optional: skim [Stage 1 security posture](#heading-stage-1-security-posture-what-blocks-vs-what-waits). Stage 1 already ran many of these tools

**Done when:** `make check-3` passes and you triggered each gate once (§3.4). Then `make snapshot STAGE=3` and `make snapshots`.

---

### What You Need to Know First

One tool is not enough. Each scanner guards a different layer:

- **Gitleaks** — secrets in code or Git history (API keys, tokens)
- **Semgrep (SAST)** — bugs in your Python/JS source (injection, unsafe patterns)
- **Trivy (SCA + images)** — known CVEs in pip/npm packages and in built Docker images
- **Checkov (IaC)** — misconfigs in Dockerfiles and Kubernetes manifests
- **Cosign** — proves images were built and signed by your pipeline

**What blocks CI today:** secrets, bad code (SAST), vulnerable images, Dockerfile issues on production images.

**What waits for later:** some Kubernetes manifest findings are reported in Stage 1 as evidence; Stage 4 (Kyverno) turns the important ones into cluster enforcement.

**Where checks run:** When you `git commit`, hooks on your laptop can scan first (pre-commit). When you `git push`, GitHub Actions scans again on the runner. Same idea twice: catch mistakes before they waste a 10-minute pipeline. Pre-commit is optional to install; CI always runs on push either way.

---

### Enable DAST (optional — after Stage 2)

DAST (Dynamic Application Security Testing) scans the **running** app at `http://clearledger.local`. It was off in Stages 1–2 on purpose: Stage 1 never deployed to the cluster, and Stage 2 was about getting GitOps healthy first.

If `make check-2` passes and `curl http://clearledger.local/auth/health` returns `200`, you can turn DAST on:

GitHub → your `clearledger` repo → **Settings → Secrets and variables → Actions → Variables** → **New repository variable**:

| Name | Value |
|---|---|
| `ENABLE_DAST` | `true` |

Push a small commit (or re-run the last workflow on `main`). The **DAST (OWASP ZAP + fintech API tests)** job should run instead of **skipped**. A failed ZAP scan is a real finding to investigate. Skipped before this step only means the toggle was off.

---

### 3.1 — Install pre-commit hooks

```bash
# macOS (Homebrew — avoids PEP 668 "externally-managed-environment" from pip3):
brew install pre-commit

# Linux/WSL2:
# sudo apt install -y pre-commit
# or: python3 -m pip install --user pre-commit

pre-commit install
pre-commit run --all-files
```

If some hooks fail on first run, see [troubleshooting.md. Gitleaks and scanner issues](troubleshooting.md#gitleaks-finds-demo-secrets). **Gitleaks and Ruff must pass**. YAML/Terraform issues on later-stage files are OK until you reach those stages.

Test it catches secrets locally before CI does:

```bash
echo 'AWS_SECRET = "'$(printf '%s%s' 'AKIA' 'IOSFODNN7EXAMPLE')'"' >> app/auth-service/main.py
git add app/auth-service/main.py && git commit -m "test"
# Gitleaks fires and blocks the commit — see "What you should see" below
git restore --staged app/auth-service/main.py
git checkout app/auth-service/main.py
```

The commit was blocked before it even reached Git. If the pre-commit hook was not installed, that fake AWS key would be in your Git history permanently (even if you delete the line later, Git remembers).

> **Already did Cosign in Stage 1?** That counts. Stage 3 does not require regenerating keys. Confirm `infra/cosign.pub` exists and GitHub has `COSIGN_PRIVATE_KEY` + `COSIGN_PASSWORD`. Stage 4 turns signing into **enforcement** at the cluster gate.

**✋ Hands-on checkpoint: pre-commit actually blocks a secret**

Installed-but-not-wired is the classic silent failure. Prove the hooks fire:

```bash
echo 'AWS_SECRET='"$(printf '%s%s' 'AKIA' 'IOSFODNN7EXAMPLE')" > leak-test.env
git add leak-test.env
pre-commit run --all-files; echo "exit=$?"
git reset leak-test.env >/dev/null; rm -f leak-test.env
```

Expected: the secret-scanning hook **fails** the run (`exit=1`) and flags `leak-test.env`. If `exit=0`, your hooks are installed but not catching anything: re-run `pre-commit install` and confirm `.git/hooks/pre-commit` exists.

If you skip this, commits sail through unscanned and you will believe Stage 3 is protecting you when it is not.

### 3.2 — Generate Cosign keys

> If you created Cosign keys in Stage 1 (§1.4), skip generation: go straight to inserting `cosign.pub` into the Kyverno policy and adding the GitHub secrets below.

**Cosign** signs your Docker images with a cryptographic key. When you deploy to the cluster, Kyverno (Stage 4) can verify the signature and reject any image that was not signed by your pipeline. This prevents someone from pushing a malicious image to your Docker Hub and having the cluster run it.

```bash
# macOS: brew install cosign
# Linux/WSL2: curl -O -L https://github.com/sigstore/cosign/releases/download/v2.2.4/cosign-linux-amd64 && chmod +x cosign-linux-amd64 && sudo mv cosign-linux-amd64 /usr/local/bin/cosign

cosign generate-key-pair   # enter a password when prompted
```

This creates two files: `cosign.key` (private, used by the pipeline to sign) and `cosign.pub` (public, used by Kyverno to verify).

Insert your public key into the Kyverno policy (replace the placeholder block in `infra/policies/require-signed-images.yaml` with the contents of `cosign.pub`).

Add secrets to GitHub (github.com/YOUR_USERNAME/clearledger → Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `COSIGN_PRIVATE_KEY` | Contents of `cosign.key` |
| `COSIGN_PASSWORD` | The password you entered when generating keys |

**✋ Hands-on checkpoint. Cosign keypair exists and is gitignored**

Stage 4's image-signing policy depends on this exact state:

```bash
test -f cosign.key && echo "private key present"
test -f cosign.pub && echo "public key present"
grep -q "BEGIN PUBLIC KEY" cosign.pub && echo "public key valid"
git check-ignore cosign.key && echo "private key correctly ignored"
```

Expected: all four success lines print. If `git check-ignore` prints nothing, your private key is **not** ignored: add it to `.gitignore` before any commit.

If you skip this, §4.2 fails confusingly later: pods admitted then ImagePullBackOff, or a silent pass.

### 3.3 — Activate the full security pipeline

The security gates are already in `.github/workflows/ci.yaml`. Push any change to trigger the full pipeline:

```bash
git add . && git commit -m "ci: full DevSecOps pipeline" && git push origin main
```

### 3.4 — Break each gate on purpose

For each gate: break something on purpose, read how the tool reports it, revert, confirm green again. Try the local command first, then push once if you want a screenshot on GitHub Actions.

```bash
# 1. Break it   2. Run locally or push   3. Read the failure
# 4. git checkout -- path/to/file   5. pre-commit run --all-files (optional)   6. git push
```

Start with **Gate 1** end-to-end before the others.

---

#### Gate 1 — Gitleaks (secrets)

**Inject:** hardcoded AWS key in any Python file.

```bash
echo 'AWS_KEY = "'$(printf '%s%s' 'AKIA' 'IOSFODNN7EXAMPLE')'"' >> app/auth-service/main.py
git add app/auth-service/main.py && git commit -m "test: trigger gitleaks"
# pre-commit blocks this commit locally — that is the test.
# For a CI screenshot only: git commit --no-verify -m "test: trigger gitleaks" && git push
```

**Done looks like (terminal: pre-commit):**

```text
🔑 Secrets scan (Gitleaks)...............................................Failed
- hook id: gitleaks
- exit code: 1

Finding:     AWS_KEY = "REDACTED"
RuleID:      aws-access-token
File:        app/auth-service/main.py
Line:        316
```

**Done looks like (CI: job `Secrets Scan (Gitleaks)`):** red ✗ on workflow; log contains `leaks found: 1` and the file path. **Build jobs do not start**: pipeline stops here.

**Revert:**

```bash
git restore --staged app/auth-service/main.py 2>/dev/null
git checkout app/auth-service/main.py
pre-commit run gitleaks --all-files   # → Passed
```

---

#### Gate 2 — Semgrep (SAST)

**Local dry-run** (no repo change):

```bash
python3 -m venv /tmp/sec-gates-venv && /tmp/sec-gates-venv/bin/pip install semgrep
cat > /tmp/semgrep-bad.py << 'EOF'
import subprocess
from fastapi import Request
def bad(request: Request):
    subprocess.run(request.query_params.get("cmd"), shell=True)
EOF
/tmp/sec-gates-venv/bin/semgrep \
  --config=p/python --config=p/security-audit --config=p/owasp-top-ten --error \
  /tmp/semgrep-bad.py
```

**Break CI**: add a throwaway file Semgrep will scan, commit, push:

```bash
cat > app/auth-service/gate_test_semgrep.py << 'EOF'
import subprocess
from fastapi import Request
def bad(request: Request):
    subprocess.run(request.query_params.get("cmd"), shell=True)
EOF
git add app/auth-service/gate_test_semgrep.py && git commit -m "test: trigger semgrep" && git push
```

**Pass:** `subprocess-shell-true` / `Blocking` in the log. CI job **`SAST (Semgrep)`** red ✗; **`Build images`** and below do not run.

**Revert:**

```bash
rm -f app/auth-service/gate_test_semgrep.py
git add -A && git commit -m "revert: semgrep gate test" && git push
```

---

#### Gate 3 — Checkov (IaC / Dockerfile)

**Learn locally**: missing `HEALTHCHECK` shows up in Checkov output but may not fail CI (only HIGH/CRITICAL hard-fail):

```bash
python3 -m venv /tmp/sec-gates-venv && /tmp/sec-gates-venv/bin/pip install checkov
sed '/^HEALTHCHECK/,+1d' app/auth-service/Dockerfile > /tmp/Dockerfile-nohc
mkdir -p /tmp/checkov-demo/app/auth-service
cp /tmp/Dockerfile-nohc /tmp/checkov-demo/app/auth-service/Dockerfile
/tmp/sec-gates-venv/bin/checkov --directory /tmp/checkov-demo --framework dockerfile
```

**Break CI**: add `EXPOSE 22` (shows **CKV_DOCKER_1** in the log). CI only goes red if Checkov rates it HIGH/CRITICAL (`--hard-fail-on` in `ci.yaml`); if the job stays green, you still passed the exercise by reading the finding in the log and artifact **`checkov-results`**.

```bash
echo 'EXPOSE 22' >> app/auth-service/Dockerfile
git add app/auth-service/Dockerfile && git commit -m "test: trigger checkov" && git push
```

**Pass:** log or artifact shows **CKV_DOCKER_1** (SSH port exposed). Job **`IaC Scan (Checkov)`** red ✗ is a bonus, not required for §3.4. Use **Gitleaks, Semgrep, or Trivy** for a screenshot of a failed job.

**Revert:**

```bash
git checkout app/auth-service/Dockerfile
git commit -am "revert: checkov gate test" && git push
```

---

#### Gate 4 — Trivy (image CVEs)

**Local dry-run**: scan an old base image (no build):

```bash
trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed python:3.8-slim
```

**Break CI**: pin an old base in the Dockerfile, push, wait for **`Scan images`**:

```bash
sed -i.bak 's/FROM python:3.13-slim/FROM python:3.8-slim/' app/auth-service/Dockerfile
git add app/auth-service/Dockerfile && git commit -m "test: trigger trivy" && git push
```

**Pass:** **`Scan images`** → **Trivy scan all images** exits 1 with a CVE table (`HIGH` / `CRITICAL`). **`Publish images`** and **`Update Manifests`** are skipped.

**Revert:**

```bash
git checkout app/auth-service/Dockerfile
git commit -am "revert: trivy gate test" && git push
```

---

### 3.5 — When a scan fails on a CVE you didn't inject

§3.4 is deliberate. This section is for the other case: you changed nothing, pushed, and **Scan images** went red anyway. New CVEs land in the database every week. That is normal: fix the package, do not weaken the gate.

**Find the real error.** Scroll up in **Trivy scan all images** for the CVE table (Package, CVE, Installed, **Fixed Version**). Or download **Artifacts → image-scan-results → trivy-auth-results.json**.

**Ignore this red herring** at the bottom of the log:

```text
Version 0.71.2 of Trivy is now available
Error: Process completed with exit code 1.
```

The version notice does not fail the job. A fixable HIGH/CRITICAL CVE does. Do not add `--skip-version-check` to “fix” it.

**Fix it:**

- **pip package** — bump to the Fixed Version in `requirements.txt` (example: `python-multipart==0.0.30` for CVE-2026-53539). Apply the same bump to sibling services if they share that pin.
- **OS package** — newer base image or a targeted `apt`/`apk` upgrade in the Dockerfile.
- **No stable fix yet** — documented exception only: add the CVE to `.trivyignore` and `.grype.yaml` with a comment (see `CVE-2026-7210`).

Do not remove `--exit-code 1`, drop HIGH from `--severity`, or disable scanning. More help: [troubleshooting.md. Trivy](troubleshooting.md#trivy-blocks-python-service-images).

---

### Finish Stage 3

**Gate cheat sheet** (for §3.4 screenshots): Gitleaks → `Secrets Scan`; Semgrep → `SAST`; Trivy → `Scan images` (CVE table). Checkov → read `CKV_*` in the log (job may stay green).

After each §3.4 test: revert, push, confirm the workflow is green again. One red-job screenshot is enough for a portfolio.

**Done when:**

```bash
make check-3   # must end: All checks passed. Ready for the next stage.
```

You also triggered at least one gate in §3.4 (Gitleaks locally counts). Optional: `ENABLE_DAST=true` if you want ZAP later, not required to leave Stage 3.

**Not required yet:** Kubernetes Checkov blocking CI, Cosign blocking deploys. Those tighten in **Stage 4** (Kyverno).

**Next:** Stage 4 stops bad pods at the cluster door even if someone uses `kubectl` and skips CI.

```bash
make snapshot STAGE=3 && make snapshots
```

---

## Stage 4 — Admission Control (Kyverno)

> Even if CI passes, the cluster can still refuse.

CI scans your code and images before they reach GitOps, but it cannot watch everything that happens inside the cluster. Someone with `kubectl` access could apply a manifest directly. A Helm chart you install might create pods that violate your security standards. Those paths never hit the pipeline, which is why Stage 4 adds **admission control**: a checkpoint built into Kubernetes itself. Every time something tries to create or update a resource, the request passes through admission webhooks before it takes effect. If a webhook rejects the request, the resource is never created.

**Kyverno** is a Kubernetes-native policy engine that uses those webhooks. You write policies as YAML files (not application code), and Kyverno enforces them on every matching resource in the cluster, for example, rejecting any pod that runs as root or requiring CPU and memory limits on every container. The difference from CI is timing: CI scans *before* code ships; Kyverno enforces at the *cluster gate*. Together they give you two layers of defense.

**Your goal in this stage** is to install Kyverno, apply the policies in `infra/policies/`, and prove in §4.4 that non-compliant pods are denied before the container runtime ever sees them.

**Before you start**, make sure the foundation from earlier stages is still solid: `make check-3` should pass (pre-commit hooks and CI security gates are active), `infra/cosign.pub` should exist from Stage 3, and ArgoCD should still be syncing so the app responds at `http://clearledger.local`. If any of those are red, fix them first: Kyverno sits on top of a healthy cluster, not a broken one.

**You are done with Stage 4** when all three break-it scenarios in §4.4 are denied and `make check-4` passes.

**What changes from Stage 3 is enforcement, not scanning.** In CI, Checkov reported Kubernetes misconfigurations but did not block the pipeline; Kyverno now stops those same classes of problems at the cluster gate. Cosign has been signing your images since Stage 1; Kyverno now *requires* that signature before a ClearLedger image can deploy. This is where [Stage 1 evidence becomes enforcement](#heading-stage-1-security-posture-what-blocks-vs-what-waits). See that section if you want the full map of what blocked in Stage 1 versus what waited for Stage 4.

Start at **§4.1** to install Kyverno. If install, policies, break-it scenarios, or `make check-4` fail, read [troubleshooting.md. Stage 4](troubleshooting.md#stage-4-admission-control-troubleshooting) before changing Helm charts or policy YAML.

### What Kyverno enforces

All policy files live in `infra/policies/`. Kyverno itself is installed via Helm using `stages/stage-4-admission-control/infra/kyverno/values.yaml`.

| Policy | What it enforces | Framework |
|---|---|---|
| `disallow-root-containers` | `runAsNonRoot: true` | CIS K8s 5.2.6 |
| `require-resource-limits` | CPU/memory requests and limits | CIS K8s 5.2.4 |
| `disallow-privilege-escalation` | `allowPrivilegeEscalation: false` | CIS K8s 5.2.5 |
| `drop-all-capabilities` | `capabilities.drop: [ALL]` | CIS K8s 5.2.7 |
| `require-signed-images` | Cosign signature on ClearLedger images | SLSA Level 2 |

### Platform Stability — From Stage 4 Onward

From Stage 4 on you are running more controllers on a single-node VM. Kyverno, storage provisioners, and later Prometheus and Loki. A pod can show `Running` while it is actually crash-looping in the background. When **platform** pods (Kyverno controllers, `hostpath-provisioner`, the Prometheus operator, and similar) accumulate high `RESTARTS`, the API server starts timing out, `kubectl` feels flaky, and you can waste days debugging the wrong component because the app pods look fine.

**After every stage from here on**, give the cluster about ten minutes to settle, then run the stage health check:

```bash
bash scripts/health-check.sh <stage>    # for example, 4, 7, 7.5
# or the Makefile shortcut:
make check-4
```

The script ends with a **Platform stability** section that flags pods with suspicious restart counts. You can also scan the worst offenders yourself. This lists the fifteen pods with the highest restart counts cluster-wide, which is useful when something feels slow but you are not sure which namespace is struggling:

```bash
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' \
  | tail -15
```

**The gate:** Kyverno controllers and other platform pods should show **RESTARTS under 5** after the stage settles. If any platform pod is climbing past 10, stop and fix it with the documented Helm values or [troubleshooting.md](troubleshooting.md). Do not `kubectl patch` around it and move on. A stable platform layer is a prerequisite for every stage that follows.

---

### 4.1 — Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm upgrade --install kyverno kyverno/kyverno \
  --version 3.2.8 \
  --namespace kyverno \
  --create-namespace \
  -f stages/stage-4-admission-control/infra/kyverno/values.yaml \
  --wait --timeout=600s
```

The values file does three important things for the lab:

1. **Disables cleanup CronJobs**: older Kyverno charts pull `bitnami/kubectl`, which was removed from Docker Hub and causes `ImagePullBackOff` on cleanup pods.
2. **Points Helm hooks at `bitnamilegacy/kubectl`**, so future `helm uninstall` does not hang on a missing image.
3. **Extends liveness probe timeouts**: the default `timeoutSeconds: 5, failureThreshold: 2` is too tight for a loaded single-node VM. Under CPU pressure the health endpoint can take >5s to respond, which triggers a restart cascade that saturates the node and makes the API server intermittently unreachable. The values file sets `timeoutSeconds: 30, failureThreshold: 5` so Kyverno survives load spikes without crash-looping.

**What you should see:**

```
Release "kyverno" does not exist. Installing it now.
NAME: kyverno
NAMESPACE: kyverno
STATUS: deployed
...
Kyverno version: v1.12.6
```

Verify all four controllers are running (first pull can take several minutes on a slow connection):

```bash
kubectl get pods -n kyverno
```

```
NAME                                             READY   STATUS    RESTARTS   AGE
kyverno-admission-controller-bd685cd4b-f6kl6     1/1     Running   0          2m
kyverno-background-controller-66fcfc6d87-59wgt   1/1     Running   0          2m
kyverno-cleanup-controller-5c5bf8bc6b-7kspq      1/1     Running   0          2m
kyverno-reports-controller-5cdd6f4c48-qf5wc      1/1     Running   0          2m
```

If pods stay in `ContainerCreating` for a long time, the node is still pulling images from `ghcr.io/kyverno`. Wait. Do not start a second Helm install on top of a partial one.


**Stability gate: Kyverno install only (before §4.2):**

Controllers should be `1/1 Running`, restarts 0–2 and not climbing. See [Platform Stability](#heading-platform-stability-from-stage-4-onward). Do not run `make check-4` yet (that script also validates the §4.3 policies).

```bash
kubectl get pods -n kyverno
```

---

### 4.2 — Confirm your Cosign public key is in the policy

Stage 3 created `infra/cosign.pub`. Kyverno uses that same key to verify image signatures when a pod is created. The policy file ships with a placeholder. You must replace it with **your** key before applying policies in §4.3.

**Step 1. Show your key (run from the repo root on the VM)**

```bash
cd ~/clearledger    # or wherever you cloned the repo
cat infra/cosign.pub
```

You should see three lines: `-----BEGIN PUBLIC KEY-----`, a long base64 line, and `-----END PUBLIC KEY-----`. Copy that whole block (you will paste it in the next step).

**Step 2. Paste the key into the policy**

Open `infra/policies/require-signed-images.yaml` in your editor (`nano`, `vim`, or VS Code).

Find this line:

```yaml
                      PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE
```

Delete **only** that placeholder line and paste the three lines from `cosign.pub` in its place. The result should look like this (your base64 line will differ):

```yaml
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                      -----END PUBLIC KEY-----
```

Save the file. The `BEGIN` / `END` lines must keep the spaces in front of them, that is normal YAML indentation.

**Step 3. Verify (three quick checks)**

Run these one at a time from the repo root:

```bash
# Check A — placeholder must be gone
grep PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE infra/policies/require-signed-images.yaml \
  && echo "❌ FAIL: placeholder still in file — edit and save again" \
  || echo "✓ OK: placeholder removed"
```

```bash
# Check B — key block must be present exactly once
grep -c "BEGIN PUBLIC KEY" infra/policies/require-signed-images.yaml
```

Expected output for Check B: `1` (if you see `0`, the key was not pasted; if `2`, you pasted it twice).

```bash
# Check C — policy key must match cosign.pub byte-for-byte
diff infra/cosign.pub \
  <(sed -n '/-----BEGIN PUBLIC KEY-----/,/-----END PUBLIC KEY-----/p' \
      infra/policies/require-signed-images.yaml | sed 's/^[[:space:]]*//')
```

Expected output for Check C: **nothing**: no diff lines means the keys match. If `diff` prints differences, open the policy file and fix the paste.

**All three passed?** Continue to §4.3.

**If you skip this**, Scenario 3 in §4.4 fails in a confusing way: unsigned images may slip through, or signed pods may be rejected because Kyverno is checking against the wrong key.

---

### 4.3 — Apply the five core policies

Apply the five policies that map to CIS controls. **Do not** apply `verify-slsa-provenance.yaml` yet. It is an optional SLSA attestation policy (Audit mode) for a later enhancement.

The `require-signed-images` policy includes `failurePolicy: Fail` and `webhookTimeoutSeconds: 30`: without these, Kyverno may allow pods through when signature verification cannot reach the registry.

```bash
kubectl apply \
  -f infra/policies/disallow-root.yaml \
  -f infra/policies/disallow-privilege-escalation.yaml \
  -f infra/policies/drop-all-capabilities.yaml \
  -f infra/policies/require-resource-limits.yaml \
  -f infra/policies/require-signed-images.yaml
```

Wait a few seconds, then confirm all policies show `READY: True` and `VALIDATE ACTION: Enforce`:

```bash
kubectl get clusterpolicy
```

```
NAME                            ADMISSION   BACKGROUND   VALIDATE ACTION   READY   AGE
disallow-privilege-escalation   true        true         Enforce           True    10s
disallow-root-containers        true        true         Enforce           True    10s
drop-all-capabilities           true        true         Enforce           True    10s
require-resource-limits         true        true         Enforce           True    10s
require-signed-images           true        false        Enforce           True    10s
```

If `READY` stays empty, check Kyverno logs: `kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=50`.

---

### 4.4 — Break it on purpose (the aha moment)

These three scenarios are deliberate **negative tests**. You submit a manifest you *know* is bad and confirm Kyverno rejects it **before the pod exists**. That is different from CI: Checkov told you the problem in a report; Kyverno stops the cluster from ever running the workload.

Each scenario removes or violates one control. Read the denial message. It names the policy, the rule, and the field that failed. That message is audit evidence.

| Scenario | What you simulate | Policy under test | Success looks like |
|---|---|---|---|
| 1 | Attacker applies a bare pod (no hardening) | Root, caps, privilege, limits | Four policies fire; pod `NotFound` |
| 2 | Developer fixes securityContext but forgets limits | Resource limits only | One policy fires; pod `NotFound` |
| 3 | Attacker pushes unsigned image to Docker Hub | Cosign signature | `require-signed-images` denies; pod `NotFound` |

---

#### Scenario 1 — root container (no securityContext)

**What you are simulating:** Someone with `kubectl` access bypasses CI and applies a minimal pod: no `securityContext`, no resource limits. This is exactly what Stage 1 Checkov flagged as evidence; Stage 4 now **blocks** it.

**What is wrong with this manifest:** The container has only a name and image. It will run as root by default, keep all Linux capabilities, and has no CPU/memory bounds.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
EOF
```

**What you should see:**

```
Error from server: error when creating "STDIN": admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/clearledger/root-test was blocked due to the following policies

disallow-privilege-escalation:
  check-allowPrivilegeEscalation: 'validation error: allowPrivilegeEscalation must
    be set to false. rule check-allowPrivilegeEscalation failed at path /spec/containers/0/securityContext/'
disallow-root-containers:
  check-runAsNonRoot: |-
    validation error: Root containers are blocked in the clearledger namespace. Set securityContext.runAsNonRoot: true on the pod or container.
    . rule check-runAsNonRoot failed at path /spec/containers/0/securityContext/
drop-all-capabilities:
  check-capabilities: 'validation error: All containers must drop ALL capabilities.
    rule check-capabilities failed at path /spec/containers/0/securityContext/'
require-resource-limits:
  check-resources: 'validation error: Resource requests and limits are required for
    all containers. rule check-resources failed at path /spec/containers/0/resources/limits/'
```

**How to read this output:**

The important line is:

```text
resource Pod/clearledger/root-test was blocked due to the following policies
```

That means Kyverno stopped the pod before it was created.

Under that line, Kyverno lists every policy the pod failed. For example:

```text
disallow-root-containers:
  check-runAsNonRoot:
```

This means the pod failed the `disallow-root-containers` policy, specifically the `check-runAsNonRoot` rule. The fix is also shown in the message:

```text
Set securityContext.runAsNonRoot: true
```

The same pattern applies to the other policies:

- `disallow-privilege-escalation` means the pod did not set `allowPrivilegeEscalation: false`
- `drop-all-capabilities` means the pod did not drop Linux capabilities with `capabilities.drop: [ALL]`
- `require-resource-limits` means the pod did not set CPU and memory requests/limits

The `path` part tells you where Kubernetes expected the missing setting. For example, `/spec/containers/0/securityContext/` means: look inside the pod spec, then the first container, then its `securityContext`.

And `/spec/containers/0/resources/limits/` means: look inside the first container's resource limits.

So this one bad pod failed four controls at once. That is the lesson: Kyverno does not just say "no." It tells you which policy failed and where to fix the YAML.

**Verify enforcement worked:**

```bash
kubectl get pod root-test -n clearledger
# Error from server (NotFound): pods "root-test" not found
```

If you see a pod in `Running` or `Pending`, policies are not enforcing: re-check `kubectl get clusterpolicy` shows all five `READY: True`.

**Take a screenshot.** This is portfolio evidence for CIS Kubernetes Benchmark 5.2.6: enforced, not just configured.

---

#### Scenario 2 — missing resource limits

**What you are simulating:** A developer who read the securityContext requirements and fixed root/caps/privilege. But skipped resource limits. Common in real teams: “we hardened the container” but forgot CPU/memory bounds.

**What is wrong with this manifest:** `securityContext` is correct, but there is no `resources.requests` or `resources.limits`. A container without limits can starve other workloads on the node.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nolimits-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
EOF
```

**What you should see:**

```
Error from server: error when creating "STDIN": admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/clearledger/nolimits-test was blocked due to the following policies

require-resource-limits:
  check-resources: 'validation error: Resource requests and limits are required for
    all containers. rule check-resources failed at path /spec/containers/0/resources/limits/'
```

**Key observation:** Only one policy fires this time: the securityContext fields satisfied the other four rules. Kyverno evaluates rules independently; each container property is a separate gate.

**Verify:**

```bash
kubectl get pod nolimits-test -n clearledger
# Error from server (NotFound): pods "nolimits-test" not found
```

---

#### Scenario 3 — unsigned ClearLedger image

**What you are simulating:** A supply-chain attack: someone pushes a malicious image to Docker Hub under your repo name (`clearledger-auth-service`) without going through your signed CI pipeline. Stage 3 made Cosign signing possible; Stage 4 makes it **mandatory** at the cluster gate.

**Why this scenario needs setup:** Kyverno verifies signatures against the **registry**, not your local machine. The image tag must **exist on Docker Hub**. A fake tag like `:unsigned` that was never pushed causes `ImagePullBackOff` after admission, that looks like a broken deploy, not a security block.

**Step 1: push a deliberately unsigned test image** (one-time):

```bash
export DOCKER_USERNAME=your-dockerhub-username

docker pull nginx:alpine
docker tag nginx:alpine ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
docker push ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test

# Must fail — proves the image has no Cosign signature from your pipeline key:
cosign verify --key infra/cosign.pub \
  index.docker.io/${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
# Error: no signatures found
```

**Step 2: try to deploy it with a compliant pod spec:**

The pod manifest is fully hardened (securityContext + limits) so **only** the signature policy can fail. Use `index.docker.io/` in the image URL: on Kyverno 1.12, `docker.io/...` may not trigger `verifyImages` matching.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: unsigned-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: index.docker.io/${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
      resources:
        requests:
          memory: "64Mi"
          cpu: "50m"
        limits:
          memory: "128Mi"
          cpu: "200m"
EOF
```

**What you should see:**

```
Error from server: error when creating "STDIN": admission webhook "mutate.kyverno.svc-fail" denied the request:

resource Pod/clearledger/unsigned-test was blocked due to the following policies

require-signed-images:
  verify-cosign-signature: 'failed to verify image index.docker.io/veeno-demo/clearledger-auth-service:unsigned-test:
    .attestors[0].entries[0].keys: no signatures found'
```

**How to read this output:**

- Note the webhook name is `mutate.kyverno.svc-fail`, not `validate`: image verification runs in Kyverno’s mutate pass (digest + signature check) before the pod is admitted.
- `no signatures found` means Kyverno reached Docker Hub, found the image, and confirmed it was **not** signed with your `infra/cosign.pub` key.
- The pod never exists: the attacker cannot get a shell even if the image is pullable.

**Verify:**

```bash
kubectl get pod unsigned-test -n clearledger
# Error from server (NotFound): pods "unsigned-test" not found
```

**What you should NOT see** (these mean the test did not prove signature enforcement):

| Symptom | What went wrong |
|---|---|
| Pod created, then `ImagePullBackOff` | Tag does not exist on Docker Hub — complete Step 1 first |
| Pod created and `Running` | Image used `docker.io/...` instead of `index.docker.io/...` |
| No `require-signed-images` in the error | Policy not applied, or `cosign.pub` not embedded in the policy YAML |

**Contrast: signed image is allowed:**

When the image **is** signed by your pipeline and the pod spec is compliant, admission succeeds:

```bash
# Your deployed tag (signed in CI) — should start if spec is compliant:
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# docker.io/veeno-demo/clearledger-auth-service:v0.1.0
```

Existing Deployments synced before policies existed keep running. New pods using your signed tags pass verification.

**Take a screenshot of the Scenario 3 denial**. It proves supply-chain enforcement, not just CI signing.

---

### 4.5 — Verify ClearLedger still works

Kyverno enforces on **new** pod creation. Existing deployments that already passed admission (or were synced before policies existed) keep running. Confirm your app pods are healthy:

```bash
kubectl get pods -n clearledger
```

```
NAME                                    READY   STATUS    RESTARTS   AGE
auth-service-...                        1/1     Running   0          ...
frontend-...                            1/1     Running   0          ...
ledger-service-...                      1/1     Running   0          ...
notification-service-...                1/1     Running   0          ...
postgres-0                              1/1     Running   0          ...
redis-...                               1/1     Running   0          ...
```

If ingress is configured:

```bash
curl -s http://clearledger.local/auth/health | jq .
# {"status": "ok", "service": "auth-service"}
```

ArgoCD should still show **Synced** and **Healthy**: GitOps and admission control work together, not against each other.

---

### 4.6 — Policy exceptions (when a legitimate workload needs a bypass)

Kyverno blocks every pod that violates a policy. But what happens when a legitimate workload needs to bypass a specific rule?

PostgreSQL is the example. The official Postgres Alpine image uses a specific internal user (UID 70) to manage its data directory. The `disallow-root-containers` policy requires every pod to set `runAsNonRoot: true`. Postgres does set that. But if Kyverno is configured to also check specific UID ranges, or if the pod's security context does not satisfy the rule for any reason, Kyverno blocks it. The database cannot start, and the entire application fails.

You cannot weaken the policy cluster-wide to accommodate one database. That would let every pod bypass the rule. Instead, you create a **PolicyException**: a targeted exemption for exactly the pods that need it.

Open [`infra/policies/exceptions/postgres-root-exception.yaml`](../infra/policies/exceptions/postgres-root-exception.yaml) and read the comments. Here is what each section does:

**The `spec.exceptions` block** identifies which policy and rule to bypass:

```yaml
exceptions:
  - policyName: disallow-root-containers
    ruleNames:
      - check-runAsNonRoot
```

This says: "skip only the `check-runAsNonRoot` rule from the `disallow-root-containers` policy." Every other rule in that policy (and every other policy in the cluster) still enforces normally.

**The `spec.match` block** limits which resources get the exception:

```yaml
match:
  any:
    - resources:
        kinds:
          - Pod
        namespaces:
          - clearledger
        names:
          - postgres-*
```

Only pods named `postgres-*` (matching `postgres-0`, `postgres-1`, and so on), only in the `clearledger` namespace, only for the `Pod` resource kind. Everything else in the cluster still follows the strict policy.

**The annotations** are documentation for your team and auditors:

```yaml
annotations:
  reason: "Postgres alpine image requires UID 70 for data directory ownership"
  approved-by: "platform-team"
  review-date: "2026-01-01"
```

These have no technical effect: Kyverno ignores them. They exist so that six months from now, when someone asks "why does Postgres bypass this rule?", the answer is right there in the file.

**The rules for safe exceptions:**

1. **Scope narrowly**: target the exact resource that needs it, nothing more
2. **Commit to Git**: the exception is reviewed in a pull request, tracked in version history, and auditable
3. **Never weaken the policy itself**: the rule stays strict for everything else
4. **Review periodically**: exceptions should be temporary if possible, and re-evaluated on a schedule

Apply the exception **only if** Kyverno blocks your postgres pods:

```bash
kubectl apply -f infra/policies/exceptions/postgres-root-exception.yaml
```

Verify Kyverno still blocks other non-compliant pods (same denial as Scenario 1):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: another-root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
EOF
```

---

### 4.7 — CIS benchmark evidence (kube-bench)

You already installed Kyverno and proved it blocks unsafe pods.

This step is different. `kube-bench` does not block pods and does not change the cluster. It only checks the Kubernetes node against the CIS benchmark and saves evidence.

Think of the difference like this:

| Tool | What it checks | Question it answers |
|---|---|---|
| Kyverno | Pods and workloads | "Is this pod allowed to run?" |
| kube-bench | Kubernetes node settings | "Is this Kubernetes node hardened?" |

Both are useful, but only Kyverno blocks workloads in this lab.

Run kube-bench:

```bash
bash stages/stage-4-admission-control/scripts/run-kube-bench.sh
```

The script runs kube-bench as a Kubernetes Job and saves the report here:

```text
stages/stage-4-admission-control/scripts/kube-bench-report.json
```

It also compares the result against this baseline:

```text
stages/stage-4-admission-control/scripts/kube-bench-baseline.json
```

On MicroK8s, you will see many `FAIL` and `WARN` lines. That is expected. The lab is not asking you to fix every CIS warning on a single-node local VM.

What matters is the final result.

Pass looks like this:

```text
kube-bench: 1 FAIL control(s) present (documented in baseline — no regressions).
kube-bench: no regressions vs baseline.
```

That means the known MicroK8s issues are documented, and your cluster did not get worse.

If you see `REGRESSION` or `make check-4` fails on kube-bench, stop and investigate before Stage 5.

Optional: confirm the report file exists:

```bash
ls -la stages/stage-4-admission-control/scripts/kube-bench-report.json
```

In production, you would either fix the CIS failures or document approved exceptions. In this lab, the baseline records the expected MicroK8s state.

---

### 4.8 — Health check

```bash
make check-4
```

**What you should see:**

```
▶ Stage 4 — Admission Control (Kyverno)
  ✓ Kyverno is running
  ✓ Policy disallow-root-containers — Enforce mode
  ✓ Policy require-resource-limits — Enforce mode
  ✓ Policy require-signed-images — Enforce mode
  ✓ Policy disallow-privilege-escalation — Enforce mode
  ✓ Policy drop-all-capabilities — Enforce mode
  ✓ Kyverno correctly rejects pods without securityContext
  ✓ kube-bench baseline exists (...)

All checks passed. Ready for the next stage.
```

If kube-bench reports regressions, run the script manually and update the baseline after reviewing, that diff is audit evidence.

If Kyverno install, policies, break-it scenarios, or `make check-4` fail, see [troubleshooting.md. Stage 4](troubleshooting.md#stage-4-admission-control-troubleshooting).

---

### Stage 4 complete — done checklist (move to Stage 5)

You are **done with Stage 4** when all of these are true:

| # | Check | How to verify |
|---|---|---|
| 1 | Kyverno running | `kubectl get pods -n kyverno` — four controllers `Running` |
| 2 | Policies applied | `kubectl get clusterpolicy` — five policies, `READY: True`, `Enforce` |
| 3 | Root pod blocked | Scenario 1 denial in terminal (screenshot for portfolio) |
| 4 | Unsigned image blocked | Scenario 3 denial — push `unsigned-test` tag first, use `index.docker.io/` |
| 5 | App still healthy | `kubectl get pods -n clearledger` — all app pods `Running` |
| 6 | Health check green | `make check-4` ends with **`All checks passed. Ready for the next stage.`** |

**Portfolio screenshots (optional):** root-pod denial (§4.4 Scenario 1) · unsigned-image denial (§4.4 Scenario 3) · `kubectl get clusterpolicy` showing five `Enforce` policies.

*Not yet: SLSA attestation (optional), Vault secrets (Stage 5), network policies (Stage 6). Passwords still live in Kubernetes Secrets. Stage 5 moves them into Vault.*

### What You Learned in Stage 4

- The difference between CI scanning (before merge) and admission control (at the cluster gate)
- What Kyverno is: a policy engine that intercepts every Kubernetes API request
- That enforcement means the bad resource never exists, not "we detected it after the fact"
- How to read a Kyverno denial: policy name → rule name → JSON path that failed
- How to write and apply cluster-wide security policies as YAML
- How to scope a PolicyException without weakening the policy for everyone else
- That operational issues (Helm, image pulls, registry URL format) affect whether controls actually fire
- **Why both CI and admission control are needed:** CI catches problems in your code; Kyverno catches everything else that touches the cluster
- **Evidence beats configuration:** a policy file in Git means nothing: the break-it denials are proof CIS controls are enforced, not just documented.

**What you can now put on your CV / say in an interview:**

> Enforced admission control with Kyverno: blocking root containers, privilege escalation, unsigned images, and missing resource limits at deploy time: mapped to CIS Kubernetes benchmarks.

`make snapshot STAGE=4 && make snapshots`. Confirm `clearledger.stage4`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

> **Want the deeper explanations behind the decisions in this stage?** [*DevOps Operating System*](https://osomudeya.gumroad.com/l/devops-atlas) breaks down the architecture, trade-offs, and reasoning that could not fit into the lab.

---

## Stage 5 — Secrets Management (Vault)

> By the end of this stage, sensitive values no longer live in Git or in etcd-backed Kubernetes Secrets: Vault holds them centrally and injects them into pods only when they start.

**Your goal:** remove `auth-service-secret` and `ledger-service-secret` from the cluster. Login and API calls must still work because Vault injects credentials at pod startup, that is the moment secrets management clicks.

**Before you start**, confirm Stage 4 is solid: `make check-4` passes, all five Kyverno policies are enforcing, and the app responds at `http://clearledger.local`. Fix any crash-looping pods before installing Vault.

### What changes in this stage

Right now, database passwords and JWT keys sit in `secret.yaml` files on GitHub and in Kubernetes Secrets inside the cluster. In Stage 5 you move those values into **HashiCorp Vault** and teach the app to read them a different way.

When an auth or ledger pod starts, the **Vault agent injector** adds a small sidecar container. That sidecar logs into Vault using the pod’s own service account, fetches the password and JWT, and writes them as files under `/vault/secrets/`. Your app already knows how to read those paths. It is the same data that used to arrive via `secretKeyRef`, just delivered at runtime instead of pulled from a Kubernetes Secret object.

Once migration is complete, sensitive values live in **Vault** (the long-term store) and briefly on the **pod filesystem** while the container runs. They are **not** in Git anymore. You remove `secret.yaml` from `clearledger-infra` and ArgoCD syncs deployments that point at Vault instead.

To load Vault the first time, you copy a template to a local **`.env` file** (§5.1). That file is gitignored. You run `seed-vault-secrets.sh` once to copy those values into Vault. Nothing secret is hardcoded in scripts that get committed.

### Do the steps in this order

Each step depends on the one before it. Skipping ahead is the most common way to get red auth/ledger pods that look like a broken app but really mean “Vault is not ready yet.”

1. **§5.1**: copy `stages/stage-5-secrets-management/.env.example` to `.env`, then fill it with your cluster passwords
2. **§5.2**: install Vault and the agent injector with Helm
3. **§5.3**. Run `setup.sh`, then `seed-vault-secrets.sh` (passwords now live in Vault)
4. **§5.4**: push Vault-enabled deployments to `clearledger-infra`; let ArgoCD sync
5. **§5.5**. Wait for **2/2** pods (app + Vault sidecar), then delete the old Kubernetes Secrets
6. **§5.5b**: ArgoCD **Synced / Healthy** (after secret delete. OutOfSync before delete is normal)
7. **§5.6**. Confirm login works and credentials appear under `/vault/secrets/` inside the pod

Start at **§5.1**. If anything fails, read [troubleshooting.md. Stage 5](troubleshooting.md#stage-5--common-issues) before changing manifests.

---

### 5.1 — Create `.env` (local only, never commit)

This file holds two things: a **dev Vault root token** for Helm (§5.2), and the **passwords you will load into Vault** in §5.3. It stays on your machine only. Never commit it. The `SEED_*` values must match what the app uses today so login still works after you delete Kubernetes Secrets later.

**Two different files. Do not mix them up:**

| File | What it is |
|---|---|
| **`stages/stage-5-secrets-management/.env.example`** | Blank template in the repo (empty fields). **Copy this** in step 1. |
| **`stages/stage-5-secrets-management/.env`** | Your real file (gitignored). You create it and fill it in steps 2–3. |

The sample block at the bottom of this section is **only a picture** of what a completed `.env` looks like: do **not** copy those placeholder passwords unless they happen to match your cluster.

**Step 1: copy the template to `.env`**

```bash
cp stages/stage-5-secrets-management/.env.example \
   stages/stage-5-secrets-management/.env
```

That gives you a file with empty `VAULT_TOKEN=` and `SEED_*=` lines. Open it in your editor for steps 2–3.

**Step 2: read the current passwords from the cluster**

Run these from the repo root. Each command prints one value: copy the output into `.env` in step 3.

```bash
# → paste as SEED_AUTH_DATABASE_URL
kubectl get secret auth-service-secret -n clearledger \
  -o jsonpath='{.data.database_url}' | base64 -d; echo

# → paste as SEED_AUTH_JWT_SECRET
kubectl get secret auth-service-secret -n clearledger \
  -o jsonpath='{.data.jwt_secret}' | base64 -d; echo

# → paste as SEED_LEDGER_DATABASE_URL
kubectl get secret ledger-service-secret -n clearledger \
  -o jsonpath='{.data.database_url}' | base64 -d; echo
```

**Step 3: fill in `.env`**

| Variable | What to put |
|---|---|
| `VAULT_TOKEN` | Any dev-only string you choose (for example, `my-dev-root-token`) — same value in §5.2 Helm install |
| `SEED_AUTH_DATABASE_URL` | Output of first command above |
| `SEED_AUTH_JWT_SECRET` | Output of second command |
| `SEED_LEDGER_DATABASE_URL` | Output of third command |

**Sample only: shape of a completed `.env`** (use **your** kubectl output from step 2, not these example strings unless they match):

```text
VAULT_TOKEN=my-dev-root-token
SEED_AUTH_DATABASE_URL=postgresql://clearledger:changeme-stage0@postgres:5432/clearledger
SEED_AUTH_JWT_SECRET=stage0-jwt-secret-change-in-production
SEED_LEDGER_DATABASE_URL=postgresql://clearledger:changeme-stage0@postgres:5432/clearledger
```

**If `auth-service-secret` is already deleted** (you skipped ahead: recover like this):

```bash
# Database URL from Postgres bootstrap secret (lab default password is often changeme-stage0)
PG_PASS=$(kubectl get secret postgres-secret -n clearledger \
  -o jsonpath='{.data.password}' | base64 -d)
echo "postgresql://clearledger:${PG_PASS}@postgres:5432/clearledger"
# Use that line for both SEED_AUTH_DATABASE_URL and SEED_LEDGER_DATABASE_URL

# JWT — same value you used at Stage 0, or read from Vault if you already seeded:
kubectl exec -n vault vault-0 -- vault kv get -field=jwt_secret clearledger/auth-service 2>/dev/null \
  || echo "(set SEED_AUTH_JWT_SECRET manually — must match tokens already issued)"
```

Continue to **§5.2** once `.env` has all four variables set.

---

### 5.2 — Install Vault and the agent injector

```bash
set -a && source stages/stage-5-secrets-management/.env && set +a

helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update

# First install:
helm install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken="${VAULT_TOKEN}" \
  --set ui.enabled=true \
  --set injector.enabled=true

# If helm install fails with "cannot re-use a name", use upgrade instead:
# helm upgrade --install vault hashicorp/vault \
#   --namespace vault --create-namespace \
#   --set server.dev.enabled=true \
#   --set server.dev.devRootToken="${VAULT_TOKEN}" \
#   --set ui.enabled=true \
#   --set injector.enabled=true

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault -n vault --timeout=120s
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault-agent-injector -n vault --timeout=120s

kubectl apply -f stages/stage-5-secrets-management/infra/vault-ingress.yaml
```

Open `http://vault.local` and sign in with **`VAULT_TOKEN` from your `.env`**.

**Verify: list Vault pods:**

```bash
kubectl get pods -n vault
```

**Expected: Vault pods:**

```text
NAME                                   READY   STATUS    RESTARTS   AGE
vault-0                                1/1     Running   0          1m
vault-agent-injector-8d6b668b4-xxxxx   1/1     Running   0          1m
```

**If `helm install` fails with “cannot re-use a name”**: Vault is already installed; use the `helm upgrade --install` block above.

---

### 5.3 — Configure Vault (platform + seed KV)

Run both scripts in order. Each reads **`VAULT_TOKEN` from your `.env`**.

```bash
bash stages/stage-5-secrets-management/infra/vault/setup.sh
bash stages/stage-5-secrets-management/infra/vault/seed-vault-secrets.sh
```

**`setup.sh`**: prepares Vault for the cluster: Kubernetes auth, the KV secret store, policies, and roles so auth/ledger pods *can* fetch secrets later. It does not write your database passwords yet and nothing goes to Git.

**`seed-vault-secrets.sh`**: takes the `SEED_*` lines from `.env` and stores them in Vault at `clearledger/data/auth-service` and `clearledger/data/ledger-service`. It does not echo those values to the terminal.

Re-running either script is safe for the lab.

**Expected, `setup.sh` (tail):**

```text
==> Enabling Kubernetes auth method...
==> Configuring Kubernetes auth...
==> Enabling KV secrets engine...
==> Creating Vault policies...
==> Creating Kubernetes auth roles...
==> Applying RBAC + ServiceAccounts...

✓ Vault platform setup complete (no secrets written yet).
  Next: bash stages/stage-5-secrets-management/infra/vault/seed-vault-secrets.sh
```

**Expected, `seed-vault-secrets.sh`:**

```text
==> Logging into Vault...
==> Writing secrets to Vault KV (values are not printed)...
======== Secret Path ========
clearledger/data/auth-service
======= Metadata =======
Key                Value
---                -----
created_time       2026-06-01T15:31:53.538991153Z
version            1
✓ Secrets stored at clearledger/data/auth-service and clearledger/data/ledger-service
```

**Verify metadata only** (no secret values printed):

```bash
kubectl exec -n vault vault-0 -- vault kv metadata get clearledger/auth-service
```

```text
Key                     Value
---                     -----
cas_required            false
created_time            2026-06-01T15:31:53.538991153Z
current_version         1
delete_version_after    0s
max_versions            0
oldest_version          0
updated_time            2026-06-01T15:31:53.538991153Z
```

---

### 5.4 — GitOps: update `clearledger-infra` (fixes ArgoCD OutOfSync)

ArgoCD deploys from your **`clearledger-infra`** GitHub repo, not from the main **`clearledger`** app repo where you are working now. You edit manifests here first, then copy the same changes to `clearledger-infra` so ArgoCD can sync them. Work slowly and verify after each sub-step.

**5.4a. Update manifests in the app repo (`clearledger`)**

```bash
cp stages/stage-5-secrets-management/infra/manifests/auth-service/deployment.yaml \
   infra/manifests/auth-service/deployment.yaml
cp stages/stage-5-secrets-management/infra/manifests/ledger-service/deployment.yaml \
   infra/manifests/ledger-service/deployment.yaml
mkdir -p infra/manifests/vault
cp infra/deferred-by-stage/stage-5-secrets-management/vault/rotation-cronjob.yaml \
   infra/manifests/vault/rotation-cronjob.yaml
rm -f infra/manifests/auth-service/secret.yaml infra/manifests/ledger-service/secret.yaml
```

**5.4b. Edit `infra/manifests/kustomization.yaml` by hand**

Open the file in your editor. In the `resources:` list:

- **Remove** the app secret entries: delete these two lines, or comment them out with `#` (both work; Kustomize ignores `#` lines):
  ```yaml
  - auth-service/secret.yaml
  - ledger-service/secret.yaml
  ```
- **Add** this line (with the other resources):
  ```yaml
  - vault/rotation-cronjob.yaml
  ```

Leave **`postgres/postgres-secret.yaml`**, that is Postgres bootstrap only, not app credentials.

Save. Verify:

```bash
# Active (uncommented) app secret lines must be gone — postgres-secret is OK
grep -E '^[[:space:]]*-[[:space:]]+(auth-service|ledger-service)/secret\.yaml' \
  infra/manifests/kustomization.yaml && echo "STOP: app secrets still active" || echo "OK"

grep vault/rotation-cronjob.yaml infra/manifests/kustomization.yaml
grep vault.hashicorp infra/manifests/auth-service/deployment.yaml | head -1
kustomize build infra/manifests >/dev/null && echo "OK: kustomize build"
```

Expected: `OK`; rotation cronjob listed; first line shows `vault.hashicorp.com/agent-inject`; kustomize build succeeds.

Commit in the **app** repo when ready: `git add infra/manifests && git commit -m "feat(stage-5): Vault deployments in canonical manifests"`.

**5.4c. Push the same changes to `clearledger-infra`**

```bash
git clone https://github.com/YOUR_USERNAME/clearledger-infra.git /tmp/clearledger-infra
```

If clone fails with **`destination path '/tmp/clearledger-infra' already exists`** (you cloned in §1.3 or an earlier step), reuse that folder. Do not clone again:

```bash
cd /tmp/clearledger-infra && git pull && cd -
```

Or start fresh: `rm -rf /tmp/clearledger-infra` then run `git clone` again.

**Run the `cp` commands from the main `clearledger` app repo**, not from `/tmp/clearledger-infra`. Your shell prompt should say `clearledger`, not `clearledger-infra`. The source path `infra/manifests/...` only exists in the app repo.

```bash
cd ~/clearledger    # main app repo — adjust path if yours differs

cp infra/manifests/auth-service/deployment.yaml /tmp/clearledger-infra/manifests/auth-service/
cp infra/manifests/ledger-service/deployment.yaml /tmp/clearledger-infra/manifests/ledger-service/
mkdir -p /tmp/clearledger-infra/manifests/vault
cp infra/manifests/vault/rotation-cronjob.yaml /tmp/clearledger-infra/manifests/vault/
cp infra/manifests/kustomization.yaml /tmp/clearledger-infra/manifests/kustomization.yaml
rm -f /tmp/clearledger-infra/manifests/auth-service/secret.yaml
rm -f /tmp/clearledger-infra/manifests/ledger-service/secret.yaml

cd /tmp/clearledger-infra
git add -A
git status
git commit -m "feat(stage-5): Vault injection; remove app secrets from GitOps"
git push
cd -
```

**✋ Hands-on checkpoint. Stage 5 GitOps landed**

```bash
git clone --depth 1 https://github.com/YOUR_USERNAME/clearledger-infra.git /tmp/verify-s5
test ! -f /tmp/verify-s5/manifests/auth-service/secret.yaml && echo "OK: app secret removed from Git"
grep vault.hashicorp /tmp/verify-s5/manifests/auth-service/deployment.yaml | head -1
grep vault/rotation-cronjob.yaml /tmp/verify-s5/manifests/kustomization.yaml
rm -rf /tmp/verify-s5
```

Expected: `OK`; Vault annotation present; rotation job in kustomization.

**Expected, `git status` before commit (step 5.4c):**

```text
modified:   manifests/auth-service/deployment.yaml
modified:   manifests/ledger-service/deployment.yaml
modified:   manifests/kustomization.yaml
new file:   manifests/vault/rotation-cronjob.yaml
deleted:    manifests/auth-service/secret.yaml
deleted:    manifests/ledger-service/secret.yaml
```

After `git push`, ArgoCD will roll out Vault-enabled deployments automatically. **Continue to §5.5**. Do not expect **Synced** yet; app secrets still in the cluster until you delete them there.

**Common rollout failures:**

| Symptom | Fix |
|---|---|
| `Duplicate value: "vault-secrets"` | Do **not** declare a `vault-secrets` volume in `deployment.yaml` — the injector creates it |
| `Service appeared 2 times` | Keep `Service` only in `service.yaml`, not at the bottom of `deployment.yaml` |
| Kyverno `containers/0` `runAsNonRoot` | Add `runAsNonRoot: true` on the **app** container `securityContext`, not only on `spec.securityContext` |
| Pods stuck `1/1` (no sidecar) | Confirm `injector.enabled=true` and deployment has `vault.hashicorp.com/agent-inject: "true"` |
| `permission denied` in vault-agent-init | Run `setup.sh` — K8s auth role not bound to service account |
| ArgoCD **Sync failed** on `CronJob/vault-secret-rotation` | Kyverno blocked the job — `infra/manifests/vault/rotation-cronjob.yaml` must include `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, and CPU/memory limits; push fix to `clearledger-infra` |

---

### 5.5 — Wait for Vault-injected pods, then delete K8s app Secrets

**Wait until auth/ledger show Vault sidecars** (`READY 2/2` = app + vault-agent):

```bash
kubectl get pods -n clearledger -l app=auth-service
kubectl get pods -n clearledger -l app=ledger-service
```

**Expected:**

```text
NAME                            READY   STATUS    RESTARTS   AGE
auth-service-5756d9fcb9-bmdlr   2/2     Running   0          2m
auth-service-5756d9fcb9-jtgss   2/2     Running   0          2m
```

Inspect sidecar pulled secrets (init container logs):

```bash
kubectl logs -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c vault-agent-init
# ... Authentication successful, rendering templates ...
```

**Only after pods are 2/2**, delete app Secrets:

```bash
kubectl delete secret auth-service-secret ledger-service-secret -n clearledger
```

**Expected: secrets remaining:**

```bash
kubectl get secret -n clearledger
```

```text
NAME              TYPE     DATA   AGE
postgres-secret   Opaque   2      6d
```

`postgres-secret` is **Postgres bootstrap only**, not app credentials. That stays until you harden Postgres separately.

**If delete says `NotFound`**: secrets were already removed. Continue to §5.6.

### 5.5b — ArgoCD should be Synced (after secret delete)

**Run this after §5.5**, not right after §5.4. Before you delete app Secrets, **OutOfSync is normal**. Git no longer lists `auth-service-secret` / `ledger-service-secret`, but they still exist in the cluster until you delete them in the step above.

```bash
kubectl get application clearledger -n argocd \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
```

**Before secret delete:** expect `sync=OutOfSync health=Healthy` or `Progressing` while Vault pods roll out, that is fine if auth/ledger are **2/2**.

**After secret delete**, hard-refresh and sync if still OutOfSync:

```bash
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web --prune
```

If sync says **another operation is already in progress**, wait a minute: ArgoCD auto-sync is already running.

Wait until:

```bash
kubectl get application clearledger -n argocd \
  -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# Synced Healthy
```

**Do not `kubectl apply` deployments** if ArgoCD manages the cluster, `selfHeal` reverts manual changes. Git is the contract (Stage 2).

---

### 5.6 — The aha moment (login + injected files)

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- ls /vault/secrets/
```

```text
database_url
jwt_secret
```

```bash
curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' | jq .
```

**Expected:**

```json
{
  "access_token": "<jwt-returned-by-auth-service>",
  "token_type": "bearer"
}
```

**Take a screenshot:** working login JSON + `kubectl get secret -n clearledger` showing **no** `auth-service-secret` / `ledger-service-secret`.

---

### 5.7 — Health check

```bash
make check-5
```

**What you should see:**

> `make check-5` re-runs Stage 4 checks first, that is expected. Look for the Stage 5 block below to confirm Vault is working.

```text
▶ Stage 4 — Admission Control (Kyverno)
  ✓ Kyverno is running
  ✓ Policy disallow-root-containers — Enforce mode
  ...
  ✓ kube-bench matches baseline (no new FAIL regressions)

▶ Stage 5 — Secrets Management (Vault)
  ✓ Vault pod is running
  ✓ Vault agent injector is running
  ✓ Vault is unsealed
  ✓ Vault Kubernetes auth method is enabled
  ✓ auth-service-secret removed — Vault is the secret source
  ✓ Vault injected /vault/secrets/database_url into auth-service

All checks passed. Ready for the next stage.
```

If Vault injection or ArgoCD sync fails, see [troubleshooting.md: Vault Issues](troubleshooting.md#vault-issues).

---

### Stage 5 complete — done checklist (move to Stage 6)

| # | Check | How to verify |
|---|---|---|
| 1 | Secrets in Vault only | `vault kv metadata get clearledger/auth-service` shows `current_version >= 1` |
| 2 | No app secrets in infra Git | `secret.yaml` absent from `clearledger-infra/manifests/auth-service/` and `ledger-service/` |
| 3 | ArgoCD synced | `Synced Healthy` on Application `clearledger` |
| 4 | K8s app secrets deleted | `kubectl get secret -n clearledger` — no auth/ledger app secrets |
| 5 | Injection works | Auth pods `2/2`; `ls /vault/secrets/` shows `database_url`, `jwt_secret` |
| 6 | App works | Login curl returns `access_token` |
| 7 | Health check | `make check-5` ends with **`All checks passed. Ready for the next stage.`** |

**Portfolio screenshots (optional):** login JSON beside `kubectl get secret -n clearledger` · auth pod `2/2` with Vault sidecar · Vault UI signed in.

*Not yet: Postgres bootstrap into Vault (optional), Vault HA/auto-unseal (dev mode is fine for the lab), Falco runtime detection (Stage 6). Credentials are out of Git: a compromised pod can still read `/vault/secrets/*` at runtime; Stage 6 detects that.*

### What You Learned in Stage 5

- Why Kubernetes Secrets are not secret management (encoding ≠ encryption; etcd exposure)
- That **Vault KV** is the source of truth; `.env` is a one-time bootstrap channel, never committed
- How Vault agent injection works via deployment annotations and service account JWT
- That GitOps must drop `secret.yaml` from **`clearledger-infra`**, not only from the app repo
- That **order matters**: Vault ready → seed KV → GitOps → healthy pods → delete K8s Secrets
- **The security improvement:** app credentials are not in Git, not in etcd as K8s Secrets, and disappear when the pod stops

**What you can now put on your CV / say in an interview:**

> Replaced Kubernetes Secrets with HashiCorp Vault agent injection so no credentials live in Git or etcd, and can explain runtime injection and rotation.

`make snapshot STAGE=5 && make snapshots`. Confirm `clearledger.stage5`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

---

## Stage 6 — Runtime Security (Falco)

> Stages 1–5 secured what gets deployed and how secrets are stored. Stage 6 watches what happens inside running containers after they start.

**Your goal** is to learn what runtime security catches and why it matters, then prove it by triggering a Falco alert and reading it the way an on-call engineer would.

CI, Kyverno, and Vault all act before or at pod startup. Falco fills the gap they leave open. It watches what running software actually does inside the container. That is the layer incident response and forensics care about, not just another chart to install.

> **Am I ready for Stage 6?**
>
> - [ ] `make check-5` passes: Vault is injecting secrets and app Secrets are gone from Git and the cluster
> - [ ] Login and transactions still work at `http://clearledger.local`
> - [ ] Platform pods are stable with low restarts ([platform stability](#heading-platform-stability-from-stage-4-onward))
>
> **You are done** when you have triggered at least one Falco alert (§6.2 or §6.3), applied network policies (§6.4), and `make check-6` passes (§6.6).
>
> **Then save your VM:** `make snapshot STAGE=6`, then `make snapshots`. Confirm `clearledger.stage6` is in the list.

### Do the steps in this order

Each step depends on the one before it. **Do not run `make check-6` until §6.4**. It checks network policies you have not applied yet.

1. **§6.1:** `bash stages/stage-6-runtime-security/scripts/install-falco.sh`. Confirm `falco-*` pods `2/2 Running` and custom rules loaded
2. **§6.2:** `make demo-6`: read **`✓ Runtime detection confirmed`** in the terminal
3. **§6.3** (optional) manual break-it scenarios (skip if `make demo-6` already worked)
4. **§6.4:** `kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml`. Confirm `curl http://clearledger.local/` returns 200
5. **§6.6:** `make check-6`

Start at **§6.1**. If anything fails, see [troubleshooting.md. Stage 6](troubleshooting.md#stage-6--runtime-security-falco).

**Optional reading:** [How Stage 6 fits the full stack](#heading-how-stage-6-fits-the-full-stack-optional-reading): why Falco and netpol exist and how they differ from Stages 3–5.

### If you get stuck in Stage 6

**If you feel lost:** You are installing a syscall watcher (Falco), triggering one demo alert, then adding network policies. You do not need to decode every row in the Falco UI: one matching alert (terminal or UI) is enough.

Open **`http://falco.local`** (login `admin` / `admin`) for the portfolio screenshot.

**Common stuck points**

| You think… | What is actually true |
|---|---|
| “The UI shows 200+ Critical alerts — I broke something” | No. **`postgres-0`** reads `/etc/passwd` on a loop and Falco flags it. Ignore those rows. |
| “I cannot find my demo alert” | Search the UI with **Cmd+F → `Shell Spawned`**, or use the **terminal grep** in step 4 above. If grep shows `auth-service` + `id && exit`, you passed. |
| “`make check-6` failed on NetworkPolicy” | You ran the check **before §6.4**. Apply netpol first, then re-run. |
| “§6.3 vs §6.2 — which do I run?” | Run **`make demo-6` (§6.2)** only. §6.3 is the same attacks as manual commands — skip it if demo-6 already worked. |
| “What is Shell Spawned?” | Falco saw a **`sh` process start** inside `auth-service`. That is suspicious in production; in the lab, **you** caused it on purpose — see §6.2. |
| “Scenario 4 hangs or exit 137” | Old **`wget`** command + **Terminating** pod. Skip Scenario 4 or use the **python3** command in §6.4. Checkpoint + `make check-6` is enough. |

---

### 6.1 — Install Falco and Falcosidekick UI

```bash
bash stages/stage-6-runtime-security/scripts/install-falco.sh
```

This runs `helm upgrade --install` with `modern_ebpf`, enables Falcosidekick + Web UI, enables the **k8s-metacollector** (`collectors.kubernetes.enabled: true`) so custom rules can match `k8smeta.ns.name = clearledger`, loads rules from `infra/falco/clearledger-rules-content.yaml`, applies the rules ConfigMap and ingress.

**If Falco is already installed**, the script is safe to re-run (upgrade).

**Verify Falco pods:**

```bash
kubectl get pods -n falco
```

**Expected output:**

```text
NAME                                      READY   STATUS    RESTARTS   AGE
falco-w4fh6                               2/2     Running   0          2m
falco-falcosidekick-...                   1/1     Running   0          2m
falco-falcosidekick-ui-...                1/1     Running   0          2m
falco-falcosidekick-ui-redis-0            1/1     Running   0          2m
```

The Falco DaemonSet should show **2/2 Running**. Sidekick, UI, and Redis pods should each show **1/1 Running**. Pod name suffixes on your cluster will differ from the example.

Open **`http://falco.local`**. Falcosidekick UI. Log in with the chart defaults:

| Field | Value |
|---|---|
| **Login** | `admin` |
| **Password** | `admin` |

To read the credentials from the cluster instead of trusting the lab defaults:

```bash
kubectl get secret falco-falcosidekick-ui -n falco \
  -o jsonpath='{.data.FALCOSIDEKICK_UI_USER}' | base64 -d && echo
# admin:admin
```

#### Falcosidekick UI — quick orientation

After login you land on the **Events** tab. The table can look busy before you run any demo, that is normal.

- **Rule** — detection name (what fired)
- **Priority** — **Critical** / **Warning** / **Notice** (focus on Critical and Warning for this lab)
- **Output** — pod name, file, or command details
- **Tags** — look for `clearledger` on lab alerts

**Background noise you can ignore:** **Notice** rows from ArgoCD; **Critical** **Sensitive File Read** rows from **`postgres-0`** reading `/etc/passwd` (repeats every few seconds). Your demo alert is different. See §6.2.

**Verify custom rules loaded** (do this before §6.2):

```bash
kubectl get pods -n falco                                    # Falco pod 2/2 Running
kubectl get configmap clearledger-falco-rules -n falco
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=200 \
  | grep 'rules.d/clearledger_rules'
```

**Expected:** `clearledger_rules.yaml | schema validation: ok`

An empty grep with `--tail=30` alone is **not** a failure. Use `--tail=200`. If you see `LOAD_ERR_COMPILE_CONDITION`, see [troubleshooting.md. Stage 6](./docs/troubleshooting.md#stage-6--runtime-security-falco).

If rules did not load, §6.2 and §6.3 will look like they passed when nothing fired.

---

### 6.2 — Guided demo (`make demo-6`)

Run this **after** §6.1 (Falco installed, rules verified, UI opens at `http://falco.local`).

```bash
make demo-6
# or:
bash stages/stage-6-runtime-security/scripts/demo-falco-alerts.sh
```

#### What the demo script does

The demo proves Falco can detect suspicious activity inside a running container.

The script checks that Falco is running, opens `http://falco.local`, and waits while you log in with:

- Username: `admin`
- Password: `admin`

Then it runs this test command inside the `auth-service` container:

```bash
kubectl exec -n clearledger \
  auth-service-<pod-suffix> \
  -c auth-service -- /bin/sh -c 'id && exit'
```

The script picks the real pod name for you.

**Non-interactive** (CI or no Enter prompts): `SKIP_PROMPT=1 make demo-6`

This starts a shell inside the app container. That is suspicious in production because app containers should run the app, not open shells. Falco should detect it and create an alert called:

`Shell Spawned in ClearLedger Container`

When the script prints:

```text
✓ Runtime detection confirmed
```

refresh the Falco UI.

Look for a **Critical** alert with:

- Rule: `Shell Spawned in ClearLedger Container`
- Pod: `auth-service-...`
- Command: `sh -c id && exit`

Ignore alerts from `postgres-0`, especially `Sensitive File Read`. Those are background noise for this lab.

If the UI is noisy, search the page for `Shell Spawned` or check from the terminal:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=500 \
  | grep 'Shell Spawned'
```

For your screenshot, capture the `Shell Spawned` alert for `auth-service`.

---

### 6.3 — Break-it scenarios (manual, optional)

Same detections as §6.2, but you run each command yourself. Skip this section if you already completed `make demo-6`.

| Rule name | You trigger it by… |
|---|---|
| **Shell Spawned in ClearLedger Container** | Scenario 1 — `kubectl exec … /bin/sh` |
| **Sensitive File Read in ClearLedger** | Scenario 2 — `cat /etc/passwd` |
| **Package Manager / Outbound connection** | Scenario 3 — `wget` or `curl` |

After each command, refresh **`http://falco.local`** or use the find methods in §6.2.

**Scenario 1. Shell in a running pod (command injection simulation):**

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- /bin/sh -c "id && exit"
```

**Expected in Falco UI / logs** (within ~10 seconds):

```text
CRITICAL: Shell spawned in ClearLedger container
  user=... container=auth-service pod=auth-service-... cmd=sh -c id && exit
```

**What this means:** Stage 4 allowed the pod (it is compliant). Stage 6 detected *behavior inside* the pod: exactly what an attacker would do after command injection.

**If you see no alert:** confirm the exec used `-c auth-service` (not the vault-agent sidecar), rules show `schema validation: ok`, and the pod image name contains `clearledger`.

**Scenario 2. Read a sensitive file (reconnaissance):**

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- cat /etc/passwd
```

**Expected:**

```text
CRITICAL: Sensitive file read in ClearLedger
  file=/etc/passwd container=auth-service pod=auth-service-...
```

**Scenario 3. Download tool at runtime (optional):**

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- sh -c "wget -q ifconfig.me -O - 2>/dev/null || true"
```

May fire **Package manager executed** and/or **Unexpected outbound connection** (WARNING).

**Take screenshots of Scenarios 1 and 2**: portfolio evidence for runtime detection.

---

### 6.4 — Apply network policies (zero-trust segmentation)

Network policies run **after** Falco demos (§6.2 / §6.3). **`make check-6` includes netpol checks. Run it only after this section.**

Network policies are a **firewall between pods**. `default-deny-all` blocks everything; each `allow-*` policy opens specific paths (auth → postgres, ledger → auth, and so on). Falco **detects** bad behavior; netpol **blocks** traffic that should not happen.

**Apply:**

```bash
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
kubectl get networkpolicy -n clearledger
```

**Expected:** seven policies: `default-deny-all` plus six `allow-*` (`auth-service`, `ledger-service`, `notification-service`, `postgres`, `redis`, `frontend`).

**Verify the app still works:**

```bash
curl -s http://clearledger.local/auth/health | jq .
# {"status":"ok","service":"auth-service"}

curl -s http://clearledger.local/notifications/health | jq .
# {"status":"ok",...}
```

**Checkpoint (required)**: proves netpol did not break the real app:

```bash
kubectl get networkpolicy -n clearledger
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/
kubectl get pods -n clearledger --field-selector=status.phase!=Running
```

| Result | Meaning |
|---|---|
| Seven policies listed | Netpol applied |
| `200` from curl | Users can still reach the app through ingress |
| Third command prints **nothing** | No crashed pods |

If auth or ledger start restarting after netpol, egress rules are too strict (see [troubleshooting.md) Stage 6](./docs/troubleshooting.md#stage-6--runtime-security-falco).

**Scenario 4: blocked cross-service traffic (optional)**

Skip if the checkpoint passed and you plan to run `make check-6`. This proves ledger **cannot** call notification directly (no allow rule for that path). **Failure to connect is success.**

**Do not use the old `wget` one-liner**: the ledger image has no `wget`/`curl`, and `head -1` can pick a **Terminating** pod (exec hangs or exit **137**).

```bash
LEDGER_POD=$(kubectl get pods -n clearledger -l app=ledger-service --no-headers \
  | awk '$2=="2/2" && $3=="Running" {print $1; exit}')

echo "Using pod: $LEDGER_POD"

kubectl exec -n clearledger "$LEDGER_POD" -c ledger-service -- python3 -c "
import urllib.request
try:
    urllib.request.urlopen('http://notification-service/', timeout=5)
    print('UNEXPECTED: connection succeeded')
except Exception as e:
    print('BLOCKED (expected):', e)
"
```

**Expected:**

```text
BLOCKED (expected): <urlopen error timed out>
```

or `Connection refused`, **not** `UNEXPECTED: connection succeeded`.

---

### 6.6 — Health check

Run this **after §6.4** (network policies). It confirms Falco, custom rules, and netpol are installed. It does **not** prove an alert fired (that is §6.2).

```bash
make check-6
```

**What you should see:**

```text
▶ Stage 6 — Runtime Security (Falco)
  ✓ Falco DaemonSet: 1/1 nodes
  ✓ ClearLedger custom Falco rules ConfigMap exists
  ✓ NetworkPolicy default-deny-all exists
  ✓ NetworkPolicy allow-auth-service exists
  ✓ NetworkPolicy allow-ledger-service exists
  ✓ NetworkPolicy allow-notification-service exists
  ✓ auth-service reachable after network policies
  ✓ notification-service reachable after network policies

All checks passed. Ready for the next stage.
```

---

### How Stage 6 fits the full stack (optional reading)

Each stage guards a different point in the lifecycle. Stages 1 through 5 work before or during pod startup. Stage 6 watches what happens **inside** a container that is already running.

**Stage 3. CI** catches bad code and images on `git push`. **Stage 4 (Kyverno** blocks bad pods at admission. **Stage 5) Vault** injects secrets at startup. **Stage 6. Falco** watches syscalls after the pod is running (shell spawns, sensitive file reads). **Stage 6. Network policies** filter pod-to-pod traffic.

Three different questions: Kyverno asks whether this pod may be created. Falco asks what the pod is doing right now. Network policies ask who the pod may talk to. Falco does not replace CI or Kyverno. If you skip Stages 3–5, Falco can still alert, but you already shipped vulnerable code and secrets in Git.

---

### Stage 6 complete — done checklist (move to Stage 6.5 / 7)

| # | Check | How to verify |
|---|---|---|
| 1 | Falco running | `kubectl get pods -n falco` — DaemonSet `2/2` |
| 2 | Custom rules loaded | `kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=200 \| grep rules.d/clearledger` |
| 3 | Shell alert fired **and you read it** | `make demo-6` → Critical row with `cmd=sh -c id && exit`, pod `auth-service-…` — §6.2 |
| 4 | Network policies applied | `kubectl get networkpolicy -n clearledger` — §6.4 |
| 5 | App still healthy | `curl` auth + notification health return 200 |
| 6 | Health check | `make check-6` green — §6.6 |

**Portfolio screenshots (optional):** shell-in-container alert · sensitive-file read alert in Falco UI.

*Not yet: network-policy refinement, Litmus chaos (optional Stage 6.5), observability dashboards (Stage 7).*

### What You Learned in Stage 6

- What runtime security catches that CI and admission control cannot: threats inside running containers
- What Falco is: eBPF syscall monitoring with custom YAML rules
- What network policies are: Kubernetes firewall rules between pods
- How to trigger and interpret alerts: incident response skills
- **The full stack:** code scanning → admission control → secrets management → runtime detection → (next) observability

**What you can now put on your CV / say in an interview:**

> Deployed Falco for runtime threat detection with custom rules, and can trigger and read an alert for a shell-in-container or sensitive-file read the way an on-call engineer would.

`make snapshot STAGE=6 && make snapshots`. Confirm `clearledger.stage6`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

---

## Stage 6.5 — Chaos Engineering (Optional)

> **Most learners skip this.** If Stage 6 is done and `make check-6` passes, jump straight to [Stage 7](#heading-stage-7-security-observability). Nothing in Stages 7–8 requires Litmus.

**If you want chaos/resilience (~1 hour):** LitmusChaos deletes one `auth-service` pod and proves `/auth/health` stays **200** while Kubernetes replaces it.

### Do the steps in this order

| Step | Section | What you do |
|------|---------|-------------|
| 1 | [§6.5.0](#heading-650-before-you-start-auth-pods-must-be-22) | `make fix-65-prereqs` — auth pods **2/2 Ready** |
| 2 | [§6.5.1](#heading-651-install-litmuschaos-operator-ui-cluster-connection) | `bash ...install-litmus.sh` — UI shows **Active 1** |
| 3 | [§6.5.2](#heading-652-run-your-first-experiment-pod-delete) | UI: Pod-delete experiment + `curl` stays 200 |
| 4 | [§6.5.7](#heading-657-health-check) | `make check-65`, snapshot |

**Optional:** [§6.5.3](#heading-653-same-experiment-from-the-terminal-make-demo-65-optional): same test via `make demo-65` (terminal path) instead of the UI wizard.

---

### 6.5.0 — Before you start (auth pods must be 2/2)

Chaos deletes pods. If replacements fail to start, you debug CrashLoopBackOff instead of learning resilience.

```bash
export GITHUB_OWNER=YOUR_GITHUB_USERNAME   # required — without this, fix-argocd breaks ArgoCD repoURL
make fix-65-prereqs
kubectl get pods -n clearledger -l app=auth-service
```

**Pass:** two pods, both **2/2 Ready**. Do not install Litmus until this is true.

**If something fails:**

| Symptom | Fix |
|---------|-----|
| ArgoCD **ComparisonError** after `fix-65-prereqs` | `kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml` |
| Auth **Init:0/1**, Vault `permission denied` | Re-run Stage 5 `setup.sh` + `seed-vault-secrets.sh`, delete auth/ledger pods |
| Auth **1/2** or postgres timeout | `make fix-65-prereqs` again (adds netpol + startup probes) |

---

### 6.5.1 — Install LitmusChaos (operator, UI, cluster connection)

```bash
bash stages/stage-6.5-chaos-engineering/scripts/install-litmus.sh
kubectl get pods -n litmus
open http://litmus.local    # login: admin / litmus
```

**Pass before §6.5.2:** **Overview** shows **Infrastructures: Active 1** (not 0, not Pending).

**Verify pods:**

```bash
kubectl get pods -n litmus
# litmus-core, chaos frontend/server, mongodb, subscriber — all Running
```

#### If Overview shows 0 infrastructures or PENDING

The UI is empty until a **subscriber agent** connects your cluster:

```bash
export LITMUS_PASSWORD='litmus'   # only if you changed the default
bash stages/stage-6.5-chaos-engineering/scripts/connect-litmus-infra.sh
```

Hard-refresh the browser. Start at **http://litmus.local** only, not old `/account/.../settings` bookmarks.

#### UI navigation (click order for §6.5.2)

1. **Overview**. Confirm **Active 1**
2. **ChaosHubs** → **Pod Delete** → **Launch Experiment**
3. **Chaos Experiments**: watch **Running → Completed**

Left nav: **Overview**, **Environments**, **ChaosHub**, **Chaos Experiments**. Skip **Resilience Probes** and deep **Settings** URLs for this lab.

---

### 6.5.2 — Run your first experiment (pod delete)

**Goal:** Kill one `auth-service` pod and prove `/auth/health` stays **200**.

**Before you click Run in the UI**, open two terminals:

```bash
# Terminal A — watch pods
kubectl get pods -n clearledger -l app=auth-service -w

# Terminal B — watch health every 5 seconds
while true; do
  date +%H:%M:%S
  curl -s -o /dev/null -w "health=%{http_code}\n" http://clearledger.local/auth/health
  sleep 5
done
```

**In the UI (`http://litmus.local`):** Left nav → **ChaosHubs** → **Pod Delete** card → **Launch Experiment**.

> **Litmus UI note:** ChaosCenter labels change between versions (for example, “Tune fault”, “Target selection”, “Chaos Experiment”). Match fields by **concept**, not exact button text. Accept wizard defaults unless the table below lists a value.

**Wizard: map each screen to these values:**

| Concept (what Litmus is asking) | Set to | UI labels you might see |
|---------------------------------|--------|-------------------------|
| **Where to run** | Infrastructure **clearledger-cluster** (**Active**, not Pending) | “Infrastructure”, “Chaos Infrastructure”, “Execution plane” |
| **Target app** | namespace **`clearledger`**, label **`app=auth-service`**, kind **Deployment** | “Target application”, “App namespace/label” |
| **Blast radius** | **50%** pods affected | “Pods affected”, “Percentage”, `PODS_AFFECTED_PERC` |
| **Duration** | **30** seconds | “Total chaos duration”, “Duration” |
| **Fault name** | `pod-delete` (usually pre-filled from hub) | “Experiment name”, “Fault” |

Click **Save/Create** to finish the wizard, then **Run** (not **Schedule**).

**What success looks like:**

| Where | Good sign |
|-------|-----------|
| Terminal A | One pod **Terminating**, then back to **2/2 Ready** |
| Terminal B | `health=200` even while one pod is down |
| Litmus UI | Experiment **Running → Completed** |

**Prefer terminal over UI?** Skip the wizard and run [§6.5.3](#heading-653-same-experiment-from-the-terminal-make-demo-65-optional) (`make demo-65`) instead.

---

### 6.5.3 — Same experiment from the terminal (`make demo-65`) — optional

Use this if you want to run the pod-delete test without clicking through the Litmus UI.

Make sure auth pods are healthy first:

```bash
make fix-65-prereqs
```

Then run the demo:

```bash
make demo-65
```

The script applies the `auth-service-pod-delete` ChaosEngine in the `litmus` namespace. Litmus deletes one `auth-service` pod, Kubernetes replaces it, and the script checks that `/auth/health` keeps returning `200`.

After it finishes, verify the result:

```bash
kubectl get chaosresult -n litmus
kubectl get pods -n clearledger -l app=auth-service
```

You passed if the script ends with `PASS`, the `ChaosResult` is `Completed / Pass`, and two `auth-service` pods are running again.

You can also see the run in the Litmus UI: **Chaos Experiments** → refresh → open the latest run.

If new auth pods get stuck in `Init:0/1`, re-apply the Stage 6 network policies:

```bash
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
```

---

### 6.5.3a — Real output examples (verified on the lab cluster)

These samples were captured from a working cluster after `make fix-65-prereqs`, `make connect-litmus`, and `make demo-65`.

#### `make check-65`

```text
▶ Stage 6.5 — Chaos Engineering (LitmusChaos)
  ✓ litmus namespace exists
  ✓ litmus-admin ServiceAccount exists in litmus
  ✓ pod-delete ChaosExperiment installed in litmus
  ✓ Litmus chaos operator is running
  ✓ Litmus ChaosCenter reachable at http://litmus.local
  ✓ Litmus subscriber running (UI connected to cluster)
  ✓ auth-service healthy (baseline before chaos)
  ✓ auth-service has 2/2 Ready replicas (stable for chaos)
  ✓ allow-postgres NetworkPolicy exists (Stage 6 fix)

All checks passed. Ready for the next stage.
```

#### `make demo-65` — captured from a real run (2026-06-01)

```text
Stage 6.5 — auth-service pod-delete

Preflight: 2 auth-service pods Running

Applying ChaosEngine auth-service-pod-delete (namespace litmus)

Watching http://clearledger.local/auth/health

  10s  health=200  pods=2
  20s  health=200  pods=1
  30s  health=200  pods=1
  40s  health=200  pods=2
  50s  health=200  pods=2
  60s  health=200  pods=2

Result:
  ChaosResult: Completed / Pass
  Recovery:    2 auth-service pod(s) Running
  Health:      6/6 checks returned 200

PASS
```

> If health lines show `000`, run `bash scripts/setup-hosts.sh` on your Mac and re-run. The script also tries `multipass exec clearledger -- curl` when the VM is present.

#### Terminal B (health loop — expected output)

```text
22:05:01
health=200
22:05:06
health=200
22:05:11
health=200
```

> Pod count may show **1** while the replacement pod is starting, that is expected.

#### Terminal A during chaos (`kubectl get pods -w`)

```text
NAME                            READY   STATUS        RESTARTS   AGE
auth-service-84cc988c4d-hdb45   2/2     Running       0          67m
auth-service-84cc988c4d-b59sj   2/2     Terminating   0          15m    ← killed
auth-service-84cc988c4d-dxz9q   0/2     Pending       0          0s     ← replacement
auth-service-84cc988c4d-dxz9q   0/2     Init:0/1      0          2s
auth-service-84cc988c4d-dxz9q   2/2     Running       0          90s
```

#### After demo — verify

```bash
kubectl get chaosresult -n litmus
# auth-service-pod-delete-pod-delete   Completed   Pass

kubectl get pods -n clearledger -l app=auth-service
# auth-service-84cc988c4d-xxxxx   2/2   Running
# auth-service-84cc988c4d-yyyyy   2/2   Running

kubectl get cm subscriber-config -n litmus -o jsonpath='{.data.IS_INFRA_CONFIRMED}'
# true
```

#### Subscriber connected (infrastructure Active in UI)

```text
kubectl logs -n litmus -l app.kubernetes.io/name=subscriber --tail=3
level=info msg="AgentID: a63c2a2c-... has been confirmed"
level=info msg="Server connection established, Listening...."
```

---

### 6.5.4 — Understand the YAML files (read before running)

Each file is a **`ChaosEngine`**: a request to Litmus: “run experiment X against app Y for Z seconds.”

#### `litmus-install.yaml`

Creates the `litmus` namespace only. Platform workloads live here, separate from `clearledger` app pods.

#### `litmus-rbac.yaml`

| Resource | What it does |
|---|---|
| `ServiceAccount litmus-admin` (namespace `litmus`) | Identity for Litmus runner pods |
| `ClusterRoleBinding → cluster-admin` | Allows deleting pods / injecting faults in `clearledger` (lab simplification; production would use least-privilege) |

#### `auth-service-pod-delete.yaml` (Experiment 1 — used by demo)

```yaml
metadata:
  namespace: litmus          # engine lives here (Kyverno-safe)
spec:
  appinfo:
    appns: clearledger       # target app namespace
    applabel: app=auth-service
    appkind: deployment
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: PODS_AFFECTED_PERC
              value: "50"    # 50% of 2 replicas = 1 pod killed
            - name: TOTAL_CHAOS_DURATION
              value: "30"    # chaos window in seconds
```

**What happens when applied:**

1. Operator reads `ChaosEngine` → creates `auth-service-pod-delete-runner` pod in `litmus`
2. Runner selects one `auth-service` pod in `clearledger` → sends SIGTERM / delete
3. Kubernetes Deployment controller sees 1/2 replicas → schedules a replacement pod
4. Service routes traffic to the **surviving** replica during recovery
5. `ChaosResult` CR records pass/fail from Litmus’s perspective

#### `ledger-service-network-latency.yaml` (Experiment 2 — manual)

Adds **2000 ms** network latency to `ledger-service` pods for 60 seconds. Proves timeouts return **503** instead of hanging the UI.

#### `notification-service-memory-hog.yaml` (Experiment 3 — manual)

Fills **80%** of pod memory limit for 60 seconds. Proves OOMKill + restart behavior.

> **Never apply all three at once.** Run one experiment, verify recovery, then the next.

---

### 6.5.5 — After the demo — what to look for (do not skip)

**1. During chaos: availability**

| Signal | Good | Bad |
|---|---|---|
| `curl http://clearledger.local/auth/health` | **200** while one pod is down | 502/503/timeout |
| `kubectl get pods -l app=auth-service` | 1 Running + 1 Init/Pending (replacement starting) | 0 Running |

**2. After chaos: recovery**

| Signal | Good | Bad |
|---|---|---|
| Pod count | 2/2 **Ready** (may take 1–2 min — Vault agent init) | Stuck at 1 replica |
| Events | `Killing` then `Scheduled` / `Started` on new pod | Repeated CrashLoopBackOff |
| ArgoCD | Synced | — |

**3. Litmus `ChaosResult` verdict**

```bash
kubectl get chaosresult -n litmus
```

**Your pass criteria:**

- `/auth/health` returned **200** at least once during the chaos window
- A pod was **Killed** (see events)
- Deployment returned to **2 replicas**

---

### 6.5.6 — Manual experiments (after Experiment 1 succeeds)

Wait until both auth-service pods show **2/2 Ready**, then run **one** experiment at a time:

```bash
# Experiment 2 — 2s network latency on ledger-service (60s)
kubectl delete chaosengine ledger-service-network-latency -n litmus --ignore-not-found
kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/ledger-service-network-latency.yaml

# Experiment 3 — memory pressure on notification-service (60s)
kubectl delete chaosengine notification-service-memory-hog -n litmus --ignore-not-found
kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/notification-service-memory-hog.yaml
```

| Experiment | File | What to verify |
|---|---|---|
| Pod delete | `auth-service-pod-delete.yaml` | Health 200 during kill; 2 replicas after |
| Network latency | `ledger-service-network-latency.yaml` | API returns 503/timeout, not infinite hang |
| Memory hog | `notification-service-memory-hog.yaml` | Pod OOMKills and restarts; Redis subscription recovers |

Clean up an experiment:

```bash
kubectl delete chaosengine auth-service-pod-delete -n litmus
```

---

### 6.5.7 — Health check

```bash
make check-65
```

**Expected:** see full sample in [§6.5.3a](#heading-653a-real-output-examples-verified-on-the-lab-cluster) (`make check-65` block). Minimum:

```text
▶ Stage 6.5 — Chaos Engineering (LitmusChaos)
  ✓ Litmus subscriber running (UI connected to cluster)
  ✓ auth-service has 2/2 Ready replicas (stable for chaos)
  ...
All checks passed. Ready for the next stage.
```

---

### Stage 6.5 complete — done checklist

| # | Check | How to verify |
|---|---|---|
| 1 | Litmus operator running | `kubectl get pods -n litmus` — `litmus-*` Running |
| 2 | Experiments installed | `kubectl get chaosexperiment pod-delete -n litmus` |
| 3 | Pod-delete demo run | `make demo-65` — health 200 during chaos |
| 4 | Recovery observed | 2 auth-service replicas Ready; Killing/Scheduled events |
| 5 | Evidence saved | Terminal output from `run-chaos.sh` (DORA artifact) |
| 6 | Health check | `make check-65` green |
| 7 | UI infrastructure connected | Overview → **Active: 1** (§6.5.2) |

### What You Learned in Stage 6.5

- **Detection ≠ resilience** — Falco alerts do not prove HA
- **Replicas + Services + probes** — why `replicas: 2` is not cosmetic
- **ChaosEngine YAML** — declarative failure injection as code
- **Platform vs app namespaces** — Kyverno blocks chaos runners in `clearledger`; engines run in `litmus`
- **MTTR** — time from pod kill to 2/2 Ready again (Stage 7 graphs this)

**What you can now put on your CV / say in an interview:**

> Ran chaos experiments with LitmusChaos (pod-delete, network latency, memory pressure) to prove the system recovers, and can distinguish detection from resilience.

`make snapshot STAGE=65 && make snapshots`. Confirm `clearledger.stage65`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

---

## Stage 7 — Security Observability

> Security you cannot measure you cannot prove.

**Goal:** Understand how **metrics**, **logs**, and **dashboards** fit together. Then prove it by running commands in the terminal, watching the same events appear in Grafana, and explaining what each panel means.

This stage is **not** “install Grafana and move on.” **Stage 7 is not complete** until your dashboards show **real** Kyverno violations and Falco alerts that **you triggered** in §7.4: plus portfolio screenshots (§7.6). `make check-7` only proves the stack is up; it does **not** prove you can detect security events.

**Before you start:** `make check-6` should pass (Stage 6.5 is optional. Skip is fine). Check the VM is not overloaded: `multipass exec clearledger -- uptime`. If you ran Stage 6.5, do [§7.0](#heading-70-free-node-resources-scale-down-litmus) first to scale Litmus down. Plan about half a day. This is the heaviest stage on a single-node VM.

**Done when:** §7.6 is complete: dashboards show **your** Kyverno denial and Falco alert, not empty panels. Then `make check-7` (§7.7), `make snapshot STAGE=7`, and `make snapshots` (confirm `clearledger.stage7`).

**Already installed?** If `kubectl get pods -n monitoring` shows Grafana **3/3** and Loki **1/1**, skip §7.1. Start at §7.2 (verify the stack), then §7.4 (hands-on lab).

---

### What You Need to Know First

Up to now, each stage had its own window into the cluster. Stage 3 gave you CI scan results in GitHub Actions. Stage 4 showed Kyverno blocking a bad deploy in the terminal. Stage 6 gave you Falco alerts in its UI, and you could always run `kubectl logs` on a pod. Those views are useful, but they are scattered.

Stage 7 brings them together in one place: **Grafana**. Instead of jumping between five different tools, you open a dashboard and see whether security events, policy violations, and app health are happening over time.

#### The three tools you are installing

**Prometheus** collects numbers from the cluster: things like “how many Kyverno denials in the last hour” or “how many HTTP requests per second.” It checks those numbers every 15–30 seconds and keeps a history you can graph.

**Loki** collects log lines: the same kind of text you see from `kubectl logs`, but from many pods at once. Falco alerts, failed login attempts, and application errors all land here so you can search them later.

**Grafana** is the web UI where charts and tables pull data from Prometheus and Loki. This is what you would show an auditor: not a one-off terminal screenshot, but proof that you can **find and measure** events after they happen.

Prometheus does not magically know what to collect. **ServiceMonitors** and **PodMonitors** are small config objects that point it at the right targets. If Kyverno has no monitor, the Kyverno dashboard stays empty even when Kyverno is working fine. The same applies to application request rates. Those panels stay blank until §7.5, when metrics-enabled images are deployed through GitOps.

Logs follow a similar path. **Promtail** reads container logs and sends them to Loki. If Loki is not running, Grafana log panels show “No data” even though `kubectl logs` still works on individual pods.

#### How this connects to what you already built

When you blocked a bad `kubectl apply` in Stage 4, Kyverno recorded that denial. In Stage 7, that shows up on the **Kyverno Policy Violations** dashboard (via Prometheus).

When you triggered a shell inside a pod in Stage 6, Falco wrote an alert. In Stage 7, that appears on the **Security Event Timeline** (via Loki).

When ClearLedger handles HTTP traffic or a failed login, those events feed the **Service Health** dashboards (Loki and Prometheus together).

Vault (Stage 5) and network policies (Stage 6) do not always have their own flashy panel, but they still matter: fewer secrets in Git and blocked pod traffic show up indirectly in a healthier, quieter cluster.

#### What you will do in this stage

You will run a command in the terminal (for example, a Kyverno violation or a Falco trigger) and then wait a short time while Prometheus or Loki ingests the event. Within about 15–90 seconds, the matching Grafana panel should update.

That is the whole point of observability for security: the terminal proves the event happened once; the dashboard proves you can **detect and measure** it later, without being logged into the cluster at that exact moment.

---

### 7.0 — Free node resources (scale down Litmus)

Stage 6.5 is complete. You do not need the Litmus UI, MongoDB, or chaos operator running while Prometheus, Loki, and Grafana start. They compete for the same CPUs on a single-node lab VM (6 by default; see `scripts/setup-cluster.sh`). Scaling Litmus to zero frees ~500–800MB RAM and reduces CPU churn before the observability install.

```bash
kubectl scale deployment,statefulset -n litmus --replicas=0 --all
kubectl get pods -n litmus
# Expected: no Running pods (Succeeded job pods from chaos experiments are OK)
multipass exec clearledger -- uptime
# Expected: load average (1m) ideally below ~8 before continuing
```

You can scale Litmus back up later if you want to re-run chaos experiments (`bash stages/stage-6.5-chaos-engineering/scripts/install-litmus.sh`). For Stages 7–7.5, keep it scaled down.

---

### 7.1 — Install the observability stack

**Safe to run more than once.** The script checks what is already installed. If Grafana, Prometheus, and Loki are healthy, it skips the heavy install and only updates dashboards and scrape configs. Running it again after a partial failure will not duplicate or break a working stack.

**When to add `FORCE=1`:** only if something is genuinely stuck, for example you edited the Helm values files and need a full reinstall, or Loki keeps crashing in a restart loop:

```bash
FORCE=1 bash stages/stage-7-observability/scripts/install-observability.sh
```

On a first-time install, use the plain command in Step 1 below. Do not use `FORCE=1` unless the troubleshooting section tells you to.

**macOS, Linux, and WSL2:** `FORCE=1 bash ...` works as written. **Native Windows PowerShell** does not use that syntax. Run the lab inside **WSL2 Ubuntu** (recommended), or set the variable first: `$env:FORCE=1; bash stages/stage-7-observability/scripts/install-observability.sh`.

**Step 1: install** (wait until the script prints `✓ Stage 7 installed.`):

```bash
bash stages/stage-7-observability/scripts/install-observability.sh
```

#### While Step 1 runs — you may see “Waiting for Falco” near the end

Most of the install is about Grafana, Prometheus, and Loki. Then the terminal suddenly mentions Falco again. If you finished Stage 6 a while ago, that can feel out of place.

**What you already have from Stage 6:** Falco watches running pods and writes alerts when something suspicious happens: like a shell starting inside `auth-service`. You proved that worked at `http://falco.local` or with `kubectl logs`.

**What Stage 7 adds:** Grafana cannot open the Falco UI. Stage 7 builds a path so the **same alerts** also show up on a Grafana dashboard called **Security Event Timeline**. Think of it as plumbing:

1. Falco still runs in the `falco` namespace (same as Stage 6).
2. **Promtail** (installed with Loki) copies Falco’s log lines into **Loki**.
3. Grafana reads those lines from Loki and draws the timeline chart.

The install script touches Falco one more time to make sure that plumbing can connect. It re-runs the **same Stage 6 Helm chart**: an upgrade, not a second Falco. You might see `Waiting for Falco DaemonSet` for a few minutes. **Let it finish.** That message is expected.

Empty Grafana panels right after install are also normal. You have not triggered any new alerts yet. In **§7.4** you run a shell inside a pod again (same idea as Stage 6) and watch the alert land on the **Security Event Timeline** in Grafana, not only in the Falco UI.

**Step 2. Check pods** (run this after Step 1 finishes):

```bash
kubectl get pods -n monitoring
```

You want something like this (pod name suffixes vary):

```text
NAME                                              READY   STATUS    RESTARTS   AGE
kube-prometheus-stack-grafana-....                3/3     Running   0          5m
kube-prometheus-stack-prometheus-....             2/2     Running   0          5m
loki-0                                            1/1     Running   0          5m
loki-promtail-....                                1/1     Running   0          5m
```

Grafana must show **3/3** Ready (not 2/3). Loki must show **1/1**. If pods are still `Pending` or `ContainerCreating`, wait a few minutes and run `kubectl get pods -n monitoring` again.

**Expected. Loki healthy:**

```bash
kubectl exec -n monitoring loki-0 -- wget -qO- http://127.0.0.1:3100/ready
```

```text
ready
```

**Expected. Grafana can reach Loki (same path log panels use):**

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  wget -qO- --timeout=5 http://loki:3100/ready
```

```text
ready
```

**Expected. Grafana UI reachable:**

```bash
curl -sI http://grafana.local | head -n 1
```

```text
HTTP/1.1 302 Found
```

Log in: **http://grafana.local:** `admin` / `admin123`

> Empty panels right after install are **normal**. You have not generated events yet. Continue to §7.2–§7.4.

If Helm fails: wait 30s, then `FORCE=1 bash stages/stage-7-observability/scripts/install-observability.sh`. See [troubleshooting.md. Stage 7](troubleshooting.md#stage-7--observability-grafana--prometheus--loki).

**✋ Hands-on checkpoint: the whole stack is healthy, especially Loki**

This is where single-node runs die: Loki crash-loops and the dashboard ConfigMaps never land, but Grafana looks fine, so you waste an hour on "empty dashboards."

```bash
kubectl get pods -n monitoring
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki \
  -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}{"\n"}'
kubectl get configmap -n monitoring -l clearledger_dashboard=1 --no-headers | wc -l
```

Expected: all monitoring pods `Running`; Loki restart count `0` (or low and **stable**, not climbing); the ConfigMap count is `6`, your six dashboards. If Loki restarts keep climbing or the count is `0`, stop here: opening Grafana now only shows empty panels.

If you skip this, you spend the rest of Stage 7 debugging "why are my dashboards empty" when the real failure was Loki crash-looping at install.

---

### 7.2 — Verify Prometheus, Loki, and Grafana (before opening dashboards)

Run these three checks so you know **which layer** is broken if a panel is empty.

#### Check 1 — Prometheus has Kyverno metrics

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  wget -qO- 'http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/query?query=kyverno_admission_requests_total' 2>/dev/null \
  | head -c 400
```

(Prometheus runs as a StatefulSet pod, not a Deployment. This query goes through Grafana to the Prometheus Service.)

**Expected:** JSON with `"status":"success"` and a `"metric"` block (values may be `0` until you trigger a violation in §7.4).

If you see `"status":"success"` but `"result":[]`, Prometheus is up but Kyverno has not recorded admissions yet, that is fine before the lab.

#### Check 2 — Loki has Falco logs

```bash
kubectl exec -n monitoring loki-0 -- wget -qO- \
  'http://127.0.0.1:3100/loki/api/v1/labels' 2>/dev/null | head -c 300
```

**Expected:** JSON listing labels such as `"namespace"` (and after Falco events, you will see `"falco"` in label values).

Quick log search (may return empty lines until §7.4 Exercise B):

```bash
kubectl exec -n monitoring loki-0 -- wget -qO- \
  'http://127.0.0.1:3100/loki/api/v1/query?query=%7Bnamespace%3D%22falco%22%7D&limit=3' 2>/dev/null \
  | head -c 500
```

**Expected:** `"status":"success"`. `"result":[]` means no Falco lines in Loki yet, not a broken Loki.

#### Check 3 — Grafana imported ClearLedger dashboards

```bash
curl -s -u admin:admin123 'http://grafana.local/api/search?tag=clearledger' | jq -r '.[].title'
```

**Expected: six titles:**

```text
ClearLedger - Compliance Posture
ClearLedger - DORA Metrics
ClearLedger - Kubernetes Audit Log Analysis
ClearLedger - Kyverno Policy Violations
ClearLedger - Security Event Timeline
ClearLedger - Service Health + Auth Security
```

Or in the UI: **Dashboards** → filter tag **`clearledger`** → you should see exactly these six (no missing names).

---

### 7.3 — Your first 10 minutes in Grafana

> **Rule for all of Stage 7:** an empty panel means "no events yet in this time range", not "broken." You create the events in §7.4.

**What you are doing here:** logging in and clicking around so Grafana feels familiar. You are **not** proving anything yet, that is **§7.4**.

#### Step 1 — open Grafana

Go to **http://grafana.local** and log in: `admin` / `admin123`.

#### Step 2 — set the time range

> **Time-range rule for all of Stage 7:** top-right corner → time picker → **Last 15 minutes**. Keep this on every dashboard. Wide ranges (Last 24 hours) overload Loki on a single-node VM. Individual exercises below note any deviation (Exercise B uses **Last 1 hour**).

#### Step 3 — open dashboards one at a time

Open **one** link, look around, then close it or move to the next. Do not open all six in separate tabs at once. Loki can struggle on a single-node lab VM.

1. [Kyverno Policy Violations](http://grafana.local/d/clearledger-kyverno-violations): policy blocks from Stage 4.
2. [Security Event Timeline](http://grafana.local/d/clearledger-security-events): Falco alerts from Stage 6. You may see old `postgres` noise in the log table.
3. [Service Health + Auth](http://grafana.local/d/clearledger-service-health): app traffic and login attempts.
4. [Compliance Posture](http://grafana.local/d/clearledger-compliance): summary view for auditors. Skim it; come back after §7.4.
5. [Audit Log Analysis](http://grafana.local/d/clearledger-audit-logs): empty on MicroK8s by design (audit pipeline not enabled by default).
6. [DORA Metrics](http://grafana.local/d/clearledger-dora-metrics): deploy-frequency charts. Needs multiple CI runs to accumulate data; may show blank on first look. Optional.

Use the links above (short URLs). Avoid old bookmarked URLs with long random slugs. They can show `not correct url` in the browser.

**Alternative:** **Dashboards** (left menu) → search tag **`clearledger`** → you should see the same six titles from Check 3 in §7.2.

#### Step 4 — how to read what you see (quick)

Grafana panels pull data from two places:

- **Prometheus** — numbers over time (Kyverno violation counts, request rates).
- **Loki** — log lines (Falco JSON alerts, auth-service log messages).

A **big number** panel asks: did this count go above zero? A **line chart** asks: was there a spike after I ran something? A **logs** panel shows the actual text: rule names, `CRITICAL`, `Failed login attempt`.

If **only** log panels say `connection refused`, Loki may be down: re-check §7.1. If number panels work but log panels fail, that points to Loki specifically.

#### Step 5 — move on

Open dashboards 1–3, then continue to **§7.4**, that is where you run commands in the terminal and watch the panels update.

---

### 7.4 — Hands-on lab: terminal → dashboard proof

This is the core learning section. Each exercise: run the command, wait, then confirm in Grafana.

**Timing:** wait **30–90 seconds** after each command for Prometheus scrape and Loki ingestion.

**Two ways to do this lab**

**Option 1 — follow the exercises below (recommended for learning)**

Run each command yourself, then check Grafana. That is Exercise A, B, and C.

**Option 2 — use the guided script**

The script runs the same steps and pauses so you can check Grafana between them:

```bash
bash stages/stage-7-observability/scripts/generate-dashboard-data.sh
```

Or:

```bash
make demo-7
```

Both commands do the same thing. The script will say things like “Press Enter after you checked the Kyverno dashboard.” Switch to Grafana, look at the panel, then come back and press Enter.

**Want it to run without pauses?** (faster, less hand-holding)

```bash
SKIP_PROMPT=1 make demo-7
```

Use Option 1 if you want to understand each step. Use Option 2 if you want a walkthrough. Use `SKIP_PROMPT=1` if you just want the data generated quickly.

---

#### Exercise A — Kyverno block → Prometheus → Kyverno dashboard

**Terminal**: apply a pod that violates Stage 4 policy (runs as root):

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: stage7-kyverno-lab
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
YAML
```

**How to know it worked**

You are testing whether Kyverno **blocks** a deliberately bad pod. Success means the pod **never gets created**.

**Pass. You should see:**

- The terminal prints **`Error from server`** and **`denied the request`**
- The exact policy names in the error do not matter. Your output might list one rule or several (`disallow-root-containers`, `require-resource-limits`, `drop-all-capabilities`, …). More lines just means more rules failed, that is still a pass.
- The pod name never shows up in the cluster:

```bash
kubectl get pods -n clearledger | grep stage7-kyverno-lab
```

**Expected:** no output.

**Fail: stop and fix Stage 4 first:**

- The command ends quietly with **`created`** (no error)
- `kubectl get pods -n clearledger` shows **`stage7-kyverno-lab`**

That means Kyverno let a root pod through. Run `make check-4` before continuing Stage 7.

**Example of a passing terminal** (yours may list more policies):

```text
Error from server: error when creating "STDIN": admission webhook "validate.kyverno.svc" denied the request:
policy disallow-root-containers/validate-run-as-non-root fail: Running as root is not allowed
```

**Confirm Prometheus saw it** (optional but useful if Grafana is empty):

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  wget -qO- 'http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/query?query=kyverno_admission_requests_total{request_allowed="false"}' 2>/dev/null \
  | grep -o '"value":\[[^]]*\]' | head -3
```

**Expected:** a `"value"` entry with a recent Unix timestamp and a number **greater than 0** (for example `"value":[..., "1"]`). If you see this, Kyverno and Prometheus are working even when Grafana panels say **No data**.

**Grafana**: open [Kyverno Policy Violations](http://grafana.local/d/clearledger-kyverno-violations?from=now-15m&to=now). Time range: **Last 15 minutes** (top-right).

**What you are proving:** the terminal denial showed up in Grafana. You do not need every panel to light up. You need **one clear sign** that Kyverno blocks are being counted.

**Step 1 — quick sanity check (top row, left to right)**

1. **Policy Violations (time range)** — big number. **Pass:** shows **1** or more. **Fail:** says **No data**.
2. **Violations (time range)** — same idea, second counter. **Pass:** **1** or more.
3. **Active Kyverno Rules** — usually **18**. If this number shows up, Grafana can talk to Prometheus. That is good even when the first two panels are still empty.

**Step 2 — if the top two numbers work, skim the charts**

- **Violation Rate by Resource Kind** (middle chart) — look for a bump labeled **Pod** around the time you ran `kubectl apply`.
- **Top Blocked Resource Types** (bottom-left table) — look for a **Pod** row.
- **Violations by Namespace (trend)** (bottom-right chart) — look for a bump for **clearledger**.

Charts can lag. A big number **> 0** in Step 1 is enough to move on. The charts are bonus proof for §7.6 screenshots.

**If the top two panels say "No data" but the terminal denial worked**

This is common. Those panels count **new** denials during the time range, not the total ever recorded. One denial sometimes lands in Prometheus before Grafana's counter moves.

Try this:

1. Run the same `kubectl apply` command **again** (denied again — that is expected).
2. Wait **60 seconds**.
3. Click **Refresh** (circular arrow, top-right).

After a second denial you should see **2** in the top stat panels. Screenshot that for §7.6.

**Still empty? Use Explore as backup proof**

1. Grafana left menu → **Explore**
2. Datasource: **Prometheus**
3. Paste: `sum(kyverno_admission_requests_total{request_allowed="false"})`
4. Click **Run query**

**Pass:** the result is **1** or **2**.

A screenshot of the terminal denial plus Explore showing a number **> 0** counts as portfolio proof even if the dashboard stats stay slow.

---

#### Exercise B — Falco shell → Loki → Security Event Timeline

**What you are doing (same idea as Exercise A):**

- **Exercise A:** you did something bad → Kyverno blocked it → Grafana **Kyverno** dashboard updated.
- **Exercise B:** you do something suspicious **inside** a running pod → Falco detects it → Grafana **Security Event Timeline** updates.

You already did this in **Stage 6** (`make demo-6`). Here you do it again and prove the alert shows up in **Grafana**, not only in `http://falco.local`.

**The story in one line:** pretend you are an attacker who got shell access inside `auth-service`: Falco should scream, and the scream should appear on the timeline dashboard.

---

**Step 1: trigger the alert (terminal)**

You are pretending an attacker got into `auth-service` and ran a quick command (`id`) to see who they are logged in as. That is suspicious. Falco is supposed to catch it.

The block below is **three commands in order**. Copy-paste the whole block:

```bash
AUTH_POD=$(kubectl get pod -n clearledger -l app=auth-service \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "Using pod: $AUTH_POD"
kubectl exec -n clearledger "$AUTH_POD" -c auth-service -- /bin/sh -c 'id && exit'
```

**What each line does**

1. **Line 1** — finds the name of a running `auth-service` pod and saves it in `AUTH_POD`.
2. **Line 2** — prints that name so you can see it worked (not empty).
3. **Line 3** — runs `/bin/sh -c 'id && exit'` **inside** that pod. This is the fake “attack.” Falco watches for shells like this.

**Pass — you only need these two lines in the output:**

```text
Using pod: auth-service-77b7d9cd99-xxxxx
uid=1000 gid=1000 groups=1000
```

- First line: a real pod name (not blank).
- Second line: the `id` command ran inside the container.

That is Step 1 done. The pod is still running. You did not break anything.

**Fail — stop and fix before Step 2:**

- `error: Internal error` or `container not found`
- `Using pod:` with nothing after it

Run `kubectl get pods -n clearledger -l app=auth-service` and retry when one pod shows **Running**.

---

**Step 2. Confirm Falco saw it (terminal, right away)**

The Falco log is one long JSON line. Do not try to read the whole thing. Run:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i 'Shell spawned'
```

**Pass. You should see one short phrase somewhere in the line:**

```text
Shell spawned in ClearLedger container ... pod=auth-service-... cmd=sh -c id && exit
```

Or the rule name:

```text
"rule":"Shell Spawned in ClearLedger Container"
```

**That one grep hit means Exercise B worked in the terminal.** Screenshot this line for your portfolio.

**Ignore:**

- `Defaulted container "falco" out of: ...`: normal kubectl noise
- Lines about `postgres-0` and `/etc/passwd`: background noise from Stage 6, not your test
- The rest of the JSON (`output_fields`, `k8smeta`, and so on). You do not need to parse it

**If grep prints nothing:** run Step 1 again, wait 5 seconds, then re-run the grep.

---

**Step 3. Confirm Loki stored it (optional check — wait ~60 seconds first)**

**The story so far:**

- **Step 1** — you triggered the alert inside `auth-service`
- **Step 2** — Falco wrote the alert to its own logs ✓

**Step 3 asks:** did that log line make it into **Loki** (Grafana's log database)?

Falco does not talk to Grafana directly. **Promtail** copies Falco's logs into Loki. That copy takes **60–90 seconds**. Wait after Step 1, then run this check.

**What this command does (in plain English):**

"Search Loki for Falco logs that contain `Shell spawned`, then show only lines that also mention `auth-service`."

```bash
kubectl exec -n monitoring loki-0 -- wget -qO- \
  'http://127.0.0.1:3100/loki/api/v1/query?query=%7Bnamespace%3D%22falco%22%2Ccontainer%3D%22falco%22%7D%20%7C%3D%20%22Shell%20spawned%22&limit=3' 2>/dev/null \
  | grep -i 'auth-service'
```

**Pass:** you see a line with both **`auth-service`** and **`Shell spawned`**. That means Loki has your alert and Grafana can show it.

**Fail (misleading pass):** you grep for `ClearLedger` alone and get a hit from **`postgres-0`** reading `/etc/passwd`. That is background noise from Stage 6, not your shell test. Always look for **`auth-service`**.

**Empty output?** That is OK. If Step 2 passed, **continue to Step 4**. Promtail may still be catching up, or the JSON is too long for this quick grep. Grafana often shows the alert even when this command prints nothing.

---

**Step 4: open Grafana**

Open [Security Event Timeline](http://grafana.local/d/clearledger-security-events?from=now-1h&to=now).

**Yes — this is the right dashboard.** The title at the top should say **ClearLedger - Security Event Timeline**.

**Before you look at panels:**

1. Time range → **Last 1 hour** (top-right)
2. Auto-refresh → **Off**
3. Re-run Step 1 if your shell command was more than a few minutes ago
4. Wait **90 seconds**, then click **Refresh**

**What you will probably see (this is normal)**

- **CRITICAL Alerts (1h)** — a big number like **1.08 K**. That is mostly **`postgres-0`** reading `/etc/passwd` on a loop (Stage 6 background noise). It does **not** mean you failed.
- **Alerts by Rule Name** (pie chart) — dominated by **Sensitive File Read in ClearLedger**. Also normal.
- **Recent CRITICAL / WARNING Events** — lots of postgres rows. Your shell alert is in there, but buried.

The top timeline (**Falco Alerts by Priority - Timeline**) may say **No data**. That is a known quirk. Do not panic — use the log panel and browser search instead.

**How to find *your* alert (on this dashboard)**

1. Stay on **ClearLedger - Security Event Timeline** — not Explore, not Tempo.
2. Click inside **Recent CRITICAL / WARNING Events** (the log list on the right).
3. Press **Cmd+F** (Mac) or **Ctrl+F** (Windows/Linux).
4. Search for **`auth-service`** or **`Shell spawned`**.

If the search finds a row mentioning your pod and **Shell spawned**, screenshot it.

**Wrong place (common mistake):** Grafana **Explore** with datasource **Tempo** showing `ledger-service` traces. That is **Stage 7.5** (OpenTelemetry), not Exercise B. Tempo shows request traces, not Falco security alerts.

**Pass for Exercise B (pick one):**

1. **Best:** Step 2 terminal grep shows `Shell spawned` **and** the **Security Event Timeline** log search finds **`auth-service`** / **`Shell spawned`** — screenshot both.
2. **Also fine:** Step 2 grep screenshot **plus** the **Security Event Timeline** dashboard with **CRITICAL Alerts (1h)** showing a number (proves Falco → Loki → Grafana works, even if your shell row is buried in postgres noise).
3. **Fallback (only if the dashboard search fails):** Step 2 grep **plus** Grafana **Explore** with datasource **Loki** (not Tempo):
   - Left menu → **Explore**
   - Top-left datasource dropdown → choose **Loki**
   - Query: `{namespace="falco", container="falco"} |= "Shell spawned"`
   - Click **Run query**
   - Look for a line with **`auth-service`**

Screenshot for §7.6.

---

#### Exercise C — Failed login, Loki, and Service Health

**The story:** someone is guessing passwords on your login API. You send ten bad login attempts from the terminal. `auth-service` writes `Failed login attempt` to its logs. Grafana **Service Health + Auth Security** should show the count go up.

Same pattern as A and B: **terminal action, then logs, then dashboard**.

---

**Step 1: send bad login attempts (terminal)**

Copy-paste the whole block:

```bash
for i in $(seq 1 10); do
  curl -s http://clearledger.local/auth/health >/dev/null
  curl -s -X POST http://clearledger.local/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"lab-attacker@evil.com","password":"wrong"}' >/dev/null
done
echo "done"
```

**What it does:** hits `/auth/health` to keep the app warm, then posts a wrong password to `/auth/login` ten times.

**Pass:** the only output you need is:

```text
done
```

No output from the `curl` lines is normal.

**Fail:** `curl: (6) Could not resolve host` — run `bash scripts/setup-hosts.sh`. `curl: (7) Failed to connect` — check `kubectl get pods -n clearledger -l app=auth-service`.

---

**Step 2. Confirm auth-service logged it (terminal, right away)**

```bash
kubectl logs -n clearledger -l app=auth-service --tail=30 | grep -i 'Failed login' | tail -3
```

**Pass — you should see lines like:**

```text
Failed login attempt for lab-attacker@evil.com
```

One line is enough. Screenshot this for your portfolio.

**If grep prints nothing:** wait 10 seconds and run again. If still empty, check the auth pod is **Running**: `kubectl get pods -n clearledger -l app=auth-service`.

---

**Step 3: open Grafana (wait ~60 seconds after Step 1)**

Open [Service Health + Auth Security](http://grafana.local/d/clearledger-service-health?from=now-1h&to=now).

**Yes — this is the right dashboard.** The title should say **ClearLedger - Service Health + Auth Security**.

1. Time range: **Last 1 hour**
2. Auto-refresh: **Off**
3. Click **Refresh** once

**What to check (only these matter for Exercise C)**

1. **Failed Login Attempts (1h)** — big number. **Pass:** **> 0**. This is your main proof.
2. **Failed Login Log Stream** — log lines in the panel. **Pass:** lines with `Failed login attempt` or `lab-attacker@evil.com`. Use **Cmd+F** inside the panel if needed.

**Panels you can ignore if empty:**

- **Successful Logins** — fine at **0** (you only sent bad passwords)
- **Request Rate by Service** — may be empty until §7.5 metrics images; not required for Exercise C

**You pass Exercise C when you have two screenshots:**

**Screenshot 1 (required):** your Step 2 terminal output showing `Failed login attempt for lab-attacker@evil.com`. This proves the app logged the bad logins.

**Screenshot 2 (pick one of these):**

- **Option A:** the **Failed Login Attempts (1h)** panel showing a number greater than zero (for example **10**). This proves Grafana counted the failures.
- **Option B:** the **Failed Login Log Stream** panel showing a line with `lab-attacker@evil.com`. Use this if the big number panel is still empty but the log stream has your email.

You need Screenshot 1 **and** either Option A or Option B. That is enough for §7.6.

---

#### Exercise D — Compliance dashboard (the auditor summary)

**What you are doing:** open one dashboard that rolls up Exercises A, B, and C. This is the “show the auditor” view: admission control + runtime detection + application security in one screen.

**When:** only after you finished A, B, and C.

**Step 1: open the dashboard**

[Compliance Posture](http://grafana.local/d/clearledger-compliance?from=now-1h&to=now)

Set **Last 1 hour**, auto-refresh **Off**, click **Refresh**.

**Step 2. Check the top row stats**

| Stat on dashboard | Came from | Pass |
|-------------------|-----------|------|
| **Policy Violations** | Exercise A (Kyverno) | **> 0** |
| **Runtime Threats** | Exercise B (Falco) | **> 0** (postgres noise counts — that is OK) |
| **Failed Auth Attempts** | Exercise C (bad logins) | **> 0** |

All three do not need to be huge numbers. They just need to be **above zero** after your tests.

**If one stat is still 0:** re-run that exercise (A, B, or C), wait 90 seconds, refresh. Policy Violations may need a second Kyverno denial like Exercise A.

**This is screenshot #3 for §7.6**: the single frame that proves defense-in-depth.

---

**✋ Hands-on checkpoint — are you actually done with Stage 7?**

Installing Grafana is not the goal. **Detection** is: you triggered real events and can see them on dashboards.

**Optional terminal check (proves Grafana is wired up):**

```bash
curl -s -u admin:admin123 'http://grafana.local/api/search?tag=clearledger' | jq -r '.[].title'
curl -s -u admin:admin123 'http://grafana.local/api/datasources' | jq -r '.[].name'
```

**First command — you should see six dashboard names:**

- ClearLedger - Kyverno Policy Violations
- ClearLedger - Security Event Timeline
- ClearLedger - Service Health + Auth Security
- ClearLedger - Compliance Posture
- ClearLedger - Kubernetes Audit Log Analysis
- ClearLedger - DORA Metrics

**Second command — you should see at least:**

- Prometheus
- Loki

**What does NOT mean you are done**

`make check-7` only checks that monitoring pods are running. Green output there does **not** replace §7.4.

**What DOES mean you are done**

You ran Exercises A, B, and C in §7.4 and saved the §7.6 screenshots:

1. Kyverno denial (terminal + dashboard)
2. Falco shell alert (terminal + Security Event Timeline)
3. Failed logins (terminal + Service Health)
4. Compliance Posture summary (all three stats above zero)

If you have those four screenshots, Stage 7 is complete.

---

### 7.5 — Optional: fill in the Request Rate chart

> **Not required for Stage 7.** Exercises A–C and §7.6 screenshots do not need this section. Skip it if you are happy moving on.
>
> **Not the same as Stage 7.5 (OpenTelemetry/Tempo).** This subsection is only about the **Request Rate by Service** chart on the Service Health dashboard.

#### What this section is for

On **Service Health + Auth Security**, the **Failed Login** panels work from logs (Loki). The **Request Rate by Service** chart needs something different: app pods must expose a `/metrics` endpoint so **Prometheus** can scrape request counts.

The code is already in the repo (`app/*/prom_metrics.py`). Prometheus is already configured to scrape it (`clearledger-podmonitor.yaml`). The usual problem: your cluster is still running **older images** from before that code was in your build.

#### Step 1 — check if you already have metrics (30 seconds)

Run this first. If it passes, **skip the rest of §7.5**.

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  wget -qO- 'http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/query?query=http_requests_total' 2>/dev/null \
  | grep -o '"__name__":"http_requests_total"' | head -1
```

**Pass:** prints `"__name__":"http_requests_total"`. **If you get output, you are done with §7.5. Skip the rest of it.** Open Service Health, refresh, and the **Request Rate by Service** chart should already have lines.

**No output:** continue to Step 2.

#### Step 2 — deploy images that expose `/metrics`

Pick **one** path.

**Path A — GitOps (if you have been using CI/CD since Stage 1–2)**

1. Push a commit to `main` on your app repo.
2. Wait for CI to build new images and update `clearledger-infra`.
3. Wait for ArgoCD to show **Synced** and **Healthy** on the clearledger app.
4. Go to Step 3.

**Path B — lab shortcut (faster, local only)**

```bash
export DOCKER_USERNAME=your-dockerhub-user
bash stages/stage-7-observability/scripts/build-metrics-images.sh
```

This builds, pushes, and rolls out metrics-enabled images for all three services.

**Heads-up:** ArgoCD self-heal may revert these image tags within a few minutes if `clearledger-infra` still points at older tags. That is fine for a quick lab demo. For a lasting fix, use Path A or update the infra repo (see §2 rollback notes).

#### Step 3 — verify metrics landed (~60 seconds after rollout)

```bash
kubectl exec -n clearledger deploy/auth-service -c auth-service -- \
  wget -qO- http://127.0.0.1:8000/metrics 2>/dev/null | head -5
```

**Pass:** lines starting with `# HELP` or `http_requests_total`.

Then confirm Prometheus sees them:

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  wget -qO- 'http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/query?query=http_requests_total' 2>/dev/null \
  | grep -o '"__name__":"http_requests_total"' | head -1
```

**Pass:** `"__name__":"http_requests_total"`

Generate a little traffic (re-run the Exercise C curl loop or hit `http://clearledger.local/auth/health` a few times), wait **60 seconds**, then open **Service Health + Auth Security** and refresh. **Request Rate by Service** should show lines for `auth-service`, `ledger-service`, or `notification-service`.

#### When to stop

- **Request Rate still empty but Failed Login panels work?** You are done with Stage 7. Request Rate is a nice-to-have.
- **Prometheus query passes but chart empty?** Widen time range to **Last 1 hour**, generate traffic, wait 60s, refresh.

---

### 7.6 — Wrap up Stage 7 (screenshots + done check)

You are almost done. This section is just: save proof, then move on.

**Are you actually finished?**

Opening Grafana and seeing six dashboards is not enough. `make check-7` passing is not enough either — that only proves pods are running.

You are done when **you** ran §7.4, waited for the panels to update, and saved **three screenshots** from **your** cluster.

If the panels are empty or only show old postgres noise, go back to §7.4 first.

**Before each screenshot:** set time range to **Last 15 minutes** (or **Last 1 hour** for Exercise B). Include the time picker and panel titles in the frame.

**Screenshot 1 — Falco alert (Exercise B)**

Open [Security Event Timeline](http://grafana.local/d/clearledger-security-events).

Capture **Recent CRITICAL / WARNING Events** with a row that mentions **`Shell spawned`** or **`auth-service`**. If postgres rows bury it, use Cmd+F inside the log panel — that still counts.

**Screenshot 2 — Kyverno denial (Exercise A)**

Open [Kyverno Policy Violations](http://grafana.local/d/clearledger-kyverno-violations).

Capture **Policy Violations (time range)** or **Violations (time range)** showing a number of **1 or more**.

**Screenshot 3 — Compliance summary (Exercise D)**

Open [Compliance Posture](http://grafana.local/d/clearledger-compliance).

Capture the top row with all three stats above zero: **Policy Violations**, **Runtime Threats**, and **Failed Auth Attempts**.

**Screenshot 4 (optional) — Failed logins (Exercise C)**

Open [Service Health + Auth Security](http://grafana.local/d/clearledger-service-health).

Capture **Failed Login Attempts (1h)** above zero, or **Failed Login Log Stream** showing `lab-attacker@evil.com`.

Save files somewhere sensible, like `docs/evidence/stage-7-screenshot-1-falco.png`. Name them so you know what each proves.

**Final check:** run `make check-7` (§7.7), save your VM, and you can claim Stage 7.

---

### 7.7 — Verify

```bash
make check-7
```

**Expected:**

```text
▶ Stage 7 — Observability (Grafana + Prometheus + Loki)
  ✓ Prometheus is running
  ✓ Grafana reachable (http://grafana.local or in-cluster health OK)
  ✓ Loki pod is running (0 restarts)
  ✓ Loki reachable from Grafana (http://loki:3100/ready)
  ✓ ClearLedger alerting rules exist
  ✓ ClearLedger dashboards imported (6 found)
```

Warnings about Loki restarts or missing dashboards: fix with §7.1 before claiming Stage 7 complete. **Save your VM** after §7.6 and `make check-7`. See the block at the end of Stage 7 below.

---

### 7.8 — What broke (lab notes + interview talking points)

**The stack in one sentence:** Prometheus stores **numbers** (metrics), Loki stores **log lines**, Grafana **displays** both. Nothing appears until something actually happens in the cluster.

#### What tripped you up in the lab

1. **Empty dashboards right after install**
   Normal. Grafana does not create events. You trigger them in §7.4 (Kyverno denial, Falco shell, failed logins).

2. **Loki slow or refresh stuck on “Cancel”**
   Falco logs are huge. **Last 24 hours** overloads a small cluster. Use **Last 1 hour**, one dashboard at a time, wait ~10 seconds.

3. **`make check-7` passed but panels still empty** *(lab checklist only, not an interview topic)*
   The health check confirms Prometheus/Loki/Grafana pods are up. It does **not** mean events exist. You still need §7.4 + §7.6 before you snapshot and move on.

#### If someone asks about this in an interview

**Empty dashboards?**
Grafana only shows what already happened. No event in the time range means an empty panel — that is normal until you trigger something.

**Loki slow on a small cluster?**
Falco logs are huge. We kept time ranges short (15 minutes, not 24 hours) and opened one dashboard at a time. Same trade-off you would make in prod on limited hardware.

**How did you prove it worked?**
I ran the attacks myself: denied a bad pod, spawned a shell in a running container, sent failed logins. Then I checked Grafana and screenshot the matching panels. Terminal action first, dashboard proof second.

**Short version you can say out loud:**

> "I connected Kyverno and Falco into Grafana. To prove it, I triggered a policy block and a runtime alert, then showed both on security dashboards. On a single-node lab, Loki got slow with wide time ranges, so we kept queries tight."

Pipeline problems from earlier stages (Trivy, Kyverno, image tags, and so on) are in `docs/troubleshooting.md` — not something you need to rehearse for Stage 7.

---

### 7.9 — If panels look wrong after a repo update

Re-apply dashboards, then generate **real** events (§7.4, not fake data):

```bash
bash stages/stage-7-observability/scripts/install-observability.sh
# Then run Exercises A–C from §7.4 (Kyverno denial, Falco shell, failed logins)
```

Open Grafana at **Last 1 hour**, wait ~30–60s after each exercise, refresh once. The §7.4 exercises cover expected appearance for each dashboard.

---

### What You Learned in Stage 7

- **Prometheus** proves countable security events (Kyverno denials, HTTP rates)
- **Loki** proves forensic detail (Falco JSON, auth log lines)
- **Grafana** is the narrative layer, not a second install step after the lab
- You can trace: **terminal action → backend signal → panel update**
- ServiceMonitors / PodMonitors are what connect Stages 4–6 to charts
- Empty dashboards mean “no events yet” or “wrong time range”, not “broken security”
- Compliance posture is how you answer an auditor in **one screen**
- Network policies must explicitly allow the `monitoring` namespace to reach app pods on port 8000, otherwise PodMonitor scrapes silently fail with `context deadline exceeded`
- Kubernetes Audit Log dashboard is empty on MicroK8s by design: the API server audit pipeline (audit-policy → file → Promtail → Loki) is not enabled by default
- Request Rate requires the full chain: app image with `/metrics`, PodMonitor, and network policy: any one missing means the panel stays empty

**What you can now put on your CV / say in an interview:**

> Built security observability with Prometheus, Loki, and Grafana (dashboards correlating Kyverno violations, Falco alerts, and DORA metrics) and can prove a security event end-to-end from terminal to dashboard.

#### Stage 7 done checklist

- `make check-7` → 6/6 ✓ (Stage 6.5 Litmus failure is expected: scaled down for memory)
- `http://grafana.local/d/clearledger-kyverno-violations`. Violations stat > 0
- `http://grafana.local/d/clearledger-security-events`. CRITICAL Falco alert visible
- `http://grafana.local/d/clearledger-compliance`. Policy Violations + Runtime Threats + Failed Auth Attempts all > 0
- `http://grafana.local/d/clearledger-service-health`. Failed Login Attempts > 0; Request Rate > 0 only if you did §7.5
- Portfolio screenshots 1–3 saved

`make snapshot STAGE=7 && make snapshots`. Confirm `clearledger.stage7`. **Don't skip this**. Stage 7 is heavy; disk pressure is common. See [How to Save Your Progress](#heading-how-to-save-your-progress).

> **Want help explaining what you just built in an interview?** [*DevOps Interview Decoder*](https://osomudeya.gumroad.com/l/pcpbks) covers what interviewers are really testing and how to talk through your decisions with confidence.

After a Mac reboot or sleep, auth/ledger pods may show **Unknown** or **Init:0/1** even though the cluster is up (see [troubleshooting.md) Mac reboot](troubleshooting.md#mac-reboot-or-sleep--authledger-pods-sick-vault).

---

## Stage 7.5 — OpenTelemetry (Optional)

**You can skip this whole stage.** Stage 7 (metrics + logs) is enough to finish the homelab and move to Stage 8.

Only do Stage 7.5 if you want distributed traces for your portfolio or interviews, and your VM has spare RAM (about **1.5 Gi free**).

### What you are adding

Stage 7 answers: *did something happen?* (Kyverno blocked a pod, Falco saw a shell, login failed.)

Traces answer: *what steps ran on this one request, and how long did each take?*

- **Metrics** — how many requests, how many errors
- **Logs** — what the app printed in its log file (errors, warnings, login failures)
- **Traces** — ledger-service called auth-service (12ms), then Postgres (8ms)

In this stage you send one real transaction, then open that request in Grafana Explore (Tempo). You will see each step listed with its timing: ledger-service, auth-service, postgres.

### Before you start

1. Finish Stage 7: §7.4 exercises done, §7.6 screenshots saved, `SKIP_CHAOS_CHECK=1 make check-7` passes.
2. Check VM memory: `multipass exec clearledger -- free -h` — want about **1.5 Gi** free.
3. If you ran Stage 6.5 Litmus, scale it down first (§7.0).

**You are done when:** you see the full request trace in Grafana Explore (Tempo datasource) and `make check-75` passes. Then `make snapshot STAGE=75`.

### Ignore this warning in app logs

Since Stage 7 you may see:

```
WARNING: Transient error StatusCode.UNAVAILABLE encountered while exporting traces
```

That is harmless. The apps are already set up to send trace data, but the receiver is not installed until §7.5.3. Your apps still work fine — the trace data just gets thrown away. Installing the collector in §7.5.3 makes the warning go away.

### How tracing is wired

1. **Your apps** send trace data when a request runs
2. **OTel Collector** receives it (port 4317) and passes it along
3. **Grafana Tempo** stores it
4. **Grafana Explore** (Tempo selected) is where you look at one request step by step

Apps talk to the collector only, not to Tempo directly. That way you can change where traces are stored later without rebuilding the apps.

---

### 7.5.1 — Check memory and load

Tempo needs ~300MB. Confirm headroom before installing:

```bash
multipass exec clearledger -- free -h    # want ~1.5Gi available
multipass exec clearledger -- uptime      # load should be reasonable for your CPU count
SKIP_CHAOS_CHECK=1 bash scripts/health-check.sh 7
```

If Litmus is still running from Stage 6.5, scale it down first (§7.0):

```bash
kubectl get pods -n litmus --field-selector=status.phase=Running
# Expected: no resources found
```

---

### 7.5.2 — Install Grafana Tempo

Tempo is the trace storage backend. Install it into the `monitoring` namespace next to Prometheus and Loki:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install tempo grafana/tempo \
  --namespace monitoring \
  --set tempo.storage.trace.backend=local \
  --set tempo.storage.trace.local.path=/var/tempo \
  --set persistence.enabled=true \
  --set persistence.size=5Gi \
  --wait
```

**Verify Tempo is running:**

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
# Expected: tempo-0   1/1   Running
```

```bash
kubectl exec -n monitoring tempo-0 -- wget -qO- http://localhost:3200/ready
# Expected: ready
```

---

### 7.5.3 — Deploy OTel Collector and wire Grafana

This applies the OTel Collector (receives spans from app pods) and registers Tempo as a Grafana datasource automatically via the sidecar:

```bash
kubectl apply -f stages/stage-7.5-opentelemetry/infra/otel/otel-collector.yaml
kubectl apply -f stages/stage-7.5-opentelemetry/infra/otel/grafana-datasource-tempo.yaml
```

**Verify the collector is running:**

```bash
kubectl get pods -n monitoring -l app=otel-collector
# Expected: otel-collector-xxxxx   1/1   Running
```

**Verify the collector started (not trace receipt yet):**

Apps **push** spans to the collector over OTLP: the collector does not scrape pods. At this step you are only confirming it is listening.

```bash
kubectl logs -n monitoring deploy/otel-collector --tail=15
# Expected:
#   Starting GRPC server ... endpoint: 0.0.0.0:4317
#   Starting HTTP server ... endpoint: 0.0.0.0:4318
#   Everything is ready. Begin running and processing data.
# No crash loops or repeated errors.
```

Proof that traces are actually flowing comes later: after you generate traffic in §7.5.6, check collector logs for span export lines from the `debug` exporter, then confirm the trace in Grafana Tempo (§7.5.7).

---

### 7.5.4 — Enable Prometheus remote write receiver

The OTel Collector also forwards OTel metrics to Prometheus via remote write. Prometheus needs to accept them:

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f stages/stage-7-observability/infra/helm/kube-prometheus-stack-values.yaml \
  --wait
```

This applies the `enableRemoteWriteReceiver: true` setting added to the Helm values in Stage 7.5. Wait for Prometheus to restart (about 60 seconds).

---

### 7.5.5 — Verify app pods connect to the collector

The deployments in `clearledger-infra` already have `OTEL_EXPORTER_OTLP_ENDPOINT` set. Once the collector is running, the pods auto-connect. Confirm the OTEL warnings are gone:

```bash
kubectl logs -n clearledger deploy/ledger-service -c ledger-service --tail=20 2>/dev/null \
  | grep -v "opentelemetry\|otlp\|Transient" | tail -10
# Expected: only INFO request logs, no WARNING: Transient error
```

If warnings persist, the network policy may not have port 4317 egress. Apply the latest policies:

```bash
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
```

---

### 7.5.6 — Generate a trace

Now create a transaction and watch it flow through the system:

```bash
# Step 1: register (skip if already registered)
curl -s -X POST http://clearledger.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"trace-demo@clearledger.io","password":"TracePass123"}' | python3 -m json.tool

# Step 2: login and grab the token
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"trace-demo@clearledger.io","password":"TracePass123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "Token acquired: ${TOKEN:0:20}..."

# Step 3: create a transaction (this is the request you will trace)
curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount": 5000, "direction": "credit"}' | python3 -m json.tool
```

**Verify the collector received spans:**

```bash
kubectl logs -n monitoring deploy/otel-collector --tail=30 \
  | grep -iE "Traces|spans|ResourceSpans" || echo "No span lines yet — see §7.5.5 (OTEL env / netpol)"
# Expected after a successful transaction: debug exporter lines mentioning exported traces/spans
```

---

### 7.5.7 — View the trace in Grafana

Open **http://grafana.local** → left sidebar **Explore** (compass icon).

#### Step 1 — Select Tempo and open Search

At the top of the query pane:

1. Datasource dropdown (orange **T** logo) → **Tempo**
2. Query row labeled **A (Tempo)** → three tabs: **Search** | TraceQL | Service Graph
3. Click **Search**. This shows dropdown filters. **TraceQL** is a text box only; if you land there with nothing typed you get `0 series returned`.

#### Step 2 — Filter by service

In the **Search** tab:

- **Service Name** → type or select `ledger-service`
- Leave Span Name, Status, Duration, and Tags empty for now
- Grafana shows the query it will run: `{resource.service.name="ledger-service"}`

Set the time range (top-right clock icon) to **Last 15 minutes** so your §7.5.6 transaction is included.

#### Step 3 — Run the query

Grafana Explore has **no “Run query” button**: results appear automatically after selecting a service. If the table stays empty, use the **blue refresh button** top-right of the pane.

#### Step 4 — Open the trace detail

Below the query editor, find **Table - Traces**. You should see at least one row like:

| Column | Example |
|--------|---------|
| Trace ID | `5730edf3…` (blue link) |
| Start time | when you ran the `curl` |
| Service | `ledger-service` |
| Name | `POST /transactions` |
| Duration | ~200ms (yours may differ) |

**Click the Trace ID link.** The right panel opens the trace detail view.

#### What the trace detail view shows

Header: **`ledger-service: POST /transactions`**

- **Trace ID** — unique ID for this request
- **Duration** — total end-to-end time
- **Services** — `2` (`ledger-service` and `auth-service` for a normal transaction)

One request, step by step:

```mermaid
sequenceDiagram
    participant You as You (curl)
    participant Ledger as ledger-service
    participant Auth as auth-service
    participant DB as postgres
    participant Redis as redis

    You->>Ledger: POST /transactions
    Ledger->>Auth: GET /verify — check JWT
    Auth-->>Ledger: user OK
    Ledger->>DB: INSERT transaction
    DB-->>Ledger: saved
    opt amount at or above notification threshold
        Ledger->>Redis: PUBLISH ledger-events
    end
    Ledger-->>You: 201 Created
```

**Reading the trace detail screen**

Each row is one **step** in the request (Grafana calls it a *span*). The colored bar on the right shows **how long that step took** — that is the *span bar*. Longer bar = more time spent on that step.

Click a row or its bar to open the details panel on the right. You will see two kinds of metadata:

- **Span attributes** — what happened in *this step*. Examples: HTTP method (`POST`, `GET`), status code (`200`), or SQL text on a database step. In your trace you might see `asgi.event.type: http.request` on the FastAPI receive step.
- **Resource attributes** — *where* the step ran. Examples: `service.name: ledger-service`, `k8s.cluster.name: clearledger`, `deployment.environment: production`.

Quick mental model: span attributes = what the step did. Resource attributes = which service produced it.

**Connecting traces to logs:** once you have a step selected, the **Logs** tab will take you straight to the matching Loki log lines for that pod at the same moment in time.

**Screenshot this trace detail view**: portfolio proof for Stage 7.5.

#### TraceQL alternative

Prefer the text box? Switch to the **TraceQL** tab, and paste:

```traceql
{ resource.service.name = "ledger-service" }
```

#### If the table is empty

**TraceQL says `0 series returned`**
Use the **Search** tab instead, or paste the TraceQL query from above into the TraceQL tab.

**Search tab has no rows**
Widen the time range to **Last 15 minutes**, re-run the transaction curl from §7.5.6, wait a few seconds, and refresh.

**Grafana cannot connect to Tempo**
The datasource URL needs port **3200**. Re-apply the datasource and restart Grafana:

```bash
kubectl apply -f stages/stage-7.5-opentelemetry/infra/otel/grafana-datasource-tempo.yaml
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

**Collector logs show no trace data**
Work through §7.5.5 — usually the OTEL environment variables or network policy blocking port 4317.

---

### 7.5.7b — What am I actually looking at?

You ran **one** curl command in §7.5.6. Grafana shows every place that single request traveled.

Think of it like tracking a package:

1. **You** sent `POST /transactions` to **ledger-service**
2. **ledger-service** asked **auth-service**: "is this user logged in?"
3. **ledger-service** saved the row to the **database**
4. **redis** only runs if the amount is **big** (10,000 or more)

Each of those is a row you see in the Tempo detail screen. You are not looking at four separate requests — it is **one** request with multiple stops.

**Why do I see both ledger-service and auth-service?**

Because ledger had to call auth before it could save the transaction. Grafana groups those stops into **one trip** so you can see the full path, not just the first hop.

**Why did my demo have no redis row?**

You used `"amount": 5000`. The app only talks to redis when the amount is **10,000 or higher**. So seeing ledger + auth + database but **no redis** is correct.

Want to see redis? Run §7.5.6 again with `"amount": 15000` and search Tempo again.

**Optional: connect it to the code**

Open `app/ledger-service/main.py`, find `create_transaction`, and read top to bottom. The Tempo rows follow that function in order: check the user, save to the database, maybe notify redis.

**Optional: same request, three tools**

At the time you ran the curl:

- **Tempo** (this stage) — which services ran and how long each took
- **Loki** (Stage 7) — what the apps wrote in their log files
- **Prometheus** (Stage 7) — how many requests happened around that time

Same moment, three different views. You already used Loki and Prometheus in Stage 7.

---

### 7.5.8 — Verify

```bash
make check-75
```

Expected output:

```text
▶ Stage 7.5 — OpenTelemetry (Distributed Tracing)
  ✓ OTel Collector is running (1 replica(s))
  ✓ Grafana Tempo datasource ConfigMap exists
  ✓ Tempo is running
  ✓ auth-service has OTEL_EXPORTER_OTLP_ENDPOINT set
```

**If you see a warning instead:**

```text
⚠ OTel env vars not found on auth-service — redeploy with updated manifests
```

`check-75` looks for `OTEL_EXPORTER_OTLP_ENDPOINT` in the **deployment manifest**. Older Stage 5 manifests may not list it even though tracing works: the Python apps default to `http://otel-collector.monitoring.svc.cluster.local:4317` when the env var is missing.

You can proceed if collector logs show spans and Tempo shows your trace. To clear the warning, apply **only** the app deployments (not the whole kustomize tree: Kyverno may block redis/postgres patches):

```bash
kubectl apply -f infra/manifests/auth-service/deployment.yaml
kubectl apply -f infra/manifests/ledger-service/deployment.yaml
kubectl rollout restart deployment/auth-service deployment/ledger-service -n clearledger
make check-75
```

**Save your VM** after `make check-75`. See the block at the end of Stage 7.5 below.

---

### What You Learned

Stage 7 gave you **metrics** (how busy?) and **logs** (what was printed?). Stage 7.5 adds **traces** (for one slow request, which step took the time?).

In the lab you proved it with one `POST /transactions` curl. In production the idea is the same: a user hits an API, the request crosses multiple services, and you need to see that full path in one place.

**If someone asks in an interview**

**Why traces at all?**
Metrics might tell you p99 latency doubled. Logs might show an error on one pod. Traces tell you *which downstream call* in the chain caused the delay — auth, database, cache, third-party API — without guessing.

**How did you implement it?**
We instrumented the services with OpenTelemetry, sent telemetry to a collector, and stored traces in Grafana Tempo. Apps talk to the collector, not directly to the backend, so we can change storage later without redeploying every service.

**What would you do in an incident?**
Find a slow or failing trace ID (from logs, metrics, or an alert), open it in Tempo, walk the call chain service by service, see where time stacked up, then jump to logs for that service at the same timestamp. That is faster than tailing logs on five pods and hoping they line up.

**Short version you can say out loud:**

> "We use the three pillars together: Prometheus for rates and errors, Loki for log detail, and Tempo for request-level debugging across microservices. When latency spikes, I start from a trace, identify the slow hop — often a database or downstream API — and correlate back to logs and metrics for that service."

---

`make check-75 && make snapshot STAGE=75 && make snapshots`. Confirm `clearledger.stage75`. See [How to Save Your Progress](#heading-how-to-save-your-progress).

---

## Stage 8 — AWS Migration

**Goal:** run the same ClearLedger app on AWS instead of your laptop VM.

You are not rewriting the application. Stages 0–7 built containers on Kubernetes with GitOps, Kyverno, secrets, and observability. Stage 8 changes **where** it runs. You keep the same images, the same ArgoCD workflow, and the same security policies; only the cloud services underneath change (MicroK8s → EKS, Vault → Secrets Manager, and so on).

- **Homelab:** MicroK8s, Postgres in a pod, dev Vault, Docker Hub, `clearledger.local`
- **AWS:** EKS, RDS, Secrets Manager, ECR, ALB hostname

> **Am I ready for Stage 8?**
>
> - [ ] Homelab complete through Stage 7 (Stage 7.5 optional)
> - [ ] `make check-7` passes (and `make check-75` if you did traces)
> - [ ] AWS account with billing alerts enabled. `make aws-up` creates billable resources
> - [ ] Skim §8.2 so you know what `make aws-up` does (even if you use the quick path)
>
> **Done when:** app reachable on the AWS ALB, ArgoCD syncing, and you run `make aws-down` when finished to stop charges.

### What `make aws-up` gives you

This is a **demo stack**: production-*shaped*, not production-*ready*. HTTP only (no TLS cert). Stage 7 observability is installed automatically. CI still runs Gitleaks, Semgrep, Checkov, Trivy, and Cosign.

For real production you would add HTTPS (see `ingress-aws-https.example.yaml`), staging before promote, and alert routing. Those are documented but not applied by the spinup script.

**GitOps rule:** after bootstrap, do not `kubectl apply` app Deployments by hand. ArgoCD owns the cluster (Stage 2). Push manifest changes to Git and let ArgoCD sync.

### Secrets on AWS

On the homelab, Vault wrote secret **files** into the pod. On AWS, secrets live in **AWS Secrets Manager** (created by Terraform). Your app still needs them as environment variables like `DATABASE_URL`.

**ESO (default in this lab)** — the simple mental model:

1. Terraform stores the real password in **AWS Secrets Manager** (for example `clearledger/auth-service`)
2. **External Secrets Operator (ESO)** watches that AWS secret
3. ESO copies it into a normal **Kubernetes Secret** inside the cluster (for example `auth-service-secret`)
4. Your deployment reads `DATABASE_URL` from that Kubernetes Secret — same as Stage 0, but the values come from AWS instead of a YAML file in Git

You never put passwords in Git. ESO keeps the Kubernetes Secret in sync with Secrets Manager.

**CSI (optional, §8.5 exercise)** — same AWS secrets, different delivery: mounted as **files** at `/mnt/secrets/*` instead of env vars. Closer to how Vault worked on the homelab.

**IRSA** — how ESO is allowed to read Secrets Manager without storing AWS access keys in the cluster. AWS trusts a Kubernetes service account instead.

---

### 8.1 — Two ways through Stage 8

**Quick path (~45–60 min):** edit `terraform/secrets.tf` (replace `CHANGE_ME_BEFORE_APPLY`), then:

```bash
make aws-up    # runs stages/stage-8-aws-migration/scripts/aws-spinup.sh
make aws-down  # destroys billable resources when you are done
```

Read §8.2 afterward so you know what ran.

**Manual path (§8.3):** run Terraform, ECR push, ArgoCD, Kyverno, ESO, and deploy yourself. Use this when learning, interviewing, or debugging a failed spinup.

Do not skip §8.2–§8.5 if you only ran `make aws-up`. Otherwise you will not know what Terraform, ESO, or ArgoCD each did.

Before your first Stage 8 push, read [§8: CI routing and `CLEARLEDGER_CI_TARGET`](#heading-ci-routing-stages-17-vs-stage-8) and set `CLEARLEDGER_CI_TARGET=aws` only after Terraform succeeds, not while you are still on Stages 1–7.

---

### 8.2 — What `make aws-up` runs

The spinup script runs 15 steps in order:

**Setup (1–6)**. Check tools and AWS login; `terraform apply` (VPC, EKS, RDS, ECR, Secrets Manager, GuardDuty, CloudTrail, IAM); confirm security services; build and push images to ECR; patch `manifests/kustomization.yaml` with your registry and git SHA; configure `kubectl` for EKS.

**Platform (7–12)**: install ArgoCD; Kyverno + cluster policies; Falco; External Secrets Operator + IRSA service accounts; CSI secrets driver; Stage 7 observability stack.

**Deploy (13–15)**: ArgoCD app `clearledger-aws` syncs `stages/stage-8-aws-migration/manifests/`; wait for ALB hostname; print URL and tear-down reminder.

After the script finishes, open the printed **`http://<alb-dns>/`** in your browser (ClearLedger login UI), or follow [§8.3. When to open what](#heading-when-to-open-what-checkpoint-map) for Argo CD and Grafana port-forwards.

Default app deploy uses **ESO** for secrets. CSI is also installed so you can try file mounts in §8.5 without extra setup.

**Terraform layout**: there is no `terraform.tf` file. The `terraform {}` block (version, providers, optional S3 backend) is at the top of `main.tf`. Resources are split by topic: `vpc.tf`, `eks.tf`, `rds.tf`, `ecr.tf`, `alb.tf`, `iam.tf`, `secrets.tf`, `security.tf`. Run all commands from `stages/stage-8-aws-migration/terraform/`.

---

### 8.3 — Manual walkthrough

Run the manual walkthrough steps yourself at least once instead of `make aws-up`. Paths are from the repo root.

**Same 15 steps as the script — you are just typing them.** Steps 1–6 prepare AWS and your laptop (Terraform, images, GitOps manifest, `kubectl`). **Steps 7–12 install the platform on the cluster** (Argo CD, Kyverno, Falco, ESO, CSI, monitoring). Steps 13–15 deploy the app and print the ALB URL. Nothing here requires GitHub Actions unless you choose CI for images in step 4.

**Commands install things; UIs prove they work.** Homelab Stages 2 and 7 already taught you to open Argo CD and Grafana in a browser. Stage 8 is the same idea. But on AWS there is no `clearledger.local` or `grafana.local` in `/etc/hosts`. You use **port-forward** for control-plane UIs and the **public ALB hostname** for the app.

#### When to open what (checkpoint map)

Whether you use `make aws-up` or this manual walkthrough, the **same fifteen steps** run in the same order. You do not need every UI open at once — just know **when** to look and **what success looks like**.

First, Terraform builds the AWS foundation. When step 2 finishes, open the **AWS Console** and confirm the cluster, registry, and database exist before any pods run: EKS `clearledger` is **Active**, ECR has four repos including `frontend` (empty is fine for now), RDS `clearledger-postgres` is **Available**. See [AWS Console (after step 2)](#heading-aws-console-after-step-2) for the walkthrough.

Next come container images. After **step 4** (your manual `docker push`) — or after **CI — AWS (ECR + OIDC)** if you use that instead — check **ECR**: each repo should list your git SHA tag. That is what ArgoCD will pull when the app deploys.

Around **step 7** you install Argo CD. Port-forward to the UI and confirm the login page loads. You will not see the app yet; you are only checking that GitOps is reachable. Details: [Argo CD UI](#heading-step-13-watch-argocd-sync-ui-cli).

**Step 12** adds observability. Port-forward to **Grafana**, log in, and confirm the six ClearLedger dashboards are listed. Panels can stay empty until you generate events — same as Stage 7 on the homelab.

Step 13 applies the `clearledger-aws` app. Go back to Argo CD → **Applications** → `clearledger-aws`. You want **Synced**, **Healthy**, and running pods for frontend, auth, ledger, and notification.

Step 14 exposes the app on a public URL. Open **`http://<alb-dns>/`** in your browser — you should see the same ClearLedger login UI as homelab `clearledger.local`, served from the ALB with no `/etc/hosts` entry. Use `/auth/health` and the other health URLs when you want a quick API check from the terminal. See [ALB — first time the app is public](#heading-step-15-open-the-app-in-your-browser).

If you want extra confirmation, the optional check is **EC2 → Load Balancers → `clearledger`**: status **Active**, with healthy targets for frontend and the API services.

On AWS the app is **four services behind one ALB**: the **frontend** at `/` (login, dashboard, transactions) and the three APIs at `/auth`, `/ledger`, and `/notifications`. Your portfolio screenshot for Stage 8 is the ALB URL showing the UI — like `http://clearledger-xxxxxxxxxx.eu-west-1.elb.amazonaws.com` with the ClearLedger login or dashboard visible.

For Argo CD and Grafana, keep a dedicated terminal running `kubectl port-forward` while the browser tab is open. `Ctrl+C` closes the tunnel.

**Before you start**

**Step A — set real passwords in `secrets.tf`**

Open `stages/stage-8-aws-migration/terraform/secrets.tf` and search for the literal text **`CHANGE_ME_BEFORE_APPLY`**. It appears **four times** in the file (postgres password, JWT secret, and two database URLs). Replace every occurrence:

- **Postgres password** — pick a strong password (same value in all three places that reference it)
- **JWT secret** — run `openssl rand -base64 64` and paste the output

`make aws-up` will **refuse to run** if any `CHANGE_ME_BEFORE_APPLY` text is still in that file.

**Step B — terminal checks**

```bash
aws sts get-caller-identity
terraform --version

# Terraform apply will refuse to run without a real github_owner (even on the manual path)
cp stages/stage-8-aws-migration/terraform/terraform.tfvars.example \
   stages/stage-8-aws-migration/terraform/terraform.tfvars
# Edit: github_owner = "your-real-github-username"

terraform -chdir=stages/stage-8-aws-migration/terraform validate
```

On the **manual path** you still set `github_owner` so `terraform apply` succeeds — Terraform creates an IAM role for GitHub as a side effect. You are **not** required to run **CI — AWS (ECR + OIDC)**; step 4 pushes images from your laptop instead. The OIDC verify block below only matters if you switch to CI later.

**Steps 1–2. Terraform**

```bash
cd stages/stage-8-aws-migration/terraform
terraform init -upgrade
terraform apply
# Save outputs:
terraform output -raw ecr_registry_url
terraform output -raw github_actions_ecr_role_arn
terraform output -raw eso_role_arn
terraform output -raw auth_service_irsa_role_arn
terraform output -raw kubeconfig_command
cd ../../..
```

#### AWS Console (after step 2)

Confirm Terraform created resources before you touch the cluster:

1. **EKS** → Clusters → `clearledger` → **Status: Active**, **3 nodes**
2. **ECR** → Repositories → `clearledger/auth-service`, `ledger-service`, `notification-service`, `frontend` (0 images until step 4 or CI)
3. **RDS** → Databases → `clearledger-postgres` → **Available**

**Verify GitHub can push to ECR (only if you plan to use AWS CI later)**

GitHub Actions needs permission to push images to your AWS account. Terraform creates an IAM role for that — but only if you set your real GitHub username in `terraform.tfvars` **before** `terraform apply`.

Check it worked:

```bash
aws iam get-role --role-name clearledger-github-actions-ecr \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals."token.actions.githubusercontent.com:sub"' \
  --output text
```

**Good:** `repo:your-real-username/clearledger:environment:production`

**Bad:** `repo:YOUR_GITHUB_USERNAME/clearledger:...` — you forgot to edit `terraform.tfvars`. Fix the file, run `terraform apply` again, then in GitHub go to **Actions** → the failed **CI — AWS (ECR + OIDC)** run → click **Re-run failed jobs**. That retries only the push step — you do not need to rebuild and rescan everything.

Skip this whole block if you are only using `make aws-up` for now and not enabling AWS CI yet.

**When do ECR repos appear?**

During **`terraform apply` (step 2)** — not when you `docker push`. Terraform creates **empty** image repositories: `clearledger/auth-service`, `ledger-service`, `notification-service`, and `frontend`. Seeing **0 images** right after apply is normal. Images land later in step 4 (manual `docker push`) or when GitHub Actions CI succeeds.

**Set your AWS CLI region to `eu-west-1`**

Everything in this lab lives in **eu-west-1** (Ireland). If your CLI defaults to `us-east-1`, commands will say resources are missing even though they exist:

```bash
aws configure set region eu-west-1
aws configure get region   # expect: eu-west-1
```

**Steps 3–4. Security services + ECR images**

```bash
AWS_REGION=eu-west-1   # or rely on aws configure set region above

# Step 3 — verify security services (must pass --region eu-west-1)
aws guardduty list-detectors --region "${AWS_REGION}"
# Expect: DetectorIds: ["<id>"]  — empty [] means wrong region, not "not created"

aws cloudtrail get-trail-status --name clearledger-trail --region "${AWS_REGION}"
# Expect: IsLogging: true
# Error "Unknown trail ... us-east-1" → you forgot --region eu-west-1

# Step 4 — build and push images to the ECR repos Terraform already created
ECR_REGISTRY=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw ecr_registry_url)
AUTH_ECR=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw auth_service_ecr_url)
LEDGER_ECR=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw ledger_service_ecr_url)
NOTIFY_ECR=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw notification_service_ecr_url)
TAG=$(git rev-parse --short HEAD)

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker build -t "${AUTH_ECR}:${TAG}" app/auth-service && docker push "${AUTH_ECR}:${TAG}"
docker build -t "${LEDGER_ECR}:${TAG}" app/ledger-service && docker push "${LEDGER_ECR}:${TAG}"
docker build -t "${NOTIFY_ECR}:${TAG}" app/notification-service && docker push "${NOTIFY_ECR}:${TAG}"

# Confirm images landed (optional)
aws ecr describe-images --repository-name clearledger/auth-service --region "${AWS_REGION}" \
  --query 'imageDetails[*].imageTags' --output table
```

**ECR console (after step 4 or green CI)**: open each repository → **Images** tab. You should see tags matching your git commit SHA. If repos are empty, ArgoCD will show `ImagePullBackOff` later.

**GitHub Actions (if using CI instead of manual push)**: repo → **Actions** → workflow **CI. AWS (ECR + OIDC)**. All jobs green; **Publish images → ECR** succeeded. This is the supply-chain proof before deploy.

**Step 5: GitOps source of truth**

Patch placeholders in `kustomization.yaml` (same `sed` as `aws-spinup.sh` step 5):

```bash
AWS_REGION=eu-west-1
ECR_REGISTRY=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw ecr_registry_url)
TAG=$(git rev-parse --short HEAD)
KUST=stages/stage-8-aws-migration/manifests/kustomization.yaml

sed -i.bak \
  -e "s|REPLACE_ECR_REGISTRY|${ECR_REGISTRY}|g" \
  -e "s|REPLACE_IMAGE_TAG|${TAG}|g" \
  "${KUST}"
rm -f "${KUST}.bak"

# Region in ESO + CSI manifests (only if not eu-west-1)
if [[ "${AWS_REGION}" != "eu-west-1" ]]; then
  sed -i.bak "s|region: eu-west-1|region: ${AWS_REGION}|g" \
    stages/stage-8-aws-migration/manifests/external-secrets.yaml \
    stages/stage-8-aws-migration/manifests/csi/auth-service-spc.yaml \
    stages/stage-8-aws-migration/manifests/csi/ledger-service-spc.yaml
  rm -f stages/stage-8-aws-migration/manifests/external-secrets.yaml.bak \
        stages/stage-8-aws-migration/manifests/csi/*.bak 2>/dev/null || true
fi

# Verify before commit
grep -E 'newName:|newTag:' "${KUST}"
# Expect: YOUR_AWS_ACCOUNT.dkr.ecr.eu-west-1.amazonaws.com/clearledger/... and your git SHA

git add stages/stage-8-aws-migration/manifests/kustomization.yaml
git commit -m "stage8: ECR images ${TAG}"
git push
```

Also fix the ArgoCD Application repo URL once (replace with your GitHub username):

```bash
# Example: YOUR_GITHUB_USERNAME/clearledger — check: git remote get-url origin
sed -i.bak 's|YOUR_GITHUB_USERNAME|YOUR_ACTUAL_GITHUB_USER|g' \
  stages/stage-8-aws-migration/argocd/clearledger-aws-app.yaml
rm -f stages/stage-8-aws-migration/argocd/clearledger-aws-app.yaml.bak
```

**Step 6. Cluster access + Terraform outputs**

Run from the **repo root**. Set the CLI region first (EKS and IAM outputs are regional), then kubeconfig, then export IRSA role ARNs: steps 9–10 need them.

```bash
aws configure set region eu-west-1

eval "$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw kubeconfig_command)"
kubectl get nodes

export AWS_REGION=eu-west-1
export ESO_ROLE_ARN=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw eso_role_arn)
export FALCO_ROLE_ARN=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw falco_role_arn)
export REPLACE_AUTH_IRSA_ROLE_ARN=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw auth_service_irsa_role_arn)
export REPLACE_LEDGER_IRSA_ROLE_ARN=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw ledger_service_irsa_role_arn)
export REPLACE_NOTIFICATION_IRSA_ROLE_ARN=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw notification_service_irsa_role_arn)

# Sanity check (all should print ARNs, not empty)
echo "ESO:      ${ESO_ROLE_ARN}"
echo "Falco:    ${FALCO_ROLE_ARN}"
echo "Auth IRSA: ${REPLACE_AUTH_IRSA_ROLE_ARN}"
```

**Steps 7–12. Platform stack on the cluster**

You finished steps 1–6 (AWS exists, images in ECR, `kubectl` works). Now install the platform stack — **the same components as `aws-spinup.sh` steps 7–12, but you run the commands from the sections below**, not the script.

For each step: run the **Install** code block, then run the **Verify** block right under it. Do not move to the next step until you see Running pods (or a ClusterPolicy list). “Command finished with no output” is not enough.

| Step | Namespace | What you are installing | Rough pod count |
|------|-----------|---------------------------|-----------------|
| 7 | `argocd` | GitOps controller | ~7 pods |
| 8 | `kyverno` | Admission policies | ~4 pods + ClusterPolicies |
| 9 | `falco` | Runtime detection | 1 DaemonSet pod **per node** (3 on this cluster) |
| 10 | `external-secrets` + `clearledger` | ESO + IRSA ServiceAccounts | ~3 ESO pods + 3 ServiceAccounts |
| 11 | `kube-system` + `clearledger` | CSI driver + AWS provider | 3 driver + 3 provider (one per node) |
| 12 | `monitoring` | Prometheus, Grafana, Loki | ~10+ pods |

Steps 13–15 (deploy app, wait for ALB, verify UI) come after step 12 below.

---

#### Step 7 — ArgoCD

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
```

**Verify: what got created:**

```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
kubectl get deploy -n argocd
```

**Expected:** `argocd-server`, `argocd-repo-server`, `argocd-application-controller`, and so on: most pods **Running** / **1/1** or **2/2**. `argocd-server` Service exposes port 443.

**UI (optional now, required after step 13):** new terminal, leave running. Use any free local port (`8081` if `8080` is in use):

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Or if 8080 is taken:
# kubectl port-forward svc/argocd-server -n argocd 8081:443
# https://localhost:8080 (or 8081)  user: admin
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo
```

Applications list is empty until step 13, that is normal.

---

#### Step 8 — Kyverno + policies

`cosign.pub` / `infra/cosign.pub` are **gitignored** (private key must never commit; public key is learner-specific). The repo ships **example** keys in `require-signed-images.yaml` / `require-signed-images-ecr.yaml`. If you regenerated keys in Stage 3, sync your local public key into policies **before** apply:

```bash
# infra/cosign.pub exists locally but is gitignored — safe to copy into committed policy YAMLs
bash scripts/embed-cosign-pub-in-policies.sh
diff infra/cosign.pub <(grep -A3 'BEGIN PUBLIC KEY' infra/policies/require-signed-images-ecr.yaml | grep -v publicKeys)
```

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  -f stages/stage-4-admission-control/infra/kyverno/values.yaml \
  --set admissionController.replicas=1 \
  --wait --timeout=180s
kubectl apply -f infra/policies/
```

**Verify:**

```bash
kubectl get pods -n kyverno
kubectl get clusterpolicy
kubectl get clusterpolicy require-signed-images-ecr -o jsonpath='{.spec.rules[0].verifyImages[0].attestors[0].entries[0].keys.publicKeys}' | head -3
```

**Expected:** admission-controller, background-controller, cleanup-controller, reports-controller pods **Running**. `kubectl get clusterpolicy` lists **6+** policies including `require-signed-images-ecr`, `disallow-root-containers`, and so on The `publicKeys` output must show `-----BEGIN PUBLIC KEY-----`, **not** `PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE` (Kyverno treats a placeholder as a file path and blocks all deploys).

`require-signed-images-ecr` defaults to **Audit** until CI Cosign-signs ECR images (`COSIGN_PRIVATE_KEY` + `COSIGN_PASSWORD` in GitHub). Unsigned images still deploy; signed-image enforcement is optional later.

If `verify-slsa-provenance` fails to apply (Audit + `mutateDigest`), set `mutateDigest: false` in that file or skip it. It is optional for Stage 8.

---

#### Step 9 — Falco

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  -f stages/stage-6-runtime-security/infra/falco/helm-values.yaml \
  --set driver.kind=modern_ebpf \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${FALCO_ROLE_ARN}" \
  --wait --timeout=300s
```

**Verify:**

```bash
kubectl get pods -n falco -o wide
kubectl get daemonset -n falco
kubectl get sa falco -n falco -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'; echo
```

**Expected:** Falco **DaemonSet** with **DESIRED = number of nodes** (3); each pod **Running**. ServiceAccount annotation shows your `FALCO_ROLE_ARN`.

---

#### Step 10 — External Secrets Operator + IRSA ServiceAccounts

```bash
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ESO_ROLE_ARN}" \
  --wait --timeout=180s
kubectl apply -f stages/stage-8-aws-migration/manifests/resources/namespace.yaml
envsubst < stages/stage-8-aws-migration/manifests/clearledger-serviceaccounts.yaml | kubectl apply -f -
```

**Verify:**

```bash
kubectl get pods -n external-secrets
kubectl get sa -n external-secrets external-secrets -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'; echo
kubectl get sa -n clearledger
```

**Expected:** `external-secrets` deployment **Running** (often 3 containers / 1 pod). Three ServiceAccounts in `clearledger`: `auth-service`, `ledger-service`, `notification-service`: each with an `eks.amazonaws.com/role-arn` annotation. No app pods yet (ArgoCD deploys those in step 13).

---

#### Step 11 — CSI driver + SecretProviderClasses

```bash
bash stages/stage-8-aws-migration/scripts/install-csi-secrets.sh
```

**Verify:**

```bash
kubectl get pods -n kube-system | grep -E 'secrets-store|provider-aws'
kubectl get secretproviderclass -n clearledger
helm list -n kube-system | grep -E 'csi-secrets|secrets-provider'
```

**Expected:** CSI driver pods **3/3 Running** (one per node); AWS provider pods **1/1 Running** per node. Two `SecretProviderClass` objects in `clearledger`. Helm shows `csi-secrets-store` and/or `secrets-provider-aws` **deployed**.

If Helm reports `meta.helm.sh/release-name` conflicts, re-run the script. It installs the AWS provider without duplicating the driver chart.

---

#### Step 12 — Observability

```bash
bash stages/stage-7-observability/scripts/install-observability.sh
```

**Verify:**

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring | grep -E 'grafana|prometheus|loki'
kubectl get configmap -n monitoring -l grafana_dashboard=1 --no-headers | wc -l
```

**Expected:** Grafana **3/3 Running**, Prometheus and Loki pods **Running**. ConfigMap count for dashboards is **6** (ClearLedger dashboards). Script prints `http://grafana.local`: on EKS use port-forward instead:

```bash
# New terminal — keep running
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000  admin / admin123
# http://localhost:3000/dashboards?tag=clearledger
```

Panels may show **No data** until you trigger events (§7.4 exercises work on this cluster too).

---

**Platform stack summary**: quick sanity check before step 13:

```bash
for ns in argocd kyverno falco external-secrets monitoring clearledger; do
  echo "=== ${ns} ==="
  kubectl get pods -n "${ns}" --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c || echo "(no pods yet)"
done
kubectl get clusterpolicy --no-headers | wc -l | xargs echo "ClusterPolicies:"
kubectl get secretproviderclass -n clearledger --no-headers | wc -l | xargs echo "SecretProviderClasses:"
```

**Expected:** every namespace shows only `Running` (or `Completed` for jobs); `clearledger` may be empty until ArgoCD syncs. ClusterPolicies ≥ 6. SecretProviderClasses = 2.

> **EKS API timeout on namespace create?** You may see
> `Unexpected error when reading response body` / `context deadline exceeded`
> and still get `namespace/argocd created`. That is a **transient client timeout** talking to the EKS API (first request, slow network, or control plane catching up), not a failed create. Confirm with `kubectl get namespace argocd` and continue. If commands keep timing out, retry once or run `kubectl cluster-info` to verify connectivity.

**Steps 13–14. Deploy via ArgoCD + see the ALB**

The app YAMLs under `stages/stage-8-aws-migration/manifests/` are not applied by hand. Step 13 tells Argo CD to sync Git; Argo CD then creates Deployments, Services, Ingress, and the rest.

**Repo access first.** If your GitHub repo is private, add a PAT in Argo CD → Settings → Repositories. If you made the repo public, refresh the app — `ComparisonError: authentication required` should clear.

**If sync still fails**, the usual causes:

- **`external-secrets.io/v1beta1` not found** — your cluster has a newer ESO API. Push `external-secrets.yaml` with `apiVersion: external-secrets.io/v1`.
- **Kyverno complains about `PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE`** — run `bash scripts/embed-cosign-pub-in-policies.sh`, then `kubectl apply -f infra/policies/`.
- **`SecretSyncedError` on auth — `database_url` or `jwt_secret` not found** — the AWS secret `clearledger/auth-service` must contain both keys (Terraform writes them in `secrets.tf`). Re-run `terraform apply` after fixing `CHANGE_ME_BEFORE_APPLY` values, or check the secret in the AWS console.
- **Pods stuck `Pending` or “too many pods”** — the lab nodes are small. Scale the node group in Terraform or lower replica counts in the manifests.

Register the app:

```bash
kubectl apply -f stages/stage-8-aws-migration/argocd/clearledger-aws-app.yaml
```

Watch Argo CD until `clearledger-aws` is **Synced** and **Healthy** — that is when app pods appear in `clearledger`.

---

#### Step 13 — Watch ArgoCD sync (UI + CLI)

Open the Argo CD browser tab you kept open (port-forward from step 7).

```
https://localhost:8080        ← or 8081 if 8080 was busy
```

Click **`clearledger-aws`**. Wait for **Healthy + Synced** (2–5 minutes on first deploy). You can watch the same info from the terminal without touching the browser:

```bash
kubectl get application clearledger-aws -n argocd -w
# Ctrl-C when HEALTH STATUS shows Healthy
```

While that's settling, watch pods start up in a second terminal:

```bash
kubectl get pods -n clearledger -w
# All pods should reach 1/1 Running within 2 minutes
# Ctrl-C when everything is Running
```

---

#### Step 14 — Get your public app URL (ALB)

AWS takes **2–5 minutes** after ArgoCD syncs to provision the load balancer.
Run this and wait until the ADDRESS column fills in:

```bash
kubectl get ingress clearledger-ingress -n clearledger -w
# ADDRESS is empty at first, then shows something like:
# clearledger-xxxxxxxxxx.eu-west-1.elb.amazonaws.com
# Ctrl-C once the hostname appears
```

Export the URL for the steps below:

```bash
export ALB_DNS=$(kubectl get ingress clearledger-ingress -n clearledger \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Your app is live at: http://${ALB_DNS}"
```

> **Still empty after 10 minutes?** See [troubleshooting.md](https://github.com/Osomudeya/clearledger/blob/main/docs/troubleshooting.md) for ALB/ingress recovery steps.

---

#### Step 15 — Open the app in your browser

Paste the ALB root URL into your browser — no DNS entry, no port-forward, no VPN:

```
http://clearledger-xxxxxxxxxx.eu-west-1.elb.amazonaws.com/
```

You should see the **ClearLedger login screen** (same SPA as homelab `clearledger.local`). Register or log in, submit a transaction, and confirm the dashboard loads. That is your Stage 8 portfolio screenshot.

**Quick API health checks** (terminal or browser):

```bash
curl -fsS "http://${ALB_DNS}/auth/health" && echo
curl -fsS "http://${ALB_DNS}/ledger/health" && echo
curl -fsS "http://${ALB_DNS}/notifications/health" && echo
```

Each should return JSON like `{"status":"ok","service":"auth-service"}`.

---

#### Step 16 — Verify in the AWS Console (optional but recommended)

This is what the deployed stack looks like from AWS side:

| Console location | What to look for |
|---|---|
| **EC2 → Load Balancers** | A load balancer named `clearledger-…` with state **Active** |
| **EC2 → Target Groups** | Two or three target groups, all targets showing **healthy** |
| **ECR → Repositories** | `clearledger/auth-service`, `clearledger/ledger-service`, `clearledger/notification-service`, `clearledger/frontend` — each with a recently pushed image tag |
| **EKS → Clusters → clearledger → Workloads** | Your pods shown as Running in the `clearledger` namespace |
| **Secrets Manager** | `clearledger/auth-service`, `clearledger/ledger-service`, `clearledger/postgres` — all present |

> **502/503 from the ALB?** The load balancer is up but the pods aren't healthy yet, or the secrets haven't synced. Check: `kubectl get pods -n clearledger` (all `1/1 Running`?) and `kubectl get externalsecret -n clearledger` (both `SecretSynced True`?).

---

**✋ Hands-on checkpoint: app is publicly reachable**

```bash
# All three must print {"status":"ok",...}
curl -fsS "http://${ALB_DNS}/auth/health"         && echo
curl -fsS "http://${ALB_DNS}/ledger/health"        && echo
curl -fsS "http://${ALB_DNS}/notifications/health" && echo

# All pods Running
kubectl get pods -n clearledger

# Nothing printed here = all pods Running (non-Running pods would show)
kubectl get pods -n clearledger --field-selector=status.phase!=Running
```

> `ImagePullBackOff` in the pod list means ECR images aren't there yet. Check GitHub Actions and re-run the workflow. A `502` from the health URL means the pod isn't ready yet. Wait 30 seconds and retry.

---

### 8.4 — Verify ESO (default secret path)

After Argo CD syncs, confirm External Secrets Operator copied values from AWS Secrets Manager into normal Kubernetes Secrets:

```bash
kubectl get externalsecret,secret -n clearledger
kubectl describe externalsecret auth-service-secret -n clearledger | grep -A6 "Conditions:"
kubectl get pods -n clearledger -l app=auth-service
kubectl exec -n clearledger deploy/auth-service -c auth-service -- env | grep DATABASE_URL
```

**Command 1 — ExternalSecrets + Secrets**

You should see two ExternalSecrets and two matching Secrets (auth has 2 keys, ledger has 1):

```
NAME                                                     STORE                 REFRESH INTERVAL   STATUS         READY
externalsecret.external-secrets.io/auth-service-secret   aws-secrets-manager   1h                 SecretSynced   True
externalsecret.external-secrets.io/ledger-service-secret aws-secrets-manager   1h                 SecretSynced   True

NAME                         TYPE     DATA   AGE
secret/auth-service-secret   Opaque   2      3m
secret/ledger-service-secret Opaque   1      3m
```

`STATUS` must be **SecretSynced** and **READY** must be **True**. If you see `SecretSyncedError`, stop here and fix IRSA before §8.5.

**Command 2 — describe auth ExternalSecret**

Look for `Reason: SecretSynced` and `Status: True`:

```
  Conditions:
    Last Transition Time:   2026-07-10T22:15:00Z
    Message:                Secret was synced
    Reason:                 SecretSynced
    Status:                 True
    Type:                   Ready
```

**Command 3 — auth pods running**

```
NAME                            READY   STATUS    RESTARTS   AGE
auth-service-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
auth-service-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

Both replicas **1/1 Running**. If pods are `CrashLoopBackOff` or `CreateContainerConfigError`, the K8s Secret may be missing or empty.

**Command 4 — DATABASE_URL is an env var (ESO path), not a file path**

```
DATABASE_URL=postgresql://clearledger:*****@clearledger-postgres.xxxxx.eu-west-1.rds.amazonaws.com:5432/clearledger
```

Good: a `postgresql://...` connection string (password shown as `*****` or your real password).

Bad for this section: `/mnt/secrets/database_url` — that means CSI file mounts (§8.5), not the default ESO env-var path.

You can also spot-check the secret exists without printing values:

```bash
kubectl get secret auth-service-secret -n clearledger -o jsonpath='{.data}' | grep -o 'database_url\|jwt_secret'
# Expect: database_url and jwt_secret (two keys)
```

If `SecretSynced=False`, check ESO logs and IRSA:

```bash
kubectl logs -n external-secrets deploy/external-secrets -c external-secrets | tail -30
kubectl get sa auth-service -n clearledger -o yaml | grep role-arn
```

**✋ Hands-on checkpoint. External Secrets actually synced from AWS**

```bash
kubectl get externalsecret -n clearledger
kubectl get secret -n clearledger
```

Expected: `auth-service-secret` and `ledger-service-secret` each show `SecretSynced` / Ready `True`; the matching Kubernetes Secrets exist in `clearledger`. A `SecretSyncedError` means IRSA/IAM can't reach Secrets Manager: fix the role binding before §8.5.

If you skip this, §8.5 (CSI driver) builds on working secret access, and a silent IAM failure here surfaces as an unrelated-looking pod error two sections later.

---

### 8.5 — Hands-on: CSI driver (file mounts)

The default pods already use ESO: secrets arrive as environment variables from a Kubernetes Secret object. This exercise switches `auth-service` to the CSI path instead: secrets are mounted as plain files under `/mnt/secrets/`, and the app reads them from disk. It is the same code path the homelab uses with Vault (`DATABASE_URL_FILE` / `JWT_SECRET_FILE`).

CSI was already installed at spinup step 11, so there is nothing extra to install.

**Step 1. Confirm CSI is running**

```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get secretproviderclass -n clearledger
```

You should see one CSI driver pod per node, and two `SecretProviderClass` objects: one for auth-service and one for ledger-service.

**Step 2: swap the deployment in Git**

Open `stages/stage-8-aws-migration/manifests/kustomization.yaml` and change one line:

```yaml
# Before
  - deployments/auth-service.yaml

# After
  - deployments/auth-service-csi.yaml
```

Commit and push, then sync:

```bash
argocd app sync clearledger-aws
kubectl rollout status deployment/auth-service -n clearledger
```

ArgoCD will roll out a new auth-service pod with the CSI volume attached.

**Step 3. Confirm the files are there**

```bash
# Find the new pod
kubectl get pod -n clearledger -l secrets=csi

# List the mounted secret files
kubectl exec -n clearledger deploy/auth-service -- ls /mnt/secrets

# Check the database URL was written correctly
kubectl exec -n clearledger deploy/auth-service -- cat /mnt/secrets/database_url

# Confirm the service is still healthy
curl -s "http://$(kubectl get ingress clearledger-ingress -n clearledger \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/auth/health"
```

You should see `database_url` and `jwt_secret` listed as files, and the health check should return `{"status":"ok"}`.

**ESO vs CSI — what actually changed?**

Both paths read the **same passwords from AWS Secrets Manager**. Only the **delivery method** changes.

**ESO (default — what you verified in §8.4)**

Think of ESO as a **copy clerk** that runs in the cluster:

1. ESO has its own AWS permission (IAM role).
2. It reads `clearledger/auth-service` from Secrets Manager.
3. It copies the values into a normal Kubernetes Secret named `auth-service-secret`.
4. The auth pod reads `DATABASE_URL` and `JWT_SECRET` as **environment variables**.

The password lives briefly inside the cluster as a Kubernetes Secret object.

**CSI (this exercise — file mounts)**

Think of CSI as the **pod picking up secrets itself** when it starts:

1. The **auth-service pod** has its own AWS permission (IRSA on its ServiceAccount).
2. When the pod starts, the CSI driver asks Secrets Manager for the values.
3. They appear as **files** under `/mnt/secrets/` (`database_url`, `jwt_secret`).
4. The pod is told `DATABASE_URL_FILE=/mnt/secrets/database_url` — it reads from disk, not from a copied K8s Secret.

No Kubernetes Secret copy is created for those values on this path.

**Why does the same app code work for both?**

`app/auth-service/main.py` uses a small helper `_read_secret()`:

- If `DATABASE_URL_FILE` points to a file that exists → read the file (CSI or homelab Vault).
- Otherwise → read `DATABASE_URL` directly (ESO / Stage 0–4).

Same image, same code — you only change which deployment YAML Argo CD syncs.

**To switch back to ESO:** in `kustomization.yaml`, change `auth-service-csi.yaml` back to `auth-service.yaml`, commit, push, and `argocd app sync clearledger-aws`.

---

**Terraform** provisions all the AWS resources (VPC, EKS, RDS, ECR, Secrets Manager, and IAM roles) from `.tf` files in `stages/stage-8-aws-migration/terraform/`.

### Two OIDC ideas in Stage 8

Stage 8 uses OIDC in two different places. They sound similar, but they solve different problems.

**GitHub Actions OIDC** lets the CI pipeline push images to ECR without storing long-lived AWS keys in GitHub. When a job runs, GitHub mints a short-lived token that proves the job's identity. AWS trusts that token and hands back temporary credentials: enough to push images and nothing else.

**IRSA** does the same thing, but for pods running inside EKS. Instead of a GitHub token, the pod presents its Kubernetes ServiceAccount token. AWS trusts the EKS cluster's OIDC provider, verifies the token, and returns temporary credentials scoped to exactly what that pod needs.

It helps to see what each one says:

```text
GitHub Actions OIDC:
  Pipeline says → "I am a job in the production environment of YOUR_USERNAME/clearledger"
  AWS replies   → "Here are credentials to push to ECR, valid for one hour"

IRSA:
  Pod says   → "I am the auth-service ServiceAccount in the clearledger namespace"
  AWS replies → "Here are credentials to read only the auth-service secret, valid for one hour"
```

The key is what is *not* stored anywhere:

```text
No AWS_ACCESS_KEY_ID in GitHub Secrets
No AWS_SECRET_ACCESS_KEY in GitHub Secrets
No AWS keys inside Kubernetes Secrets
```

Terraform creates the role `clearledger-github-actions-ecr` and wires up the trust policies for both. The pipeline in `.github/workflows/ci-aws.yaml` assumes that role, pushes images to ECR, and updates `kustomization.yaml`. ArgoCD picks up the change and deploys the new images.

### CI routing: Stages 1–7 vs Stage 8

The repo ships two workflow files. You do not need both running at the same time.

`ci.yaml` is the homelab pipeline from Stages 1–7. It runs on your self-hosted Multipass VM, pushes images to Docker Hub, and updates your `clearledger-infra` GitOps repo. This is the default: nothing to configure.

`ci-aws.yaml` is the AWS pipeline for Stage 8. It runs on GitHub-hosted `ubuntu-latest` runners, pushes images to ECR, and updates `kustomization.yaml` directly in this repo. It only activates when you set the repo variable `CLEARLEDGER_CI_TARGET=aws`.

**If you are on Stages 1–7, do nothing.** The `CLEARLEDGER_CI_TARGET` variable is unset by default, so every push runs `ci.yaml` on your self-hosted runner as normal. The AWS workflow file exists in the repo but its jobs are skipped.

> **Do not set `CLEARLEDGER_CI_TARGET=aws` until your EKS cluster is running.**
>
> If you set it early, `ci.yaml` stops running on push (no more Docker Hub builds), and `ci-aws.yaml` will fail immediately because there is no ECR, no OIDC role, and no AWS infrastructure yet. If you accidentally set it, delete the variable: GitHub → repo **Settings** → **Secrets and variables** → **Actions** → **Variables** → delete `CLEARLEDGER_CI_TARGET`.

**Enabling AWS CI (do this after `terraform apply` completes)**

You need three repository variables and one secret in a `production` environment.

First, set the variables: replace `YOUR_USERNAME` with your GitHub username:

```bash
gh variable set CLEARLEDGER_CI_TARGET --body aws --repo YOUR_USERNAME/clearledger
gh variable set AWS_ACCOUNT_ID --body "$(aws sts get-caller-identity --query Account --output text)" --repo YOUR_USERNAME/clearledger
gh variable set AWS_REGION --body eu-west-1 --repo YOUR_USERNAME/clearledger
```

Then create the `production` environment and add the OIDC role ARN as a secret:

```bash
# Create the environment first — gh secret set returns 404 if it does not exist
gh api --method PUT "repos/YOUR_USERNAME/clearledger/environments/production"

gh secret set AWS_ACTIONS_ROLE_ARN \
  --env production \
  --body "$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw github_actions_ecr_role_arn)" \
  --repo YOUR_USERNAME/clearledger
```

> Note: GitHub blocks secret names that start with `GITHUB_`. Use `AWS_ACTIONS_ROLE_ARN`, not `GITHUB_ACTIONS_ROLE_ARN`.

Also make sure `github_owner` is set correctly in `terraform.tfvars` (see `terraform.tfvars.example`) before running `terraform apply`. This wires up the OIDC trust policy so AWS will accept tokens from your specific GitHub account.

Once `CLEARLEDGER_CI_TARGET=aws` is set, every push to `main` runs the AWS pipeline: Gitleaks → Semgrep → Checkov → build → Trivy scan → ECR push → kustomization update. The homelab `ci.yaml` is skipped.

**If CI fails at the ECR push step**

The most common failure is `Not authorized to perform sts:AssumeRoleWithWebIdentity`. This means the IAM role trust policy still has a placeholder `YOUR_GITHUB_USERNAME` in the `:sub` condition. Fix it by setting `github_owner` in `terraform.tfvars` and running `terraform apply` again, then re-run only the failed job (not the whole pipeline: the earlier scan steps already passed).

```text
GitHub → Actions → failed run → Re-run failed jobs
```

If you see `404` when running `gh secret set`, the `production` environment does not exist yet. Run the `gh api --method PUT` command above first.

**Re-run after fixing OIDC: failed jobs only, not the full pipeline.** Earlier gates (Gitleaks, build, scan) already passed; their artifacts are still in the workflow run. Use **Re-run all jobs** only if you changed app code or want a clean scan from scratch.

### Production Hardening Checklist

The lab architecture is production-style, but a real production setup needs extra guardrails. Add these before you describe it as production-ready.

#### 1. Protect the main branches

Protect both GitHub repos:

```text
github.com/YOUR_GITHUB_USERNAME/clearledger
github.com/YOUR_GITHUB_USERNAME/clearledger-infra
```

Go to each repo:

```text
Settings
→ Rules
→ Rulesets
→ New ruleset
→ Branch targeting: main
```

Enable:

```text
Require a pull request before merging
Require approvals
Require status checks to pass
Require branches to be up to date before merging
Block force pushes
Block branch deletion
```

Why this matters: nobody should push straight to the code repo or the GitOps repo in production. A bad direct push to `clearledger-infra` is a direct deployment request.

#### 2. Use GitHub Environments with approvals

Create a protected environment:

```text
clearledger repo
→ Settings
→ Environments
→ New environment
→ Name: production
→ Required reviewers: add yourself or the team
→ Deployment branches: main only
```

The AWS workflow uses:

```yaml
environment: production
```

That means GitHub pauses the AWS deployment until an approved reviewer allows it. This creates a real promotion gate instead of "every push deploys to prod."

#### 3. Prefer fine-grained tokens or a GitHub App

For the basic lab, `INFRA_REPO_TOKEN` can be a classic PAT. For production, tighten it.

Better option:

```text
Fine-grained personal access token
→ Repository access: only YOUR_GITHUB_USERNAME/clearledger-infra
→ Permissions:
   Contents: Read and write
   Metadata: Read
```

Best option for teams: use a GitHub App installed only on `clearledger-infra`, with permission to write contents. That gives better audit logs and easier rotation than a personal token.

Store `INFRA_REPO_TOKEN` as a **production environment secret**, not a general repository secret:

```text
clearledger
→ Settings
→ Environments
→ production
→ Environment secrets
→ INFRA_REPO_TOKEN
```

#### 4. Lock AWS OIDC to the production environment

This is **not a shell command**. It is a **trust rule** Terraform writes into AWS when you run `terraform apply`.

In `iam.tf`, the IAM role `clearledger-github-actions-ecr` only accepts GitHub tokens whose subject claim matches:

```text
repo:YOUR_GITHUB_USERNAME/clearledger:environment:production
```

Plain English: only GitHub Actions jobs running in the **`production` environment** of your `clearledger` repo can assume the ECR push role. A random branch, fork, or workflow without that environment cannot get AWS credentials.

**What you do (not the line above — that is the rule Terraform creates):**

1. Set `github_owner` in `terraform.tfvars`, then `terraform apply` (Stage 8 step 2).
2. On GitHub: **Settings → Environments → production** — create it if missing; add protection rules if you want.
3. Add environment secret `AWS_ACTIONS_ROLE_ARN` = `terraform output -raw github_actions_ecr_role_arn`.
4. `ci-aws.yaml` already sets `environment: production` on the ECR jobs — that is what makes GitHub mint a matching token.

**Verify the rule exists (optional):**

```bash
aws iam get-role --role-name clearledger-github-actions-ecr \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals."token.actions.githubusercontent.com:sub"' \
  --output text
```

Expect: `repo:your-username/clearledger:environment:production`

On the **manual Stage 8 path** you can skip GitHub CI entirely — this lock only matters when you enable **CI — AWS (ECR + OIDC)**.

#### 5. Staging before production (promote, do not rebuild)

**Lab flow (this repo today):** push to `main` → `ci-aws.yaml` builds and scans → CI updates `stages/stage-8-aws-migration/manifests/kustomization.yaml` with the new image tag → Argo CD syncs `clearledger-aws`. Homelab Stages 1–7 still use `clearledger-infra` and Docker Hub; Stage 8 AWS uses the in-repo kustomize path.

**Real production adds a staging step in the middle:** build the image once, deploy that **same tag or digest** to staging, run smoke tests or get manual approval, then promote to production — **without building again**.

Why: if you rebuild for prod, you might ship different code than what passed staging. The safe pattern is one artifact, tested once, promoted twice.

```text
Build once (one image SHA)
  → deploy to staging
  → test / approve
  → deploy the same SHA to production
```

#### 6. Use private networking where possible

For production AWS:

```text
EKS nodes in private subnets
RDS in private subnets
Private EKS API endpoint, or restricted public endpoint
Security groups scoped to required ports only
ALB public only if the app is public
No SSH-based deployment path
```

The pipeline should talk to AWS APIs through IAM/OIDC and deploy through GitOps. It should not SSH into EC2 instances.

#### 7. Store Terraform state remotely

Local Terraform state is fine for a lab. Production should use encrypted remote state:

```text
S3 bucket for terraform.tfstate
DynamoDB table for state locking
SSE encryption enabled
Bucket versioning enabled
Public access blocked
```

The Terraform backend block is already included in `stages/stage-8-aws-migration/terraform/main.tf` as a commented template. Uncomment it after you create the S3 bucket and DynamoDB lock table.

#### Production-ready summary

```text
CI builds and proves the artifact.
GitHub Environments approve production.
OIDC gives short-lived AWS credentials.
ECR stores immutable images.
kustomization.yaml (Stage 8 path) records desired state.
ArgoCD clearledger-aws deploys from Git.
No SSH. No static AWS keys. No direct kubectl from CI.
```

Open the URL. ClearLedger is running on AWS. Same architecture, same security layers, new infrastructure.

**Destroy when done. This stops all charges:**

```bash
make aws-down
```

See `stages/stage-8-aws-migration/README.md` for the full walkthrough and cost reference.

### What You Learned in Stage 8

- That containerized applications are portable: the same code runs on your laptop and on AWS
- What Terraform does: declares infrastructure as code so environments are reproducible
- What changes in a cloud migration (managed services, IAM, networking) and what does not (application code, CI logic, security policies)
- Three AWS secret delivery paths: ESO (default), CSI file mounts (§8.5), vs Vault on homelab
- AWS-specific security services: GuardDuty (threat detection), CloudTrail (API audit), GitHub Actions OIDC (pipeline AWS auth without long-lived keys), and IRSA (pod-level IAM without long-lived credentials)

**What you can now put on your CV / say in an interview:**

> Migrated the same architecture to AWS (EKS, ECR, RDS, ALB, with secrets via External Secrets Operator and IRSA) provisioned by Terraform, without rewriting the application.

**When you are done on AWS, tear down to stop charges:**

```bash
make aws-down
```

Your homelab VM is separate. If you plan to return to it, you should already have a snapshot from Stage 7 (`make snapshots` to confirm). See [Saving your progress](#heading-how-to-save-your-progress).

> **Want the deeper explanations behind the migration decisions?** [*DevOps Operating System*](https://osomudeya.gumroad.com/l/devops-atlas) breaks down the architecture, trade-offs, and reasoning that could not fit into the lab.

---

## Troubleshooting

**Pod stuck in Pending:**

```bash
kubectl describe pod POD_NAME -n clearledger
# Insufficient memory/cpu → reduce resource requests
# Image pull error → check Docker Hub repo name and credentials
```

**Kyverno blocking a deployment:**

```bash
kubectl get events -n clearledger --sort-by='.lastTimestamp' | tail -10
kubectl get policyreport -n clearledger -o yaml
```

**Vault agent not injecting secrets:**

```bash
kubectl logs POD_NAME -n clearledger -c vault-agent-init
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/auth-service
```

**Falco not firing alerts:**

```bash
kubectl logs -n falco daemonset/falco | grep -i error | tail -20
```

**ArgoCD shows OutOfSync:**

```bash
argocd app sync clearledger --force
argocd app get clearledger
kubectl get events -n clearledger --sort-by='.lastTimestamp'
```

**clearledger.local not resolving:**

```bash
multipass info clearledger | grep IPv4
grep clearledger /etc/hosts
# If the IP changed, update /etc/hosts
```

**VM disk full or pods Evicted (disk pressure):**

```bash
make doctor     # PASS / WARN / FAIL + PVC and Prometheus TSDB sizes
make reclaim    # safe reclaim — unused images + journald only (not PVCs)
```

If still FAIL after reclaim, tear down and recreate: `make teardown && make setup`. Full guidance: [troubleshooting.md: disk health](troubleshooting.md#disk-health-long-running-lab-vm) and [VM disk full](troubleshooting.md#vm-disk-full-or-nearly-full).

---

## Compliance Reference

Every control maps to at least one framework. Full mapping: [`docs/compliance-mapping.md`](compliance-mapping.md)

| Control | Tool | Stage | PCI-DSS | SOC2 | CIS K8s |
|---|---|---|---|---|---|
| Secrets detection | Gitleaks | 3 | 6.2 | CC8.1 | — |
| SAST | Semgrep | 3 | 6.3.2 | CC7.1 | — |
| Dependency scan | Trivy SCA | 3 | 6.3.3 | CC7.1 | — |
| IaC scan | Checkov | 3 | 6.3.1 | CC6.1 | — |
| Image signing | Cosign | 3 | 6.3 | CC6.1 | — |
| SBOM generation | Syft | 3 | 6.3.3 | CC6.1 | — |
| Non-root containers | Kyverno | 4 | 6.5 | CC6.3 | 5.2.6 |
| Resource limits | Kyverno | 4 | — | A1.1 | 5.2.4 |
| No privilege escalation | Kyverno | 4 | 6.5 | CC6.3 | 5.2.5 |
| Secrets management | Vault | 5 | 3.5 | CC6.1 | — |
| Runtime detection | Falco | 6 | 10.7 | CC7.2 | — |
| Network segmentation | NetworkPolicy | 6 | 1.3 | CC6.6 | 5.3.2 |
| Security observability | Grafana | 7 | 10.6 | CC7.2 | — |
| DORA metrics | ArgoCD + Grafana | 7 | — | — | — |
| Account threat detection | GuardDuty | 8 | 10.6 | CC7.2 | — |
| API audit trail | CloudTrail | 8 | 10.2 | CC7.3 | — |

**EU DORA (Digital Operational Resilience Act):** applies to EU financial entities since January 2025. ClearLedger maps to all five DORA pillars. Full mapping in `docs/compliance-mapping.md`.

---

## Interview Preparation

Full weak/strong answers: [`docs/interview-prep.md`](interview-prep.md)

Practice these as you finish each stage:

**Stage 0:** How does traffic reach your services in Kubernetes? What breaks first when deployment is manual?

**Stage 1:** How do you prove what image is deployed for a given commit? What stops a developer bypassing CI?

**Stage 2:** What does GitOps mean mechanically? How do you prove drift is corrected automatically?

**Stage 3:** Difference between SAST, IaC scanning, and image scanning? Where do you draw the line for fail-on severity?

**Stage 4:** What is admission control and why is it different from CI? How would you safely introduce a policy exception?

**Stage 5:** Why are Kubernetes Secrets not "secret management"? How do you rotate secrets with minimal downtime risk?

**Stage 6:** What does runtime detection catch that CI and admission cannot? What is your first response to a shell-spawn alert?

**Stage 7:** What is the difference between a dashboard and an alert? How do you produce audit evidence, not just claims?

**Stage 8:** What actually changes when you move to EKS? What should not change? How does IRSA reduce risk?

---

## AWS Cost Reference

Default Stage 8 sizes (eu-west-1, approximate):

| Resource | Monthly (8h/day) | Monthly (24/7) |
|---|---|---|
| EKS control plane | ~$24 | ~$73 |
| 3× t3.medium nodes | ~$30 | ~$92 |
| NAT Gateway | ~$11 | ~$33 |
| RDS db.t3.micro | ~$4 | ~$13 |
| ALB | ~$2 | ~$6 |
| GuardDuty + CloudTrail | ~$2 | ~$5 |
| **Total estimate** | **~$73** | **~$222** |

Always destroy when not in use:

```bash
make aws-down
```

---


## Conclusion

You have now built a fintech application and layered eight security and reliability controls on top of it: all from a laptop.

You started with raw Kubernetes and manual deploys in Stage 0. You added a CI pipeline that builds, scans, and signs images automatically in Stage 1. You connected Git to the cluster with ArgoCD in Stage 2. You gated every push with SAST, IaC, and image scanning in Stage 3. You blocked bad workloads at the cluster boundary with Kyverno in Stage 4. You moved credentials out of Git and Kubernetes secrets into Vault in Stage 5. You added runtime threat detection with Falco and network segmentation in Stage 6. You built observability dashboards that produce audit evidence in Stage 7. And you migrated the whole thing to AWS in Stage 8.

None of these stages is a toy exercise. Each one represents a real problem that real teams hit in production. You felt the pain, then built the solution. That is the difference between reading about DevSecOps and being able to do it.

Take your screenshots, update your CV with the specific tools and outcomes, and use the interview prep section when you need to talk through the decisions you made. You built every one of them.

**[Star the repo](https://github.com/Osomudeya/clearledger/stargazers)** · **[DevOps Beyond Tutorials](https://osomudeya.kit.com/23db7ca59f)** (weekly production architecture, troubleshooting, and interview lessons) · **[Connect on LinkedIn](https://www.linkedin.com/in/osomudeya-zudonu-17290b124/)**

**Go beyond the lab:** [*DevOps Operating System*](https://osomudeya.gumroad.com/l/devops-atlas) · [*DevOps Interview Decoder*](https://osomudeya.gumroad.com/l/pcpbks)
