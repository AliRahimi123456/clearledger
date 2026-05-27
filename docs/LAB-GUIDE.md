# ClearLedger Lab Guide

---

## What You Are Building

ClearLedger is a fintech transaction ledger — three FastAPI services, Postgres, Redis, and a web UI — secured across eight stages. The app processes credit and debit transactions and fires compliance alerts when transactions exceed a threshold.

| Service | Responsibility | Code |
|---|---|---|
| `auth-service` | Registration, login, JWT issuance | [`app/auth-service/`](../app/auth-service/) |
| `ledger-service` | Transactions, balance, history | [`app/ledger-service/`](../app/ledger-service/) |
| `notification-service` | Large-transaction alerts via Redis | [`app/notification-service/`](../app/notification-service/) |
| `frontend` | Web UI — login, dashboard, alerts | [`app/frontend/`](../app/frontend/) |

The app is the vehicle. DevSecOps is the destination.

| Stage | What changes | Why |
|---|---|---|
| 0 — Raw Kubernetes | App running, manual deploys | See the system before automating it |
| 1 — CI Pipeline | Builds automate on push | Manual docker build does not scale |
| 2 — GitOps | Pipeline stops touching kubectl | Cluster and Git drift apart |
| 3 — Security Gates | Scans block every commit | Bad code reaches the cluster undetected |
| 4 — Admission Control | Kyverno enforces policy at deploy time | Bad manifests reach running pods |
| 5 — Secrets Management | Vault replaces K8s Secrets | Credentials live in Git and etcd |
| 6 — Runtime Security | Falco watches live pods | Threats inside containers go undetected |
| 6.5 — Chaos Engineering | LitmusChaos kills pods | Detection is not the same as resilience |
| 7 — Observability | Six Grafana dashboards | Security you cannot measure you cannot prove |
| 7.5 — OpenTelemetry | Distributed traces | Metrics and logs do not show the request journey |
| 8 — AWS Migration | EKS, ECR, RDS, ALB | Cloud-ready without relearning the architecture |
| — **Optional: Local stack** | Docker Compose on your host (no VM) | Try the UI and APIs before or alongside Stage 0 |

**The rule:** every stage makes you feel the problem before showing the solution.

---

## How to Use This Guide

**Read, do not skim.** The paragraphs before each command explain *why* you are running it. Skipping them means you can reproduce the steps but not explain them — and explaining them is what gets you hired.

**Go in order.** Each stage depends on the one before it. Jumping ahead will break things and skip context you need later.

**When something breaks, read the error.** The troubleshooting section at the end covers every common failure. Getting stuck and debugging is part of the learning — employers want to hear "I hit X error and fixed it by doing Y."

**Take screenshots.** Every aha-moment section tells you to. These become your portfolio evidence. A screenshot of Kyverno blocking a root container or Falco catching a shell exec is worth more than a paragraph on your CV.

**Estimated time:** Stages 0–2 take a full day each. Stages 3–7 take half a day each. Stage 8 takes a few hours. That is normal. Do not rush.

---

## Who This Is For

**Junior DevOps (0–2 yrs):** do every stage in order. Do not skip the pain point sections. Expect Stage 0–2 to take a full day each. That is normal.

**Mid-level DevOps (2–4 yrs):** skim Stages 0–2 to understand the app, focus time on Stages 3–7 where the security layers are.

**Interview preparation:** complete through Stage 4, then read `docs/interview-prep.md`. The questions are based on exactly what is in this lab.

### What to put on your CV when you finish

By Stage 4, you can truthfully write:

> Built and secured a multi-service fintech application on Kubernetes with CI/CD (GitHub Actions + self-hosted runner), GitOps (ArgoCD), SAST/SCA/IaC scanning (Semgrep, Trivy, Checkov), image signing (Cosign), and admission control (Kyverno). Implemented compliance controls mapping to PCI-DSS, SOC2, and CIS Kubernetes benchmarks.

By Stage 7, add:

> Implemented runtime threat detection (Falco), secrets management (HashiCorp Vault), network segmentation, chaos engineering (LitmusChaos), and security observability dashboards (Prometheus, Grafana, Loki) with DORA metrics tracking.

These are not buzzwords. You built every one of them. The screenshots prove it.

---

## Before You Start

### System requirements

- 16 GB RAM minimum (the VM needs 8 GB reserved)
- 60 GB free disk space
- macOS, Linux (Ubuntu 20.04+), or Windows 10/11

### Install on your host machine

| Tool | What it does | macOS | Linux | Windows |
|---|---|---|---|---|
| Multipass | Creates lightweight Ubuntu VMs on your laptop | `brew install --cask multipass` | `sudo snap install multipass` | [multipass.run/install](https://multipass.run/install) |
| kubectl | Talks to your Kubernetes cluster from your terminal | `brew install kubectl` | `sudo snap install kubectl --classic` | `winget install Kubernetes.kubectl` |
| Helm | Package manager for Kubernetes (like apt/brew but for cluster apps) | `brew install helm` | `sudo snap install helm --classic` | `winget install Helm.Helm` |
| Docker Desktop | Builds container images on your machine | [docker.com](https://docs.docker.com/desktop/) | [docker.com](https://docs.docker.com/engine/install/) | [docker.com](https://docs.docker.com/desktop/) |
| jq | Formats JSON output so you can read it | `brew install jq` | `sudo apt install jq` | `winget install jqlang.jq` |

> **Windows:** use Git Bash or WSL2 for bash commands. Multipass and kubectl work in PowerShell natively.

Verify everything before continuing:

```bash
multipass --version
kubectl version --client --short
helm version --short
docker --version
jq --version
```

If any command fails, fix it now. Every stage depends on these.

---

## One Command to Start

```bash
make          # shows all available commands
make setup    # provisions the VM and cluster
```

After `make setup` finishes, it adds `KUBECONFIG` to your `~/.zshrc` so every future terminal knows where the cluster is. Your **current** terminal was already open before that happened, so run this once:

```bash
export KUBECONFIG=~/.kube/clearledger-config
kubectl get nodes   # should show Ready
```

Any new terminal you open after this will work automatically. Then continue:

```bash
make stage-0  # opens Stage 0 and shows what you're building
```

---

## Optional — Local integration stack (no Kubernetes)

This is **not a numbered stage**. It is a shortcut to run the same three APIs plus the web UI on your laptop with Docker only — useful before the VM is ready, for frontend checks, or to reproduce UI bugs without `kubectl`.

| | Local stack | Main lab (Stage 0+) |
|---|---|---|
| URL | **http://localhost:3000** | **http://clearledger.local** |
| Infra | [`docker-compose.integration.yml`](../docker-compose.integration.yml) | Multipass + MicroK8s + ingress |
| Data | Ephemeral Postgres in Compose (wiped on `down -v`) | Postgres in the cluster |

### Start and stop

```bash
# From the repo root on your host (Docker Desktop running)
docker compose -f docker-compose.integration.yml up --build -d

# Open the UI
open http://localhost:3000    # macOS
# Linux: xdg-open http://localhost:3000

# Automated API + UI checks (12 assertions)
bash scripts/test-frontend-integration.sh

# Stop (add -v to delete the database volume)
docker compose -f docker-compose.integration.yml down
```

### First-time sign-in

1. **Register** — the database starts empty after each fresh `up` (or `down -v`).
2. Use a real-looking email (Pydantic rejects `@*.local`), for example:
   - Email: `test@clearledger.io`
   - Password: `SecurePass123`
3. **Sign in** with the same credentials.

Wrong password shows *Incorrect email or password*. If you see a stale error, hard-refresh or run `localStorage.removeItem('cl_token')` in the browser console.

### Demo flow (matches Stage 0 curl lab)

1. Register and sign in at http://localhost:3000
2. Submit a few credits and debits (e.g. Salary +$5000, Rent −$1200)
3. Confirm balance updates and history lists entries
4. Submit a transaction **≥ $10,000** — the Alerts panel should show `LARGE_TRANSACTION`

Optional smoke test against the same base URL:

```bash
BASE_URL=http://localhost:3000 bash scripts/dast/smoke.sh
```

When you continue the main lab, deploy to Kubernetes as in Stage 0 and use **clearledger.local** — the UI and APIs behave the same; only the hostname and backing infra change.

---

## Domain Names

`make setup` handles this automatically — it runs `scripts/setup-hosts.sh` which adds all six domain entries to `/etc/hosts` for you. You only need this section if you skipped `make setup` and provisioned the VM manually (Step 0.1).

**Why these entries exist:** Kubernetes routes traffic based on the hostname in the URL. When your browser requests `clearledger.local`, it reaches the VM, and the Ingress controller inside the cluster decides which service to forward the request to. Without the `/etc/hosts` entry, your machine does not know that `clearledger.local` means "the VM's IP address."

<details>
<summary>Manual setup (only if you did not run <code>make setup</code>)</summary>

**macOS / Linux:**

```bash
VMIP=$(multipass info clearledger | grep IPv4 | awk '{print $2}')
sudo tee -a /etc/hosts << EOF
$VMIP  clearledger.local
$VMIP  argocd.local
$VMIP  grafana.local
$VMIP  vault.local
$VMIP  falco.local
EOF
```

Or run: `sudo bash scripts/setup-hosts.sh`

**Windows (PowerShell as Administrator):**

```powershell
$ip = "PASTE_VM_IP_HERE"
@(
  "$ip  clearledger.local",
  "$ip  argocd.local",     "$ip  grafana.local",
  "$ip  vault.local",      "$ip  falco.local"
) | Add-Content "C:\Windows\System32\drivers\etc\hosts"
```

</details>

---

## Stage 0 — The Running System

> The system works. But every change is manual, unaudited, and fragile.

**Goal:** ClearLedger is running on Kubernetes. You deployed everything by hand. You can register a user, create a transaction, and see a compliance alert fire. No automation exists yet. That is intentional — you need to feel what manual operations actually cost before you understand why every subsequent stage exists.

---

### 0.1 — Provision the cluster

**What you are doing:** creating a virtual machine on your laptop that runs its own Kubernetes cluster. Think of it as a miniature data center inside your computer.

**Multipass** creates lightweight Ubuntu VMs. **MicroK8s** is a minimal Kubernetes distribution that runs inside that VM. Together they give you a real cluster without needing cloud resources.

```bash
multipass launch \
  --name clearledger \
  --cpus 4 --memory 8G --disk 50G \
  22.04
```

Get the VM IP (you will need it if you are setting up `/etc/hosts` manually):

```bash
multipass info clearledger | grep IPv4
```

> If you used `make setup`, the hosts file is already configured. If you are provisioning manually, add the `/etc/hosts` entries now — see the "Domain Names" section above.

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
```

Expected:

```
NAME          STATUS   ROLES    AGE   VERSION
clearledger   Ready    <none>   2m    v1.29.x
```

If STATUS is `NotReady`, wait 60 seconds and try again. MicroK8s takes a moment to finish starting its internal services.

```bash
exit   # back to your host machine
```

Connect kubectl from your host so you can manage the cluster without SSH-ing into the VM every time:

```bash
multipass exec clearledger -- microk8s config > ~/.kube/clearledger-config
export KUBECONFIG=~/.kube/clearledger-config
kubectl get nodes   # should show Ready
```

Or run `make setup` to automate 0.1 and `/etc/hosts` in one step.

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

Notice in every Dockerfile: `USER appuser`. The container does not run as root. This matters more than you think right now — in Stage 4, Kyverno will automatically reject any container that tries to run as root. You are seeing the security requirement before you see the enforcement.

Also look at [`infra/manifests/auth-service/secret.yaml`](../infra/manifests/auth-service/secret.yaml). The database password is `changeme-stage0` encoded in base64. Decode it:

```bash
echo "Y2hhbmdlbWUtc3RhZ2Uw" | base64 -d
# changeme-stage0
```

That password is sitting in a YAML file anyone with repo access can read. base64 is encoding, not encryption — it is trivially reversible. Remember this moment. It is why Stage 5 exists.

---

### 0.3 — Docker Hub setup

You need a container registry — a place to store the built images so the cluster can pull them. Docker Hub is the simplest option. You will replace it with a private registry (ECR) in Stage 8.

Create four public repositories on Docker Hub (free account, hub.docker.com):

```
YOUR_USERNAME/clearledger-auth-service
YOUR_USERNAME/clearledger-ledger-service
YOUR_USERNAME/clearledger-notification-service
YOUR_USERNAME/clearledger-frontend
```

Generate an access token: hub.docker.com → Account Settings → Security → New Access Token (Read/Write/Delete). Save it — you will not see it again.

```bash
docker login
# Username: your Docker Hub username
# Password: the access token (NOT your account password)
```

Build and push all four services:

```bash
DOCKER_USERNAME=your-username   # replace with your actual username

docker build -t $DOCKER_USERNAME/clearledger-auth-service:v0.1.0 ./app/auth-service
docker build -t $DOCKER_USERNAME/clearledger-ledger-service:v0.1.0 ./app/ledger-service
docker build -t $DOCKER_USERNAME/clearledger-notification-service:v0.1.0 ./app/notification-service
docker build -t $DOCKER_USERNAME/clearledger-frontend:v0.1.0 ./app/frontend

docker push $DOCKER_USERNAME/clearledger-auth-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-ledger-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-notification-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-frontend:v0.1.0
```

Verify on hub.docker.com — four repos, each showing `v0.1.0`. If a push failed, re-run that specific push.

---

### 0.4 — Look at the manifests before applying them

**What are manifests?** YAML files that tell Kubernetes what to create. Each file describes a resource — a Deployment (runs your containers), a Service (gives them a network address), a Secret (stores credentials), or an Ingress (routes external traffic). Kubernetes reads these files and makes reality match the description.

| Manifest | What it creates |
|---|---|
| [`infra/manifests/namespace.yaml`](../infra/manifests/namespace.yaml) | The `clearledger` namespace — an isolated area within the cluster |
| [`infra/manifests/rbac/rbac.yaml`](../infra/manifests/rbac/rbac.yaml) | Security permissions — who is allowed to do what inside the cluster (explained below) |
| [`infra/manifests/postgres/`](../infra/manifests/postgres/) | Postgres StatefulSet — note `runAsUser: 70` (the postgres user in Alpine, not root) |
| [`infra/manifests/redis/redis.yaml`](../infra/manifests/redis/redis.yaml) | Redis Deployment — used as a message bus for notifications |
| [`infra/manifests/auth-service/`](../infra/manifests/auth-service/) | Deployment, Service, Secret |
| [`infra/manifests/frontend/deployment.yaml`](../infra/manifests/frontend/deployment.yaml) | nginx serving the SPA |
| [`infra/manifests/ingress.yaml`](../infra/manifests/ingress.yaml) | Routes external traffic to the correct service based on the URL path |

**About the Ingress file:** this is where most beginners get confused, so read this carefully.

Your cluster has four services running: frontend, auth-service, ledger-service, and notification-service. Each one has its own internal address inside the cluster (called a Service), but none of them are reachable from your browser. They are hidden inside the cluster's private network.

The **Ingress** is the front door. It tells Kubernetes: "when a request arrives from outside the cluster, look at the URL and forward it to the right service."

Here is how the routing works:

```text
Browser request                 Ingress decision              Backend service
─────────────────              ──────────────────            ────────────────
clearledger.local/             →  path starts with /         →  frontend
clearledger.local/auth/login   →  path starts with /auth     →  auth-service
clearledger.local/ledger/balance → path starts with /ledger  →  ledger-service
clearledger.local/notifications/alerts → path starts with /notifications → notification-service
```

The Ingress also **strips the prefix** before forwarding. So when your browser requests `/auth/login`, the Ingress removes `/auth` and sends just `/login` to auth-service. This is called a **rewrite**. The backend services do not know about the prefix — they only see their own routes (`/login`, `/register`, `/health`, etc.).

Open [`infra/manifests/ingress.yaml`](../infra/manifests/ingress.yaml) and read the comments. The file creates two Ingress resources:

- **`clearledger-api`** — handles `/auth`, `/ledger`, and `/notifications` paths. Uses regex to strip the prefix before forwarding.
- **`clearledger-frontend`** — handles `/` (everything else). No rewrite — passes the path through unchanged so static files like CSS and JavaScript load correctly.

Why two instead of one? The API services need the prefix stripped (rewrite). The frontend does not — it needs the full path preserved so `/style.css` stays `/style.css`. Mixing both behaviors in a single Ingress requires hacks. Two Ingress resources with clear, separate behavior is the standard production pattern.

The nginx Ingress controller (which MicroK8s provides via `microk8s enable ingress`) merges both resources internally. It serves them from a single entry point but applies the correct rules to each path.

**About the RBAC file:** RBAC stands for Role-Based Access Control. It answers the question "who is allowed to do what inside the cluster?" Open `infra/manifests/rbac/rbac.yaml` — the comments at the top walk through every section. The short version:

- Each service gets its own **ServiceAccount** (an identity card — Kubernetes knows which app is making a request)
- Each ServiceAccount gets a **Role** with minimal permissions (auth-service can look up service addresses, but cannot read secrets or delete anything)
- A **RoleBinding** connects the identity to the permissions (without it, the role exists but nobody uses it)
- A **viewer** account can see pods and services but never secrets — useful for monitoring and debugging
- The `default` ServiceAccount gets a role with **zero permissions** — so if someone forgets to assign a ServiceAccount to a pod, it cannot do anything

This is called **least privilege**: every app gets the minimum access it needs to function, nothing more. If auth-service is compromised, the attacker cannot read secrets or access other services through the Kubernetes API.

---

### 0.5 — Deploy everything

First, update the image references with your Docker Hub username:

```bash
# macOS
sed -i '' "s|DOCKER_USERNAME|$DOCKER_USERNAME|g" \
  infra/manifests/auth-service/deployment.yaml \
  infra/manifests/ledger-service/deployment.yaml \
  infra/manifests/notification-service/deployment.yaml \
  infra/manifests/frontend/deployment.yaml

# Linux: use sed -i without the empty string after -i
```

> Do not commit this change. From Stage 1 onwards CI manages image tags automatically.

Deploy in dependency order. Postgres must be running before the app services start, because they need the database connection:

```bash
kubectl apply -f infra/manifests/namespace.yaml
kubectl apply -f infra/manifests/rbac/rbac.yaml
kubectl apply -f infra/manifests/postgres/postgres-secret.yaml
kubectl apply -f infra/manifests/postgres/postgres.yaml

# Wait for Postgres before starting the application services
kubectl wait --for=condition=ready pod -l app=postgres \
  -n clearledger --timeout=120s

kubectl apply -f infra/manifests/redis/redis.yaml
kubectl apply -f infra/manifests/auth-service/secret.yaml
kubectl apply -f infra/manifests/auth-service/deployment.yaml
kubectl apply -f infra/manifests/auth-service/service.yaml
kubectl apply -f infra/manifests/ledger-service/secret.yaml
kubectl apply -f infra/manifests/ledger-service/deployment.yaml
kubectl apply -f infra/manifests/ledger-service/service.yaml
kubectl apply -f infra/manifests/notification-service/deployment.yaml
kubectl apply -f infra/manifests/notification-service/service.yaml
kubectl apply -f infra/manifests/frontend/deployment.yaml
kubectl apply -f infra/manifests/ingress.yaml

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

**Browser verification (recommended):**

Open `http://clearledger.local` in your browser. You should see the ClearLedger login screen.

1. Click **Register** and create an account (use a real-looking email like `test@clearledger.io` — Pydantic rejects obviously fake ones)
2. Sign in with the credentials you just created
3. On first login the dashboard auto-seeds demo transactions — wait a few seconds for them to appear
4. Look at the **Current Balance** card — it should show a dollar amount with a sparkline chart
5. Look at **Transaction History** — you should see entries like "Salary — Acme Corp", "Rent — May 2026", etc.
6. Look at the **Alerts** panel at the bottom — you should see `LARGE_TRANSACTION` alerts with a red badge. Two of the demo transactions exceed $10,000, which triggers the compliance alert automatically
7. Submit your own transaction over $10,000 — watch the alert count increase in real time

**What to look for:**

- Balance updates immediately after each transaction
- Credits show as green `+$` amounts, debits show as red `−$` amounts
- The Alerts badge count increases when you submit a transaction ≥ $10,000
- Each alert shows the amount, direction, and timestamp

**Take a screenshot of the dashboard showing transactions and at least one alert.** This is the first piece of your portfolio.

**Alternatively via curl** (useful if the browser is not cooperating):

```bash
# Register
curl -s -X POST http://clearledger.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' | jq .
```

Expected: `{"user_id":"...","email":"test@clearledger.io"}`

```bash
# Login — save the token
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' \
  | jq -r .access_token)
echo "Token: ${TOKEN:0:30}..."
```

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

Expected: `{"total":1,"alerts":[{"type":"LARGE_TRANSACTION","amount":15000,...}]}`

> **If you see `{"detail":"Unauthorized"}`:** your token has expired. JWTs are short-lived for security — this is intentional. Re-run the login command above to get a fresh token, then retry the failed command. This only affects the `$TOKEN` variable in your current terminal session. If you open a new terminal, you need to run the login command again because `$TOKEN` does not persist across sessions.

```bash
make check-0
```

---

### 0.7 — Feel the pain (intentional)

This section is deliberately uncomfortable. You are going to deploy a change the same way most real teams do it before they set up automation — manually. The goal is not to learn a good process. The goal is to feel why this process is bad, so every tool in the next stages makes immediate sense.

**Step 1 — Make a visible change.**

Open `app/auth-service/main.py` and find the `/health` endpoint. Change the return value so you can tell the new version is running:

```python
# Before
return {"status": "ok", "service": settings.service_name}

# After — add a version field
return {"status": "ok", "service": settings.service_name, "version": "0.2.0"}
```

Save the file. This simulates a developer shipping a small fix.

**Step 2 — Build, push, and deploy by hand.**

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

**Step 3 — Verify your change is live.**

```bash
curl -s http://clearledger.local/auth/health | jq .
```

Expected: `{"status":"ok","service":"auth-service","version":"0.2.0"}`

If you still see the old response without `"version"`, wait a few more seconds and retry — Kubernetes is still rolling out the new pods.

**Step 4 — Now sit with these questions.**

You just deployed a change. It works. But think about what just happened:

- **Who deployed this?** There is no record. You ran `kubectl` from your laptop. If three people have cluster access, no one knows who changed what.
- **What changed?** The only evidence is the Docker Hub tag `v0.2.0`. Nothing links that tag to a specific commit or code review.
- **What if `v0.2.0` is broken?** You would need to remember the previous tag, then run `kubectl set image` again to roll back. What if you do not remember the tag? What if the previous image was deleted?
- **What if someone else runs `kubectl apply` with `v0.1.0` while you are pushing `v0.2.0`?** The cluster silently reverts to the old version. No error. No notification. You think your fix is live, but it is not.
- **Where is the audit trail?** Nowhere. In a regulated environment (banking, healthcare, government), you need proof of who deployed what and when. Right now you have nothing.

There are no good answers with this approach. That is the point. Remember this feeling — it is why every subsequent stage exists.

**Step 5 — Revert your change before continuing.**

Undo the health endpoint change in `app/auth-service/main.py` (remove `"version": "0.2.0"`). Do not rebuild — the cluster will keep running `v0.2.0` for now, and Stage 1 will take over image management.

Stage 1 automates the build. Stage 2 fixes the deployment.

### What you learned in Stage 0

- How to provision a local Kubernetes cluster with Multipass and MicroK8s
- How Kubernetes manifests describe the desired state of your system
- How an Ingress routes external traffic to internal services
- How to build, push, and deploy container images manually
- **Why manual deployment is a problem** — no audit trail, no rollback, no consistency

---

## Stage 1 — CI Pipeline (GitHub Actions + Self-Hosted Runner)

> The build is automated. The deployment is not. That gap has a name.

**Goal:** a `git push` to GitHub automatically builds images, pushes them to Docker Hub, and updates the image tags in the `clearledger-infra` repo on GitHub. You still deploy manually. One pain point removed — the cluster drift remains.

### What you need to know first

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
Infra manifests are updated with the new image tags
```

The important idea: **the build no longer depends on your laptop**. Your laptop writes code. The pipeline produces the release artifact.

A CI system has three parts:

1. **Pipeline host** — the control plane. It notices a push and decides which workflow to run. In this lab, that is **GitHub Actions**.
2. **Pipeline file** — the instructions. It is a YAML file at `.github/workflows/ci.yaml` that says what jobs to run.
3. **Runner** — the worker machine. It actually executes the commands in the pipeline.

GitHub Actions normally uses GitHub-hosted runners in the cloud. In this lab, that is not enough. Your Kubernetes cluster lives inside a local Multipass VM. GitHub's cloud runner cannot reach it. You also need the runner inside the VM to build Docker images using the local Docker daemon.

So you install a **self-hosted runner** inside the VM. It connects outbound to GitHub, waits for work, then executes pipeline jobs locally where it can reach everything.

```text
GitHub.com
  stores app repo
  starts workflow on git push
        ↓
Self-hosted runner inside Multipass VM
  builds Docker images
  pushes images to Docker Hub
  updates image tags in clearledger-infra on GitHub
        ↓
GitHub (clearledger-infra repo)
  stores Kubernetes YAML with updated image tags
  ArgoCD watches this in Stage 2
```

Both repos live on GitHub. The runner is the only piece that runs locally — and it only needs outbound internet access to GitHub and Docker Hub.

This stage intentionally stops before automatic deployment. After the pipeline runs, the infra repo has changed, but the cluster has not. That unfinished handoff is the lesson: **CI automates building; GitOps automates applying.** Stage 1 gives you CI. Stage 2 adds GitOps.

---

### 1.1 — Push the App Repo to GitHub

First, put the application repo somewhere a pipeline host can see it.

Go to GitHub → New Repository:

- Repository name: `clearledger`
- Visibility: Public
- Do not initialize with a README or `.gitignore`

The repo already has those files locally. If GitHub creates its own, your first push may fail because the histories do not match.

```bash
git remote add origin https://github.com/YOUR_USERNAME/clearledger.git
git branch -M main
git push -u origin main
```

Verify in the browser: `https://github.com/YOUR_USERNAME/clearledger`.

You should see your application code, Dockerfiles, Kubernetes manifests, and `.github/workflows/ci.yaml`.

What you proved: GitHub can now see your code and can trigger automation when you push.

### 1.2 — Install the Self-Hosted Runner Inside the VM

The workflow file tells GitHub *what* to run. The runner is *where* it runs.

This lab uses a self-hosted runner because your infrastructure is local. GitHub's cloud servers cannot reach your MicroK8s cluster or Docker daemon inside the Multipass VM. The runner solves that by living inside the VM — it connects outbound to GitHub to pick up jobs, then executes everything locally.

```
GitHub (cloud)
  sees the git push
  schedules a workflow job
  ↓
Self-hosted runner (inside VM)
  receives the job
  builds Docker images
  pushes images to Docker Hub
  updates image tags in clearledger-infra on GitHub
```

If the runner is missing or offline, the pipeline cannot execute. The workflow may sit queued, or it may fail because no matching runner is available.

**Step 1 — Generate a runner token on GitHub**

Go to: github.com/YOUR_USERNAME/clearledger → Settings → Actions → Runners → New self-hosted runner

Select: Linux → x64

Copy the token shown. It looks like: `AXXXXXXXXXXXXXXXXXXXXXXXXX`

Do NOT close this page yet — the token expires in 1 hour.

**Step 2 — Enter the VM**

```bash
multipass shell clearledger
```

> **STOP. Check your prompt before continuing.**
>
> After running `multipass shell clearledger`, your terminal prompt should change to something like:
> ```
> ubuntu@clearledger:~$
> ```
> If your prompt still shows your Mac username (e.g. `mac@192` or `yourname@MacBook`), you are still on your host machine.
> The runner binary is compiled for Linux. Running it on macOS will fail with:
> `cannot execute binary file`
>
> Do not proceed until your prompt shows `ubuntu@clearledger`.

**Everything from Step 3 onwards runs inside the VM, not on your Mac.**

**Step 3 — Install Docker inside the VM**

The runner will build Docker images. That means Docker must exist where the runner runs.

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu
newgrp docker

docker --version
```

Expected: Docker prints a version number.

What you proved: the VM can build container images without relying on Docker Desktop on your host.

**Step 4 — Install and register the runner**

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

The `clearledger` label is required. The workflow uses:

```yaml
runs-on: [self-hosted, clearledger]
```

GitHub schedules jobs by runner **labels**, not by runner name. A runner named `clearledger` without the `clearledger` label will stay online but jobs will remain queued with `Waiting for a runner to pick up this job`.

What those last two commands mean:

```text
sudo ./svc.sh install
  Registers the runner with systemd inside the VM.
  Without this, `sudo ./svc.sh status` says: not installed.

sudo ./svc.sh start
  Starts the runner service in the background.
  After this, it keeps running even when you close the terminal.
```

Check it locally from the same folder, still inside the VM:

```bash
cd ~/actions-runner
sudo ./svc.sh status
```

Expected: the service is installed and running.

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

**Step 5 — Exit the VM**

```bash
exit
```

**Step 6 — Verify the runner is connected**

Go to: github.com/YOUR_USERNAME/clearledger → Settings → Actions → Runners

You should see `clearledger-runner` with a green dot and status **Idle**. Open the runner details and confirm the labels include:

```text
self-hosted
Linux
X64
clearledger
```

If `clearledger` is missing, add it in the runner settings before rerunning the workflow. The runner name alone is not enough.

If it shows Offline:

```bash
multipass exec clearledger -- sudo systemctl status actions.runner.*.service
multipass exec clearledger -- journalctl -u actions.runner.*.service --lines=50
```

What you proved: GitHub can now send work into your local lab environment.

### 1.3 — Create the Infra Repo on GitHub

Now separate **application code** from **deployment state**.

You now use two GitHub repositories:

| Repo | What lives there | Who changes it | Why it exists |
|---|---|---|---|
| `clearledger` | App source code, Dockerfiles, tests, `.github/workflows/ci.yaml`, lab docs | You, the developer | This is where code changes start |
| `clearledger-infra` | Kubernetes manifests only: `deployment.yaml`, `service.yaml`, ingress, secrets templates | The CI pipeline, then ArgoCD reads it | This is the desired state of the cluster |

The important idea:

```text
clearledger
  "Here is the application code"

clearledger-infra
  "Here is the exact version that should run in Kubernetes"
```

Why not keep everything in one repo?

Because the two repos answer different questions:

```text
clearledger asks:
  What is the application code?

clearledger-infra asks:
  What exact version should the cluster run right now?
```

Imagine you edit `README.md` in `clearledger`. That is a code/documentation repo change, but it should not mean "deploy the application." Now imagine you change `auth-service` code and the pipeline builds image tag `abc123`. Only after tests and scans pass should the desired running version change.

That is why the pipeline writes this kind of change into `clearledger-infra`:

```yaml
image: osomudeya/clearledger-auth-service:abc123
```

Then ArgoCD watches `clearledger-infra` and says:

```text
Git says auth-service should run abc123.
The cluster is running the old tag.
I will update the cluster to match Git.
```

So the app repo is where work starts. The infra repo is the deployment contract.

The pipeline flow is:

```text
You push code to clearledger
        ↓
GitHub Actions builds Docker images
        ↓
Images are pushed to Docker Hub
        ↓
Pipeline updates clearledger-infra with the new image tags
        ↓
Stage 2: ArgoCD watches clearledger-infra and deploys it
```

The pipeline does **not** deploy directly to the cluster. That is Stage 2 (ArgoCD).

Go to github.com → New Repository → Name: `clearledger-infra` → Public → Create.

Push only the Kubernetes manifests:

```bash
mkdir -p /tmp/clearledger-infra
cp -r infra/manifests /tmp/clearledger-infra/
cd /tmp/clearledger-infra
git init
git remote add origin https://github.com/YOUR_USERNAME/clearledger-infra.git
git add . && git commit -m "feat: initial manifests" && git push -u origin main
cd -
```

Stage 1 does not keep a separate copy of manifests inside `stages/stage-1-ci-pipeline/infra`. If that folder is empty or missing, that is expected. The source manifests for this stage are the root manifests:

```text
infra/manifests/
```

You copy those manifests into the separate GitHub repo named `clearledger-infra`. That repo is the real Stage 1 infra target. The app repo stays focused on application code and pipeline logic; `clearledger-infra` becomes the desired-state repo that the pipeline updates after successful builds.

What you proved: the infrastructure definition has its own Git history, separate from application code.

### 1.4 — Set up GitHub Secrets

Go to: `github.com/YOUR_USERNAME/clearledger` → Settings → Secrets and variables → Actions → New repository secret

The workflow needs credentials for two external systems:

- Docker Hub, so it can push images.
- GitHub, so it can push image tag updates into `clearledger-infra`.

Do **not** paste these values into YAML files. Store them as GitHub Actions secrets.

**Secret 1 — `DOCKER_USERNAME`**

This is just your Docker Hub username.

Example:

```text
osomudeya
```

Get it from Docker Hub: hub.docker.com → profile menu → Account Settings.

**Secret 2 — `DOCKER_PASSWORD`**

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

**Secret 3 — `INFRA_REPO_TOKEN`**

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

Add these three secrets:

| Secret name | Value | Purpose |
|---|---|---|
| `DOCKER_USERNAME` | Your Docker Hub username | Pipeline logs in to push images |
| `DOCKER_PASSWORD` | Your Docker Hub access token | Pipeline authenticates with Docker Hub |
| `INFRA_REPO_TOKEN` | The GitHub PAT from above | Pipeline pushes image tag updates to clearledger-infra |

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
1. Scan secrets
        ↓
2. Run code security scans (SAST)
        ↓
3. Scan Kubernetes and IaC files
        ↓
4. Build Docker images
        ↓
5. Scan images for vulnerabilities
        ↓
6. Generate a software inventory (SBOM)
        ↓
7. Push images to Docker Hub with commit SHA tags
        ↓
8. Sign images with Cosign
        ↓
9. Produce supply-chain evidence for later verification
```

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

Important: the image tag is based on the commit SHA. That means you can answer "which code produced this image?" just by looking at the tag.

The pipeline does **not** deploy to Kubernetes directly. It only updates `clearledger-infra`. Stage 2 installs ArgoCD, and ArgoCD watches `clearledger-infra` to deploy the change.

| Section | What it does | Why |
|---|---|---|
| `on: push: branches: [main]` | Triggers on every push to main | Every change gets built automatically |
| `runs-on: [self-hosted, clearledger]` | Uses your local runner | Needed to reach the local cluster and Docker daemon |
| `docker/login-action` | Logs in to Docker Hub | Runner needs auth to push images |
| Build jobs | Builds and pushes each service image | Same work as Stage 0, but repeatable and tied to a commit |
| `update-manifests` | Updates image tags in clearledger-infra on GitHub | Records the desired new version in Git |

The Kubernetes Checkov scan in Stage 1 is evidence-only. It uploads findings so you can see the hardening work ahead, but it does not block the first CI pipeline run. That is intentional: Stage 1 proves the build-push-update flow. Later stages tighten Kubernetes policy with security gates, admission control, and secrets management.

Notice what the pipeline does **not** do: it does not run `kubectl`.

That is intentional. CI should produce artifacts and update desired state. It should not directly mutate the cluster. Direct cluster mutation is hard to audit and easy to drift from Git.

### 1.6 — Activate the pipeline

The pipeline file already exists at `.github/workflows/ci.yaml`. Push any small change to trigger it:

```bash
echo "# Pipeline activated $(date)" >> README.md
git add README.md
git commit -m "ci: activate GitHub Actions pipeline"
git push origin main
```

Watch the run at: `https://github.com/YOUR_USERNAME/clearledger/actions`

Expected: all jobs green in about 8 minutes.

```
✓ Build + Scan auth-service
✓ Build + Scan ledger-service
✓ Build + Scan notification-service
✓ Build + Scan frontend
✓ Update manifests → GitHub
```

Note: this lab includes `.gitleaksignore` because some intentional demo secrets are already present in git history. Gitleaks still runs normally. The ignore file only suppresses known lab fingerprints. Do not add new findings to it unless you have confirmed they are intentional test data.

Click into the job logs and look for the story — do not just wait for green:

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

```bash
make check-1
```

### What you learned in Stage 1

- **CI removes your laptop from the build process.** Builds become repeatable, visible, and tied to Git commits.
- **A runner is the worker, not the pipeline itself.** GitHub schedules the job; the self-hosted runner executes it inside your VM.
- **Artifacts and desired state are different things.** Docker Hub stores built images. `clearledger-infra` on GitHub stores the Kubernetes manifests that say which image should run.
- **Good pipelines do not secretly mutate clusters.** This pipeline updates Git instead of running `kubectl`.
- **The gap that remains:** the infra repo changed, but the cluster did not. Someone still has to apply the change manually. Stage 2 fixes that with GitOps.

---

## Stage 2 — GitOps with ArgoCD

> Git is truth. The cluster proves it by correcting itself.

**Goal:** ArgoCD watches the infra repo and syncs the cluster to match. The pipeline never runs `kubectl` again.

### What you need to know first

**GitOps** is a deployment model where Git is the single source of truth for what should be running in the cluster. Instead of someone running `kubectl apply` or clicking "deploy" in a dashboard, a tool watches a Git repo and automatically applies any changes it sees.

**ArgoCD** is that tool. It runs inside your cluster, polls your infra Git repo every few minutes, and compares the manifests in Git to what is actually running. If they differ — whether because a new commit updated an image tag or because someone manually changed something in the cluster — ArgoCD corrects the cluster to match Git.

This solves every problem from Stage 0.7:
- **Who deployed what?** Check the Git history.
- **What is running right now?** Whatever Git says.
- **How do you roll back?** Revert the commit.
- **What if someone changes the cluster directly?** ArgoCD undoes it.

---

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s
```

Get the admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Apply the ArgoCD Ingress so your browser can reach it:

```bash
kubectl apply -f stages/stage-2-gitops/infra/argocd-ingress.yaml
```

Open `https://argocd.local` — login: `admin` / the password from the command above.

Connect ArgoCD to the infra repo and apply the Application manifest:

```bash
# Install the ArgoCD CLI first
# macOS: brew install argocd
# Linux: curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && chmod +x argocd && sudo mv argocd /usr/local/bin/

argocd login argocd.local --username admin --password YOUR_PASSWORD --insecure

# Connect ArgoCD to the infra repo on GitHub
# Public repo: no credentials needed
# Private repo: use your INFRA_REPO_TOKEN PAT
argocd repo add https://github.com/YOUR_USERNAME/clearledger-infra.git

# Update the repo URL in the Application manifest before applying
sed -i '' "s|YOUR_USERNAME|$(git config user.name)|g" \
  stages/stage-2-gitops/argocd/clearledger-app.yaml

kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
argocd app sync clearledger
```

**Take a screenshot of ArgoCD showing all resources synced and healthy.** This is portfolio evidence.

**Prove the contract — this is the aha moment:**

```bash
# Manually change the image to a fake tag
kubectl set image deployment/auth-service \
  auth-service=$DOCKER_USERNAME/clearledger-auth-service:fake-tag \
  -n clearledger

# Wait 3 minutes. Do nothing.
sleep 180

# Check — ArgoCD reverted it
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

The image is back to the Git version. The cluster self-corrected without being asked. That is GitOps working. If someone — even you — makes an unauthorized change to the cluster, ArgoCD reverts it within minutes.

```bash
make check-2
```

### What you learned in Stage 2

- What GitOps means: Git is the single source of truth, and a tool enforces it
- What ArgoCD does: watches Git, compares it to the cluster, corrects drift automatically
- How the full flow works now: push code → CI builds image → CI updates infra repo → ArgoCD syncs cluster
- **No one runs `kubectl` to deploy anymore.** The pipeline updates Git, ArgoCD does the rest.

---

## Stage 3 — Security Gates

> Every commit passes through security checks. A failure at any gate stops the pipeline.

**Goal:** six security tools scan every commit. Each one catches a different category of vulnerability. You will deliberately trigger each one to see exactly what it catches and why it matters.

### What you need to know first

Security scanning has categories, each catching problems at a different layer:

| Category | What it scans | What it catches | Tool in this lab |
|---|---|---|---|
| **Secrets detection** | Your code and Git history | Leaked API keys, passwords, tokens that should never be in source code | Gitleaks |
| **SAST (Static Application Security Testing)** | Your application source code | Code-level vulnerabilities — SQL injection, command injection, insecure deserialization | Semgrep |
| **SCA (Software Composition Analysis)** | Your dependencies (pip packages, npm modules) | Known CVEs in third-party libraries you depend on | Trivy |
| **IaC scanning (Infrastructure as Code)** | Your Kubernetes manifests, Dockerfiles, Terraform files | Misconfigurations — containers running as root, missing resource limits, secrets in plaintext | Checkov |
| **Image scanning** | Your built Docker images | OS-level vulnerabilities in the base image (e.g. outdated openssl) | Trivy |
| **Image signing** | Your built Docker images | Proves an image was built by *your* pipeline, not tampered with after the fact | Cosign |

No single tool covers everything. That is why you need all six — each one is a gate that blocks a different class of problem from reaching production.

**Pre-commit hooks** run these checks on your laptop *before* the commit even reaches Git. The CI pipeline runs them again on the server. This is defense in depth — two chances to catch a problem.

---

### 3.1 — Install pre-commit hooks

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

Test it catches secrets locally before CI does:

```bash
echo 'AWS_SECRET = "AKIAIOSFODNN7EXAMPLE"' >> app/auth-service/main.py
git add app/auth-service/main.py && git commit -m "test"
# Gitleaks fires and blocks the commit
git checkout app/auth-service/main.py
```

The commit was blocked before it even reached Git. If the pre-commit hook was not installed, that fake AWS key would be in your Git history permanently (even if you delete the line later, Git remembers).

### 3.2 — Generate Cosign keys

**Cosign** signs your Docker images with a cryptographic key. When you deploy to the cluster, Kyverno (Stage 4) can verify the signature and reject any image that was not signed by your pipeline. This prevents someone from pushing a malicious image to your Docker Hub and having the cluster run it.

```bash
# macOS: brew install cosign
# Linux: curl -O -L https://github.com/sigstore/cosign/releases/download/v2.2.4/cosign-linux-amd64 && chmod +x cosign-linux-amd64 && sudo mv cosign-linux-amd64 /usr/local/bin/cosign

cosign generate-key-pair   # enter a password when prompted
```

This creates two files: `cosign.key` (private, used by the pipeline to sign) and `cosign.pub` (public, used by Kyverno to verify).

Insert your public key into the Kyverno policy (replace the placeholder block in `infra/policies/require-signed-images.yaml` with the contents of `cosign.pub`).

Add secrets to GitHub (github.com/YOUR_USERNAME/clearledger → Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `COSIGN_PRIVATE_KEY` | Contents of `cosign.key` |
| `COSIGN_PASSWORD` | The password you entered when generating keys |

### 3.3 — Activate the full security pipeline

The security gates are already in `.github/workflows/ci.yaml`. Push any change to trigger the full pipeline:

```bash
git add . && git commit -m "ci: full DevSecOps pipeline" && git push origin main
```

### 3.4 — Break each gate on purpose

This is where the learning happens. You are going to deliberately introduce each type of vulnerability, watch the pipeline catch it, read the error message, then revert the change.

| Gate | How to trigger | What you see | Why this matters |
|---|---|---|---|
| Gitleaks | Add `AWS_KEY = "AKIAIOSFODNN7EXAMPLE"` to any Python file | Pipeline fails at Secrets Scan step | Leaked credentials are the #1 cause of cloud breaches |
| Trivy | Change `FROM python:3.12-slim` to `FROM python:3.8-slim` in any Dockerfile | Pipeline fails at image scan with a list of CVEs | Old base images contain known, exploitable vulnerabilities |
| Semgrep | Add `subprocess.run(request.args.get("cmd"), shell=True)` to any route | Pipeline fails at SAST step | This is a remote code execution vulnerability — an attacker could run any command on your server |
| Checkov | Remove `securityContext` from any deployment manifest | Pipeline fails at IaC scan | Without security context, the container runs as root with full privileges |

**For each gate:** push the change, watch the specific gate fail at github.com/YOUR_USERNAME/clearledger/actions, read the error message, understand what it caught, revert the change, push again, watch it go green.

**Take a screenshot of at least one pipeline failure showing a blocked security gate.** This is strong portfolio evidence — it shows you do not just set up security tools, you understand what they catch.

```bash
make check-3
```

### What you learned in Stage 3

- The difference between SAST, SCA, IaC scanning, image scanning, and secrets detection
- Why no single tool catches everything — each gate targets a different layer
- What pre-commit hooks are and why running checks locally + in CI is defense in depth
- What image signing proves and why it matters for supply chain security
- **The pattern:** deliberately break → read the error → understand it → fix it. This is how you build operational instinct.

---

## Stage 4 — Admission Control (Kyverno)

> Even if CI passes, the cluster can still refuse.

**Goal:** Kyverno intercepts every pod creation and rejects any that violate policy — before the container runtime ever sees them.

### What you need to know first

CI scanning catches problems before code is merged. But what if someone applies a manifest directly with `kubectl`? What if a Helm chart you installed creates pods that violate your security standards? CI never sees those.

**Admission control** is a checkpoint built into Kubernetes itself. Every time something tries to create or update a resource in the cluster, the request passes through admission webhooks before it takes effect. If a webhook rejects the request, the resource is never created.

**Kyverno** is a Kubernetes-native policy engine that uses those webhooks. You write policies as YAML files (not code), and Kyverno enforces them on every resource in the cluster. For example: "reject any pod that runs as root" or "require resource limits on every container."

The difference from CI: CI scans your code *before* it reaches the cluster. Kyverno enforces policy *at the cluster gate itself*. Together they create two layers of defense.

---

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update
helm install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace --set replicaCount=1
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=kyverno -n kyverno --timeout=120s
```

Apply all policies:

```bash
kubectl apply -f infra/policies/
kubectl get clusterpolicy   # all should show READY: True
```

**Watch Kyverno block a pod — this is the aha moment:**

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

Expected error:

```
Error from server: admission webhook "validate.kyverno.svc" denied the request:
Root containers are blocked in clearledger namespace.
```

The pod was never created. Kyverno intercepted the request and rejected it because the manifest did not specify `runAsNonRoot: true`. This is enforcement, not just detection — the pod does not exist.

**Take a screenshot of that error.** It is compliance evidence. It proves CIS Kubernetes Benchmark 5.2.6 is enforced — not just configured, enforced. Auditors care about the difference.

### 4.1 — Admission Control Exceptions

Kyverno blocks every pod that violates a policy. But what happens when a legitimate workload needs to bypass a specific rule?

PostgreSQL is the example. The official Postgres Alpine image uses a specific internal user (UID 70) to manage its data directory. The `disallow-root-containers` policy requires every pod to set `runAsNonRoot: true`. Postgres does set that — but if Kyverno is configured to also check specific UID ranges, or if the pod's security context does not satisfy the rule for any reason, Kyverno blocks it. The database cannot start, and the entire application fails.

You cannot weaken the policy cluster-wide to accommodate one database. That would let every pod bypass the rule. Instead, you create a **PolicyException** — a targeted exemption for exactly the pods that need it.

Open [`infra/policies/exceptions/postgres-root-exception.yaml`](../infra/policies/exceptions/postgres-root-exception.yaml) and read the comments. Here is what each section does:

**The `spec.exceptions` block** identifies which policy and rule to bypass:

```yaml
exceptions:
  - policyName: disallow-root-containers
    ruleNames:
      - check-runAsNonRoot
```

This says: "skip only the `check-runAsNonRoot` rule from the `disallow-root-containers` policy." Every other rule in that policy — and every other policy in the cluster — still enforces normally.

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

Only pods named `postgres-*` (matching `postgres-0`, `postgres-1`, etc.), only in the `clearledger` namespace, only for the `Pod` resource kind. Everything else in the cluster still follows the strict policy.

**The annotations** are documentation for your team and auditors:

```yaml
annotations:
  reason: "Postgres alpine image requires UID 70 for data directory ownership"
  approved-by: "platform-team"
  review-date: "2026-01-01"
```

- `reason` — why the exception exists
- `approved-by` — who authorised it
- `review-date` — when someone should revisit whether it is still needed

These have no technical effect — Kyverno ignores them. They exist so that six months from now, when someone asks "why does Postgres bypass this rule?", the answer is right there in the file. This is standard enterprise security practice.

**The rules for safe exceptions:**

1. **Scope narrowly** — target the exact resource that needs it, nothing more
2. **Commit to Git** — the exception is reviewed in a pull request, tracked in version history, and auditable
3. **Never weaken the policy itself** — the rule stays strict for everything else
4. **Review periodically** — exceptions should be temporary if possible, and re-evaluated on a schedule

Apply the exception only if Kyverno blocks your postgres pods:

```bash
kubectl apply -f infra/policies/exceptions/postgres-root-exception.yaml
```

Verify Kyverno still blocks other non-compliant pods:

```bash
# This should still be rejected — only postgres gets the exception
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

The exception allows Postgres through while everything else remains blocked. That is the principle: exceptions are small, controlled, auditable, and as temporary as possible.

```bash
make check-4
```

### What you learned in Stage 4

- The difference between CI scanning (before merge) and admission control (at the cluster gate)
- What Kyverno is: a policy engine that intercepts every Kubernetes API request
- That enforcement means the bad resource never exists — not "we detected it after the fact"
- How to write and apply cluster-wide security policies as YAML
- **Why both CI and admission control are needed:** CI catches problems in your code, Kyverno catches everything else that touches the cluster

---

## Stage 5 — Secrets Management (Vault)

> No credentials in Git. No credentials in etcd. Vault injects them at runtime.

**Goal:** delete the Kubernetes Secrets. The app keeps working. That is when secrets management clicks.

### What you need to know first

In Stage 0, you saw database passwords stored as base64-encoded strings in YAML files committed to Git. That is the default Kubernetes approach, and it has two problems:

1. **Anyone with repo access can read them.** base64 is encoding, not encryption. Run `echo "..." | base64 -d` and the password is in plaintext.
2. **Kubernetes stores Secrets in etcd unencrypted by default.** etcd is the cluster's database. Anyone with etcd access can read every Secret.

**HashiCorp Vault** is a dedicated secrets management system. Instead of storing credentials in YAML files, you store them in Vault. When a pod starts, a Vault agent sidecar (a small helper container) authenticates with Vault, retrieves the secrets, and writes them to a temporary file inside the pod. The secrets never exist in Git, never exist in etcd, and disappear when the pod stops.

**Vault agent injection** works through Kubernetes annotations on your deployment. You add annotations like `vault.hashicorp.com/agent-inject-secret-db-password: "clearledger/auth-service"`, and Vault's admission webhook adds the sidecar container automatically.

---

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
helm install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken="root-dev-token" \
  --set ui.enabled=true
```

Apply the Vault Ingress so your browser can reach the UI:

```bash
kubectl apply -f stages/stage-5-secrets-management/infra/vault-ingress.yaml
```

Open `http://vault.local` — token: `root-dev-token`.

Configure Vault, store secrets, and set up Kubernetes authentication:

```bash
bash stages/stage-5-secrets-management/infra/vault/setup.sh
```

**IMPORTANT — update through Git, not kubectl directly.** ArgoCD has `selfHeal: true`. Any direct `kubectl apply` is reverted within 3 minutes. All changes go through Git now.

```bash
cp stages/stage-5-secrets-management/infra/manifests/auth-service/deployment.yaml \
   infra/manifests/auth-service/deployment.yaml
cp stages/stage-5-secrets-management/infra/manifests/ledger-service/deployment.yaml \
   infra/manifests/ledger-service/deployment.yaml

# Push to infra repo — ArgoCD applies it
cd /tmp/clearledger-infra
git add manifests/ && git commit -m "feat: vault injection" && git push
cd -
```

Watch ArgoCD sync (2-3 minutes), then delete the K8s Secrets:

```bash
kubectl delete secret auth-service-secret -n clearledger
kubectl delete secret ledger-service-secret -n clearledger
```

**The aha moment:** run a login request — it still works:

```bash
curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' | jq .
```

Now check what secrets remain in the cluster:

```bash
kubectl get secret -n clearledger
```

The application-level secrets are gone. The credentials exist only in Vault, injected at pod startup as temporary files. Nothing in Git, nothing in etcd. **Take a screenshot** of the working login response next to the `kubectl get secret` output showing no app secrets.

```bash
make check-5
```

### What you learned in Stage 5

- Why Kubernetes Secrets are not real secrets management (base64 is not encryption, etcd stores them in plaintext)
- What Vault does: stores secrets centrally, injects them into pods at startup via sidecar containers
- How Vault agent injection works through deployment annotations
- That the app keeps working after deleting K8s Secrets — the credentials now come from Vault
- **The security improvement:** secrets are no longer in Git history, no longer in etcd, and disappear when the pod stops

---

## Stage 6 — Runtime Security (Falco)

> The pipeline secured what enters the cluster. Falco watches what happens inside.

**Goal:** exec into your own pod, trigger your own alert, find it in the Falco UI.

### What you need to know first

Everything up to this point catches problems *before* they reach a running container — CI scans code, Kyverno blocks bad manifests, Vault removes credentials from Git. But what happens when a container is compromised at runtime? An attacker who exploits a vulnerability in your app might:

- Open a shell inside the container
- Read sensitive files like `/etc/passwd` or `/etc/shadow`
- Download tools or malware
- Make unexpected network connections

None of those actions involve creating new Kubernetes resources, so Kyverno will not see them. They are not code changes, so CI will not see them. You need something that watches what happens *inside running containers*.

**Falco** is a runtime security tool that monitors system calls (syscalls) — the low-level operations every process uses to interact with the Linux kernel (opening files, spawning processes, making network connections). Falco uses **eBPF**, a Linux kernel technology that lets it observe syscalls with near-zero performance overhead, without modifying your containers.

You write rules like "alert if a shell process is spawned in any container in the clearledger namespace." Falco watches every syscall and fires an alert the moment it matches a rule.

**Network policies** complement Falco. While Falco detects suspicious activity, network policies *prevent* unauthorized network connections. They are Kubernetes firewall rules: "auth-service can talk to Postgres, but nothing else can."

---

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts && helm repo update
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true \
  --set tty=true
```

Apply the Falco Ingress so your browser can reach the UI:

```bash
kubectl apply -f stages/stage-6-runtime-security/infra/falco-ingress.yaml
```

Open `http://falco.local`.

Load custom rules and apply network policies:

```bash
kubectl apply -f stages/stage-6-runtime-security/infra/falco/clearledger-rules.yaml
kubectl apply -f stages/stage-6-runtime-security/infra/netpol/network-policies.yaml
```

**Trigger alerts on purpose — this simulates an attacker:**

```bash
# Scenario 1: shell in a running pod (an attacker gaining interactive access)
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- /bin/sh -c "id && exit"
```

Open `http://falco.local` — you should see: **CRITICAL: Shell spawned in ClearLedger container**

That alert tells you the exact pod, container, user, command, and timestamp. In a real environment, this would trigger an incident response process.

```bash
# Scenario 2: read a sensitive file (reconnaissance activity)
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- cat /etc/passwd
```

Falco fires: **CRITICAL: Sensitive file read in ClearLedger**

**Take screenshots of both alerts in the Falco UI.**

After applying network policies, verify ClearLedger still works (network policies restrict traffic but should not break legitimate communication):

```bash
curl -s http://clearledger.local/auth/health | jq .
curl -s http://clearledger.local/notifications/health | jq .
```

Both should return `{"status":"ok",...}`. If notification-service fails, check `kubectl get networkpolicy allow-notification-service -n clearledger`.

```bash
make check-6
```

### What you learned in Stage 6

- What runtime security catches that CI and admission control cannot: threats inside running containers
- What Falco is: a syscall monitoring tool that uses eBPF to watch every process in every container
- What network policies are: Kubernetes-level firewall rules that restrict which pods can talk to each other
- How to trigger and interpret security alerts — the exact skills you need for incident response
- **The security layers so far:** code scanning → admission control → secrets management → runtime detection. Each layer catches what the previous ones miss.

---

## Stage 6.5 — Chaos Engineering (Optional)

> Falco detects failures. Chaos engineering proves you survive them.

**Goal:** deliberately break parts of the system and verify it stays available. Detection is not the same as resilience.

### What you need to know first

You know the system can detect threats (Falco) and block bad deployments (Kyverno). But what happens when things fail? A pod crashes, the network gets slow, a node runs out of memory. Does the system recover automatically, or does it go down?

**Chaos engineering** answers that question by deliberately injecting failures into a running system and measuring the impact. If auth-service has two replicas and you kill one, does login still work? If ledger-service has 2 seconds of network latency, does the frontend timeout gracefully?

**LitmusChaos** is a Kubernetes-native chaos engineering platform. You define experiments as YAML (e.g. "kill one auth-service pod" or "inject 2 seconds of network delay to ledger-service") and Litmus executes them while you monitor the results.

---

```bash
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ && helm repo update
helm install chaos litmuschaos/litmus \
  --namespace litmus --create-namespace \
  -f stages/stage-6.5-chaos-engineering/infra/chaos/litmus-values.yaml
```

Run the experiments:

```bash
bash stages/stage-6.5-chaos-engineering/scripts/run-chaos.sh
```

The script runs three experiments:

| Experiment | What it does | What it proves |
|---|---|---|
| Pod kill | Kills one auth-service pod | Kubernetes restarts it, the second replica handles traffic during recovery |
| Network latency | Injects 2 seconds of delay into ledger-service | The frontend handles slow responses without crashing |
| Memory stress | Fills notification-service memory to 80% | The pod stays running and does not get OOM-killed at normal load |

After each experiment, the script verifies `http://clearledger.local/auth/health` returns 200.

```bash
make check-65
```

### What you learned in Stage 6.5

- The difference between detection (Falco sees a failure) and resilience (the system survives a failure)
- What chaos engineering is: deliberately injecting failures to verify recovery
- Why Kubernetes replicas matter — one pod dying does not mean downtime if another replica is serving traffic
- **An interview talking point:** "I ran chaos experiments against a live system and proved it survived pod failures, network latency, and memory pressure"

---

## Stage 7 — Security Observability

> Security you cannot measure you cannot prove.

**Goal:** every security signal from the previous stages feeds into six Grafana dashboards with real data.

### What you need to know first

You have security tools running: Falco detecting threats, Kyverno blocking bad deployments, ArgoCD tracking drift. But where do you see all of this in one place? How do you prove to an auditor that Falco caught 3 shell exec attempts last month, or that Kyverno blocked 12 root container attempts?

**Observability** is the practice of collecting, storing, and visualizing signals from your system. The monitoring stack in this stage has three components:

| Tool | What it does | Analogy |
|---|---|---|
| **Prometheus** | Collects metrics — numeric measurements over time (CPU usage, request count, error rate, Falco alert count) | A thermometer that takes readings every 15 seconds |
| **Loki** | Collects logs — text output from your applications and tools | A filing cabinet that stores every log line, searchable |
| **Grafana** | Visualizes metrics and logs on dashboards — charts, tables, alerts | The monitoring screen in a control room |

**ServiceMonitors** tell Prometheus where to scrape metrics from. Without a ServiceMonitor for ArgoCD, Prometheus does not know ArgoCD exists. Without one for Falco, Prometheus does not collect Falco alert counts. You are connecting the data sources to the collection system.

**DORA metrics** are four measurements that high-performing engineering teams track: deployment frequency, lead time for changes, change failure rate, and mean time to recovery. Google's research shows these metrics correlate strongly with organizational performance. You will see them on a dashboard.

---

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.hosts[0]=grafana.local \
  --set grafana.ingress.ingressClassName=nginx \
  --set grafana.adminPassword=admin123

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=5Gi
```

Enable metrics scraping from ArgoCD and Falco. ServiceMonitors tell Prometheus "go collect metrics from these services":

```bash
kubectl apply -f stages/stage-7-observability/infra/monitoring/argocd-servicemonitor.yaml
kubectl apply -f stages/stage-7-observability/infra/monitoring/falco-servicemonitor.yaml
kubectl apply -f stages/stage-7-observability/infra/monitoring/alerting-rules.yaml
```

Open `http://grafana.local` (admin / admin123). Add Loki as a data source so Grafana can query logs: Configuration → Data Sources → Add → Loki → URL: `http://loki:3100` → Save and Test.

**Import the dashboards** (Dashboards → Import → Upload JSON file):

| File | What it shows | Why it matters |
|---|---|---|
| `stages/stage-7-observability/infra/dashboards/01-security-event-timeline.json` | Falco alerts by priority and rule | See every security event across all pods in one view |
| `stages/stage-7-observability/infra/dashboards/02-kyverno-violations.json` | Policy violations per day, trend | Prove to auditors that policy enforcement is active and measured |
| `stages/stage-7-observability/infra/dashboards/03-service-health.json` | Request rate, error rate, failed logins | Detect availability and authentication issues in real time |
| `stages/stage-7-observability/infra/dashboards/04-compliance-posture.json` | Security posture at a glance | Single-pane compliance view for management and auditors |
| `stages/stage-7-observability/infra/dashboards/05-audit-log-analysis.json` | K8s API audit events | Who did what in the cluster and when |
| `stages/stage-7-observability/infra/dashboards/06-dora-metrics.json` | Deployment frequency, lead time, CFR, MTTR | Prove your DevOps process is improving over time |

**Generate real data on the dashboards:** go back to Stage 6 and exec into a pod again:

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- /bin/sh -c "id && exit"
```

Now open the Security Event Timeline dashboard. Find the Falco alert. The pod name, timestamp, and command are there. The system saw you.

**Take a screenshot of the Security Event Timeline with at least one alert.** This is powerful portfolio evidence — it shows end-to-end security observability.

```bash
make check-7
```

### What you learned in Stage 7

- The three components of observability: metrics (Prometheus), logs (Loki), dashboards (Grafana)
- What ServiceMonitors do: connect data sources to Prometheus
- What DORA metrics are and why they matter for engineering performance
- How to produce audit evidence — not just claims, but dashboards with real data
- **The full picture:** you can now see every security event, policy violation, and deployment across the entire system in one place

---

## Stage 7.5 — OpenTelemetry (Optional)

> Metrics show what happened. Traces show where time was spent and how services connected.

**Goal:** one transaction in Grafana Tempo shows spans across ledger-service → auth-service → postgres.

### What you need to know first

Metrics tell you "ledger-service had 50 requests in the last minute, 2 were errors." Logs tell you "request X failed with a 500 error." But neither tells you the full story of a single request: which services did it pass through, how long each step took, and where the bottleneck was.

**Distributed tracing** follows a single request across every service it touches. When a user creates a transaction, the request hits the frontend, goes to ledger-service, which calls auth-service to verify the JWT, then writes to Postgres. A **trace** captures that entire journey. Each step is a **span** — a named, timed operation. Spans nest inside each other, showing the call tree.

**OpenTelemetry (OTel)** is the standard for collecting traces. Your application code sends trace data to an **OTel Collector**, which forwards it to **Tempo** (a trace storage backend). Grafana queries Tempo and shows you the trace waterfall diagram.

---

```bash
kubectl apply -f stages/stage-7.5-opentelemetry/infra/otel/otel-collector.yaml

helm install tempo grafana/tempo \
  --namespace monitoring \
  --set tempo.storage.trace.backend=local \
  --set persistence.enabled=true \
  --set persistence.size=5Gi

kubectl apply -f stages/stage-7.5-opentelemetry/infra/otel/grafana-datasource-tempo.yaml
```

Update deployments with OTel environment variables (push through Git → ArgoCD syncs).

Then create a transaction and open Grafana → Explore → Tempo → search `service.name = "ledger-service"`. Expand the trace — you see the auth-service call and the Postgres INSERT as child spans with exact timing. That is a distributed trace.

**Take a screenshot of a trace showing spans across multiple services.** This demonstrates you understand microservice observability.

```bash
make check-75
```

### What you learned in Stage 7.5

- The difference between metrics (aggregates), logs (text), and traces (request journeys)
- What a span and a trace are: named, timed operations that show the path of a single request
- What OpenTelemetry does: a standard way to collect and forward traces
- How to find performance bottlenecks by looking at span durations in a trace waterfall

---

## Stage 8 — AWS Migration

> The architecture survives the migration because the contracts are portable.

**Goal:** the same application, the same security layers, running on AWS managed services instead of your laptop.

### What you need to know first

Everything you built in Stages 0–7 runs on a VM on your laptop. In production, you would use cloud-managed services: AWS EKS instead of MicroK8s, RDS instead of a Postgres container, ECR instead of Docker Hub, Secrets Manager or Vault on EC2 instead of dev-mode Vault.

The key insight: **the application code does not change.** The Dockerfiles, the FastAPI services, the CI pipeline logic — all identical. What changes is the infrastructure underneath. That is the point of containerization and Kubernetes — your app is portable because it does not depend on the underlying platform.

**Terraform** provisions the AWS resources. It reads `.tf` files that describe the desired infrastructure (VPC, subnets, EKS cluster, RDS database, etc.) and creates everything in your AWS account.

### Two OIDC Ideas in Stage 8

Stage 8 uses OIDC in two places. They sound similar, but they solve different problems:

- **GitHub Actions OIDC:** lets the pipeline push images to Amazon ECR without storing AWS access keys in GitHub.
- **IRSA:** lets pods inside EKS read AWS services, like Secrets Manager, without storing AWS access keys in Kubernetes.

Think of it this way:

```text
GitHub Actions OIDC
  GitHub job proves: "I am an approved job in the production environment of Osomudeya/clearledger"
  AWS replies: "Here are short-lived credentials to push images to ECR"

IRSA
  Kubernetes pod proves: "I am the auth-service ServiceAccount"
  AWS replies: "Here are short-lived credentials to read only the auth secret"
```

The important part is what is **not** stored anymore:

```text
No AWS_ACCESS_KEY_ID in GitHub Secrets
No AWS_SECRET_ACCESS_KEY in GitHub Secrets
No AWS keys inside Kubernetes Secrets
```

When Terraform runs, it creates a role called `clearledger-github-actions-ecr`. The Stage 8 pipeline in `.github/workflows/ci-aws.yaml` assumes that role using OIDC, logs in to ECR, pushes images, then updates `clearledger-infra` with ECR image URLs.

---

**Prerequisites:** AWS CLI configured (`aws sts get-caller-identity` returns your account), Terraform installed (`terraform --version`).

```bash
make aws-up   # provisions everything, ends by printing a URL
```

Terraform creates: VPC, EKS, ECR, RDS, ALB, Secrets Manager, GuardDuty, CloudTrail, VPC Flow Logs, IRSA roles, and the GitHub Actions OIDC role for ECR pushes. ArgoCD, Kyverno, and Falco install identically to the local setup.

After Terraform finishes, add the AWS pipeline values to GitHub:

```text
GitHub production environment secrets:
  GITHUB_ACTIONS_ROLE_ARN = terraform output github_actions_ecr_role_arn
  INFRA_REPO_TOKEN         = fine-grained token or GitHub App token for clearledger-infra

GitHub Variables:
  AWS_ACCOUNT_ID = your 12-digit AWS account ID
  AWS_REGION     = eu-west-1
```

Then run the Stage 8 workflow:

```text
GitHub → clearledger repo → Actions → CI — AWS (ECR + OIDC) → Run workflow
```

That workflow is the AWS version of the Stage 1 pipeline. It uses the same self-hosted runner, but pushes to ECR instead of Docker Hub.

Important: the two workflows are intentionally different:

| Workflow | When it runs | Registry | Target stage |
|---|---|---|---|
| `.github/workflows/ci.yaml` | Automatically on push to `main` | Docker Hub | Stages 1–7 local MicroK8s lab |
| `.github/workflows/ci-aws.yaml` | Manually from the Actions tab | Amazon ECR | Stage 8 AWS migration |

Why manual for AWS? Because AWS actions can create cost and affect a real cloud environment. You should choose when to run the AWS pipeline instead of triggering it during local MicroK8s testing.

### Production Hardening Checklist

The lab architecture is production-style, but a real production setup needs extra guardrails. Add these before you describe it as production-ready.

#### 1. Protect the main branches

Protect both GitHub repos:

```text
github.com/Osomudeya/clearledger
github.com/Osomudeya/clearledger-infra
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
→ Repository access: only Osomudeya/clearledger-infra
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

The Stage 8 Terraform does this in `iam.tf`:

```text
token.actions.githubusercontent.com:sub
= repo:Osomudeya/clearledger:environment:production
```

That means AWS only trusts GitHub jobs from the `production` environment. A random branch, fork, or unapproved workflow run cannot assume the ECR push role.

Important nuance: AWS IAM can reliably check the GitHub OIDC `aud` and `sub` claims. Use the protected GitHub environment and branch protection to control which workflow can reach that environment.

#### 5. Use staging to production promotion

The simplest lab flow is:

```text
main → build → update clearledger-infra → ArgoCD deploys
```

A production flow should be:

```text
main
  ↓
Build image once
  ↓
Deploy to staging
  ↓
Run smoke tests / DAST / manual approval
  ↓
Promote same image SHA to production
```

Do **not** rebuild for production. Promote the same image digest or SHA that passed staging.

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
clearledger-infra records desired state.
ArgoCD deploys from Git.
No SSH. No static AWS keys. No direct kubectl from CI.
```

Open the URL. ClearLedger is running on AWS. Same architecture, same security layers, new infrastructure.

**Destroy when done — this stops all charges:**

```bash
make aws-down
```

See `stages/stage-8-aws-migration/README.md` for the full walkthrough and cost reference.

### What you learned in Stage 8

- That containerized applications are portable — the same code runs on your laptop and on AWS
- What Terraform does: declares infrastructure as code so environments are reproducible
- What changes in a cloud migration (managed services, IAM, networking) and what does not (application code, CI logic, security policies)
- AWS-specific security services: GuardDuty (threat detection), CloudTrail (API audit), GitHub Actions OIDC (pipeline AWS auth without long-lived keys), and IRSA (pod-level IAM without long-lived credentials)

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
