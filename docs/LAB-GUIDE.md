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

**After every stage (authors and learners):** run the health check, then scan restart counts. A pod can be `Running` while crash-looping — high `RESTARTS` on platform pods (Kyverno, `hostpath-provisioner`, Prometheus operator) means the node is heading into a failure cascade. **Do not start the next stage until both checks look healthy.**

```bash
bash scripts/health-check.sh <stage>    # e.g. 4, 7, 7.5
```

The script ends with a **Platform stability** section. Also inspect the highest restart counts yourself:

```bash
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' \
  | tail -15
```

**Gate before the next stage:** platform pods (especially Kyverno controllers) should show **RESTARTS under 5** after the stage settles (~10 minutes). If any platform pod is climbing past 10, stop — fix it with the documented Helm values or troubleshooting steps. Do not `kubectl patch` around it.

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
$VMIP  litmus.local
EOF
```

Or run: `sudo bash scripts/setup-hosts.sh`

**Windows (PowerShell as Administrator):**

```powershell
$ip = "PASTE_VM_IP_HERE"
@(
  "$ip  clearledger.local",
  "$ip  argocd.local",     "$ip  grafana.local",
  "$ip  vault.local",      "$ip  falco.local",
  "$ip  litmus.local"
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

The runner uses Docker **inside the Ubuntu VM**, not Docker Desktop on your Mac. If a GitHub Actions job later fails with:

```text
permission denied while trying to connect to the Docker API at unix:///var/run/docker.sock
```

it usually means the runner process started before the `ubuntu` user picked up the `docker` group membership. Restart the runner inside the VM:

```bash
cd ~/actions-runner
pkill -f "Runner.Listener|Runner.Worker|./run.sh" || true
nohup ./run.sh > _diag/manual-runner.log 2>&1 &
docker ps
```

`docker ps` should run without `sudo`. That proves the runner user can build images in the VM.

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

**Do not copy** `infra/deferred-by-stage/` into `clearledger-infra`. That folder holds manifests for later stages (for example network policies for **Stage 6**) so ArgoCD does not apply them too early.

| Folder | Goes to `clearledger-infra`? | When it takes effect |
|---|---|---|
| `infra/manifests/` | **Yes** — Stage 1 push, ArgoCD from Stage 2 | App deployments, ingress, postgres, etc. |
| `infra/deferred-by-stage/` | **No** — stays in the `clearledger` repo only | Manual `kubectl apply` at the stage named in the path |

Stage 1 does not keep a separate copy of manifests inside `stages/stage-1-ci-pipeline/infra`. If that folder is empty or missing, that is expected. The GitOps source for this stage is:

```text
infra/manifests/          → clearledger-infra (ArgoCD)
infra/deferred-by-stage/  → apply later (see README there)
```

You copy `infra/manifests/` into the separate GitHub repo named `clearledger-infra`. That repo is the real Stage 1 infra target. The app repo stays focused on application code and pipeline logic; `clearledger-infra` becomes the desired-state repo that the pipeline updates after successful builds.

What you proved: the infrastructure definition has its own Git history, separate from application code.

### 1.4 — Set up GitHub Secrets

Go to: `github.com/YOUR_USERNAME/clearledger` → Settings → Secrets and variables → Actions → New repository secret

The workflow needs credentials for Docker Hub, GitHub, and image signing:

- Docker Hub, so it can push images.
- GitHub, so it can push image tag updates into `clearledger-infra`.
- Cosign, so it can sign the images after pushing them.

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

**Secrets 4 and 5 — `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD`**

Cosign signs container images after the pipeline pushes them to Docker Hub. Later, Stage 4 uses the public key with Kyverno so the cluster can verify that images came from your trusted pipeline.

Generate the key pair on your host machine, not inside the Multipass VM:

```bash
brew install cosign
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

On the self-hosted runner, images stay in the local Docker daemon between jobs (same VM, same daemon). That is why build and scan can be separate jobs without uploading multi-gigabyte tarballs — a lab shortcut that matches how a dedicated build VM works in production.

Stage 8 AWS (`ci-aws.yaml`) uses the same pattern on GitHub-hosted runners: `build-images` saves `images.tar` as an artifact, `scan-images` loads and scans it, `publish-images` loads and pushes to ECR.

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

#### GitOps manifest flow — three layers (read this once)

Do not confuse **app code**, **manifest templates**, and **what ArgoCD deploys**:

| Layer | Where | Who changes it |
|---|---|---|
| 1. Application code | `app/` in **clearledger** | You (developer) |
| 2. Canonical manifests | `infra/manifests/` in **clearledger** | You (Kubernetes YAML, probes, Vault, limits) |
| 3. GitOps desired state | **clearledger-infra** on GitHub | **CI** (after every successful build) |

```text
You edit infra/manifests/  +  push app code
        ↓
CI builds images → scans → publishes
        ↓
CI copies infra/manifests/ → clearledger-infra  (full tree, every deploy)
        ↓
CI updates image SHAs in kustomization.yaml only  (Kustomize — not sed)
        ↓
ArgoCD auto-syncs cluster to match Git
```

**Deployments never store the real registry tag.** They use a placeholder:

```yaml
# auth-service/deployment.yaml (canonical — same in both repos)
image: clearledger/auth-service:gitops
```

**Kustomize** maps that to the real image in `kustomization.yaml`:

```yaml
images:
  - name: clearledger/auth-service
    newName: docker.io/YOUR_USER/clearledger-auth-service
    newTag: d7bccf485dd06c319cabfebb310f52d872788a2f   # CI writes this SHA
```

ArgoCD renders `kustomize build` and applies the result. **Same pattern as Stage 8 AWS** — you learn it twice, not two different systems.

#### Lab vs larger prod — accurate comparison

| Piece | This lab (Stages 1–7) | Larger prod often adds |
|---|---|---|
| **Image tag updates** | Kustomize `images:` + `kustomize edit set image` in CI | Same — or Argo CD Image Updater / Flux Image Automation |
| **Manifest structure** | CI copies full `infra/manifests/` each deploy | Monorepo or infra repo with PR review on every change |
| **ArgoCD refresh** | `kubectl annotate` hard refresh (self-hosted runner) | Argo CD webhook, ApplicationSet, or Notifications |
| **Drift recovery** | `make fix-argocd` (break-glass; should be rare now) | Policy bots; drift should not happen with single source |

**Does Kustomize make learning harder?** No — you touch **one file** (`kustomization.yaml`) and **one CI step**. Deployments stay readable placeholders. Stage 8 reuses the same idea for ECR. Without Kustomize, the old `sed`-only approach caused **9-hour OutOfSync** bugs because CI updated image lines but not probes/limits.

#### Image tags — SHA now, digest later

| Approach | This lab | Prod teams often add later |
|---|---|---|
| **Git SHA tag** (`:abc123…`) | **Yes — primary tag** | Same — traceability anchor |
| **`:latest` or semver** (`:v1.2.3`) | No | Human-friendly pointer; CI moves `:latest` after scan passes |
| **Digest pinning** (`image@sha256:…`) | No | Strongest immutability — tag can be retagged, digest cannot |

The pipeline does **not** deploy to Kubernetes directly. It updates `clearledger-infra`. Stage 2 installs ArgoCD, and ArgoCD watches `clearledger-infra` to deploy the change.

| Section | What it does | Why |
|---|---|---|
| `on: push: branches: [main]` | Triggers on every push to main | Every change gets built automatically |
| `runs-on: [self-hosted, clearledger]` | Uses your local runner | Needed to reach the local cluster and Docker daemon |
| `prepare-scanners` | Installs scanner CLIs; downloads Trivy DB once per workflow | Avoids repeating ~95MB DB download per service |
| `build-images` | Builds all service images locally | Produces artifacts before any registry write |
| `scan-images` | Trivy + SBOM gates | Blocks publish if CVEs are found |
| `publish-images` | Docker Hub login + `ci-publish-image.sh` | Push and sign only after scan passes |
| `update-manifests` | Copies `infra/manifests/` + Kustomize image SHAs → clearledger-infra | Single source of truth; no manifest drift |

The Kubernetes Checkov scan in Stage 1 is evidence-only. It uploads findings so you can see the hardening work ahead, but it does not block the first CI pipeline run. That is intentional: Stage 1 proves the build-push-update flow. Later stages tighten Kubernetes policy with security gates, admission control, and secrets management.

DAST is also disabled by default in Stage 1. It needs a live deployed application, but Stage 1 only updates `clearledger-infra`; ArgoCD does not deploy that change until Stage 2. To enable DAST later, add a repository variable named `ENABLE_DAST` with value `true`.

#### Stage 1 security posture — strict vs evidence-only

Stage 1 is **not** “security turned off.” Some checks **block the pipeline**; others **run and upload evidence** so you can see what still needs work. This table is your reference — bookmark it and come back when you reach later stages.

| Check | Stage 1 behavior | Blocks pipeline? | Hardened in | What changes later |
|---|---|---|---|---|
| Gitleaks (secrets in Git) | Runs on full history | **Yes** | Stage 3 (break exercise) | You deliberately leak a secret and watch it fail |
| Semgrep (SAST) | Runs on Python services | **Yes** | Stage 3 (break exercise) | You inject unsafe code and watch SAST catch it |
| Checkov (Dockerfiles) | Scans production Dockerfiles | **Yes** | Stage 3 (break exercise) | Remove `HEALTHCHECK` and watch IaC fail |
| Checkov (Kubernetes manifests) | Scans `infra/manifests/` | **No — evidence only** | **Stage 4** | Kyverno enforces the same rules at the cluster gate |
| Trivy (image CVEs) | Blocks fixable HIGH/CRITICAL (`--ignore-unfixed`) | **Yes** | Stage 3 (break exercise) | Downgrade base image and watch scan fail |
| Grype (SBOM, auth-service) | Blocks fixable HIGH+ (`--only-fixed`) | **Yes** | Stage 3 | Same CVE story from a second scanner angle |
| Syft (SBOM generation) | Generates inventory | No | Stage 3 | Used for supply-chain evidence and Grype input |
| Cosign sign + SLSA attest | Runs after push | **No — non-blocking** | **Stage 4** | Kyverno rejects unsigned images at admission |
| DAST (OWASP ZAP) | Disabled unless `ENABLE_DAST=true` | N/A in Stage 1 | After Stage 2 deploy | Needs a live app URL to scan |
| Manifest update → Git | Updates `clearledger-infra` tags | **Yes** (must succeed) | Stage 2 | ArgoCD auto-syncs those tags to the cluster |

**Will you remember which stage hardens what?** Probably not from memory alone — that is normal. Use this table as the map:

| If Stage 1 left this loose… | Come back in… | You will… |
|---|---|---|
| Kubernetes Checkov findings (no `runAsNonRoot`, missing limits, etc.) | **Stage 4** | Install Kyverno; watch it **block** bad pods at admission |
| Cosign signing errors ignored / non-blocking | **Stage 4** | Configure `require-signed-images`; unsigned images **cannot deploy** |
| Passwords in Git / base64 K8s Secrets | **Stage 5** | Move credentials to Vault; secrets never live in YAML again |
| Nothing watches running containers | **Stage 6** | Falco detects shell exec, crypto mining, etc. at runtime |
| No central view of violations | **Stage 7** | Grafana dashboards show Kyverno blocks, Falco alerts, scan trends |

**How to make it stick (do not rely on memory):**

1. **Bookmark this section** — search the lab guide for “Stage 1 security posture”.
2. **In Stage 3**, do the “break each gate on purpose” exercises — that is where you learn what each tool catches.
3. **In Stage 4**, open the Checkov artifact from a Stage 1 run and compare it to what Kyverno now blocks. That connects “evidence” to “enforcement”.
4. Run `make check-3` and `make check-4` — they verify the hardening stages actually landed.

> **Design intent:** Stage 1 proves CI can build, scan, push, and update Git without you touching Docker manually. Stages 3–7 turn evidence into enforcement, runtime detection, and audit trails. Relaxations in Stage 1 are deliberate — not accidental weakening.

If a Stage 1 job fails, use `docs/troubleshooting.md#stage-1-ci-troubleshooting` before changing the workflow. It covers the failures this lab commonly exposes: runner label mismatch, Docker socket permissions, Docker Hub IPv6 connectivity, missing `pip`, Gitleaks demo secrets, Checkov behavior, Trivy install problems, real Python and frontend CVEs, Cosign download issues, Syft/Grype installs, wrong manifest image paths, and DAST being too early for Stage 1.

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

You may also see **DAST (OWASP ZAP + fintech API tests)** listed as **skipped** — that is expected. DAST is off until you set the repository variable `ENABLE_DAST` to `true` (after Stage 2, when the app is deployed and reachable). A skipped DAST job is not a failure.

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

### DevSecOps lesson — Stage 1 in one paragraph

**Automate the boring path first, and separate “built” from “deployed.”** Stage 1 turns `git push` into a repeatable factory: scan, build, sign, push images, then update **desired state** in `clearledger-infra` — not the cluster directly. That split is core DevSecOps: the pipeline produces **evidence** (scan reports, signed images, immutable tags tied to commit SHA) and records **intent** (which image *should* run) in Git. Security starts here too — some gates already block bad commits — but the deliberate lesson is operational: nobody SSHs to build, nobody runs `kubectl` to “deploy,” and when the infra repo changes but the cluster does not, you feel the **deployment gap** that Stage 2 closes. CI automates *building*; GitOps (next) automates *applying*.

---

## Stage 2 — GitOps with ArgoCD

> **Git is truth.** The infra repo says what *should* run. **ArgoCD** keeps the cluster matching that and fixes drift on its own.

**Goal:** Install ArgoCD so it watches `clearledger-infra` and deploys to the cluster. CI still only updates Git; it never runs `kubectl`.

### What you need to know first

**The gap from Stage 1:** CI already builds images and updates `clearledger-infra`. The cluster did not change until someone ran `kubectl`. This stage closes that last step.

| Who | Job |
|---|---|
| **CI** (Stage 1) | Build → scan → push images → update image tags in `clearledger-infra` |
| **ArgoCD** (Stage 2) | Watch `clearledger-infra` → apply manifests → cluster runs what Git says |

```text
push code → CI updates clearledger-infra → ArgoCD syncs cluster
```

**GitOps** means the infra repo is the official record of what should run, not “whatever the cluster happens to have.” **ArgoCD** is the controller inside Kubernetes that enforces that: new commit in Git → deploy; manual `kubectl` change → reverted back to Git.

| Question | Answer |
|---|---|
| Who deployed what? | Git history in `clearledger-infra` |
| What should be running? | Whatever the manifests in Git say |
| Roll back? | Revert the commit in the infra repo |
| Someone changed the cluster by hand? | ArgoCD undoes it (you will prove this below) |

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

Configure Argo CD for NGINX ingress (TLS at ingress, HTTP to the server — fixes `503` / `ERR_TOO_MANY_REDIRECTS` on `/api/v1/stream/*`):

```bash
kubectl apply -f stages/stage-2-gitops/infra/argocd-cmd-params.yaml
kubectl apply -f stages/stage-2-gitops/infra/argocd-ingress.yaml
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
```

**Expected in `argocd-cmd-params-cm`:** `server.insecure: "true"`, `server.grpc.web: "true"`, `server.url: https://argocd.local`

Apply the ArgoCD Ingress (HTTP backend on port 80 — do **not** use `ssl-passthrough`):

```bash
kubectl apply -f stages/stage-2-gitops/infra/argocd-ingress.yaml
```

Open **`https://argocd.local`** in a **private/incognito** window (clears stale tokens that cause `401 Unauthorized`). Login: `admin` / the password from the command above. Accept the browser certificate warning (self-signed).

**Expected:** After login, the Applications page loads with **no** red `401` or `ERR_HTTP2_PROTOCOL_ERROR` lines in the browser console (F12 → Console). If you still see them, see [troubleshooting.md — ArgoCD](troubleshooting.md#argocd-ui-401-or-err_http2_protocol_error).

Connect ArgoCD to the infra repo and apply the Application manifest:

```bash
# Install the ArgoCD CLI first
# macOS: brew install argocd
# Linux: curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && chmod +x argocd && sudo mv argocd /usr/local/bin/

argocd login argocd.local --username admin --password YOUR_PASSWORD --insecure --grpc-web

# Connect ArgoCD to the infra repo on GitHub
# Public repo: no credentials needed
# Private repo: use your INFRA_REPO_TOKEN PAT
argocd repo add https://github.com/YOUR_USERNAME/clearledger-infra.git

# Update the repo URL in the Application manifest before applying
sed -i '' "s|YOUR_USERNAME|$(git config user.name)|g" \
  stages/stage-2-gitops/argocd/clearledger-app.yaml

kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
argocd app sync clearledger --grpc-web
```

Confirm ArgoCD is watching **all** manifest folders (not only ingress):

```bash
argocd app resources clearledger --grpc-web | grep Deployment
```

You should see `auth-service`, `ledger-service`, `frontend`, and the other app Deployments. ArgoCD renders `manifests/kustomization.yaml`, which lists every resource under `manifests/` — not just `ingress.yaml` at the top level.

### If the UI shows red pods or "Progressing" (read this before the screenshot)

This is a common first-sync surprise, not a broken install.

**Three statuses, three meanings:**

| What you see | Plain English |
|---|---|
| **Synced** | Git and the cluster agree on *what should exist* |
| **Progressing** | ArgoCD is still waiting for pods to become ready |
| **Red pod / 0/1** | A new pod is crashing or failing its health check |

You can be **Synced** and **Progressing** at the same time: manifests applied, but not every pod is healthy yet.

**Why it happens in Stage 2**

Network policies belong to **Stage 6** (runtime security). They live in `infra/deferred-by-stage/stage-6-runtime-security/netpol/` in this repo — **not** in `infra/manifests/`.

If `manifests/netpol/` is still in your **`clearledger-infra`** repo on GitHub (from an older copy of the lab), ArgoCD will keep applying it. Those policies use **default-deny** and break DNS for new pods, so you see red **0/1** pods and **Progressing** health.

**Fix for Stage 2**

Do **both** steps. Deleting only in the cluster is not enough — ArgoCD recreates policies from Git on the next sync.

**Step 1 — remove from `clearledger-infra` on GitHub**

Delete the folder `manifests/netpol/` → commit: `chore: defer network policies to Stage 6`.

**Step 2 — sync and restart**

```bash
argocd app sync clearledger --grpc-web
kubectl delete networkpolicy -n clearledger --all   # safe once Git no longer has netpol
kubectl rollout restart deployment/auth-service deployment/ledger-service -n clearledger
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
```

Network policies stay in **`clearledger`** under `infra/deferred-by-stage/` until you apply them in Stage 6.

When that looks good, continue below.

---

When sync finishes and health is **Healthy**, you should see the **clearledger** app in the UI with green **Healthy** and **Synced** badges — repo pointing at your `clearledger-infra` repo on `main`, path `manifests`, namespace `clearledger`. Open the app tile and the resource tree should show deployments, services, and ingresses reconciled with no red pods.

From the CLI, `argocd app get clearledger` should echo the same story: `Sync Status: Synced`, `Health Status: Healthy`, and each resource listed as synced.

### ArgoCD stuck OutOfSync (break-glass fix)

**Normal path:** CI copies full manifests + updates Kustomize tags → ArgoCD auto-syncs within ~3 minutes.

**If still OutOfSync after 10+ minutes:**

```bash
make fix-argocd
```

This re-syncs canonical manifests to `clearledger-infra` (Kustomize SHAs preserved), re-applies the Application, and triggers a hard refresh. **Do not** `kubectl apply` deployments — fix Git, let ArgoCD sync.

```bash
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web --prune
kubectl get application clearledger -n argocd -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
```

**Take a screenshot of that view** — the app tile or the resource tree is fine. That’s your portfolio proof that GitOps is actually running.

**Prove the contract — this is the aha moment:**

The point is **not** to change Git. `kubectl set image` only changes what is running in the cluster. ArgoCD compares the cluster to `clearledger-infra`; if they differ, it shows **OutOfSync** and `selfHeal` puts the cluster back to match Git.

Before you run the demo, confirm the app is **Healthy** (not **Progressing**) and that Deployments are managed — see the red-pods section above if not.

```bash
argocd app resources clearledger --grpc-web | grep Deployment
```

```bash
# Manually change the image in the cluster only (Git stays the same)
kubectl set image deployment/auth-service \
  auth-service=$DOCKER_USERNAME/clearledger-auth-service:fake-tag \
  -n clearledger

# ArgoCD should flip to OutOfSync within a minute or two
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"

# Wait for selfHeal (default sync interval is ~3 minutes)
sleep 180

# Cluster image should match clearledger-infra again — Git was never edited
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

The image is back to the Git version. The cluster self-corrected without anyone editing the infra repo. That is GitOps: Git is the contract, ArgoCD enforces it on the cluster.

```bash
make check-2
```

---

### Rolling back a bad deploy

> You just proved that ArgoCD reverts unauthorized cluster changes. Now flip it: **what if you pushed a bad commit yourself?** GitOps rollback is not a button — it is a git operation. This section explains why, shows you both methods, and has you practise each one before you need them under pressure.

#### How you know you need to roll back

These symptoms appearing within minutes of a push to `clearledger-infra` point at a bad commit:

- Pods stuck in `CrashLoopBackOff` or `Error` — check with `kubectl get pods -n clearledger`
- `kubectl logs <pod> -n clearledger --previous` shows startup errors that were not there before
- ArgoCD health flips from `Healthy` to `Degraded` or stays on `Progressing` — check with `argocd app get clearledger --grpc-web`
- The app returns 5xx errors or login stops working — check with `curl -I http://clearledger.local/health`

If you see any of these within minutes of a push, assume the latest commit is the cause and roll back first — investigate second.

---

#### Why ArgoCD rollback is not just a button

ArgoCD has a rollback button in the UI and an `argocd app rollback` command. Both work — but only if you understand the interaction with `selfHeal`.

Your Application (`stages/stage-2-gitops/argocd/clearledger-app.yaml`) is configured with:

```yaml
syncPolicy:
  automated:
    selfHeal: true
```

`selfHeal: true` means ArgoCD continuously compares the cluster to Git. If they differ, it re-syncs the cluster back to match Git automatically. If you click the rollback button without disabling auto-sync first, ArgoCD will detect that the cluster no longer matches `HEAD` and silently undo your rollback within 3 minutes. You will think you rolled back. You did not.

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
- `selfHeal` works *with* you — the new `HEAD` is already the reverted state, nothing fights you
- Full audit trail — Git shows the bad deploy, the revert, and who did both
- No cluster commands needed — ArgoCD applies everything
- Compliant — regulators and on-call engineers can read exactly what happened from Git history alone

---

#### Method 2 — Emergency ArgoCD rollback (when the cluster is on fire)

Use this when the cluster is broken right now and you do not have time to push a Git fix. It pins the cluster to a previous known-good deployment immediately. You will still fix Git afterward — this is a stabilise-first step, not a permanent fix.

**When to use:** Incident in progress. Pods are crashing, users are affected, and you need the cluster back to a known-good state in under 30 seconds.

> **Before you start:** confirm your ArgoCD CLI session is still valid. If it expired, re-login first — an expired session will silently fail every command below.
> ```bash
> argocd account get-user-info --grpc-web
> # If you see "Unauthenticated", re-login:
> ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
>   -o jsonpath="{.data.password}" | base64 -d)
> argocd login argocd.local --username admin --password "$ARGOCD_PASSWORD" \
>   --insecure --grpc-web
> ```

**Step 1 — Disable auto-sync** (critical — skip this and selfHeal will undo your rollback within 3 minutes)

```bash
argocd app set clearledger --sync-policy none --grpc-web
# Confirm: automated sync is now off
argocd app get clearledger --grpc-web | grep "Sync Policy"
# Expected: Sync Policy: <none>
```

**Step 2 — Find the last known-good deployment ID**

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

**Step 3 — Roll back to the known-good ID**

```bash
argocd app rollback clearledger 8 --grpc-web
```

**Step 4 — Confirm the cluster is stable**

```bash
kubectl get pods -n clearledger
# All pods should be Running

argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
# Sync Status:   OutOfSync  ← expected — cluster is at rev 8, Git is still at the bad HEAD
# Health Status: Healthy    ← this is what matters right now
```

`OutOfSync` is correct and expected at this point. The cluster is running the old known-good revision. Git still has the bad commit — you will fix that next.

**Step 5 — Fix Git (do not leave it broken)**

```bash
cd ~/clearledger-infra
git pull
git revert <bad-commit-sha> --no-edit
git push
```

**Step 6 — Re-enable auto-sync**

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

> **Never leave auto-sync disabled longer than the incident.** It is your drift-detection and tamper-evidence mechanism — without it, unauthorized `kubectl` changes go undetected. Re-enable it the moment you push the Git fix.

---

#### Practise the rollback now (before you need it under pressure)

Do not wait for a real incident to run this for the first time. The steps below simulate a bad image tag deploy and walk you through Method 1 (the preferred path).

**Step 1 — Push a bad image tag to `clearledger-infra`**

```bash
cd ~/clearledger-infra
git pull

# Edit manifests/notification-service/deployment.yaml
# Change the image tag to a tag that does not exist, e.g.:
#   image: docker.io/veeno/clearledger-notification-service:broken-tag

# Commit and push it
git add manifests/notification-service/deployment.yaml
git commit -m "test: simulate bad deploy with nonexistent image tag"
git push
```

**Step 2 — Watch ArgoCD sync the bad state**

```bash
# Give ArgoCD ~3 minutes to pick it up, or trigger immediately:
argocd app sync clearledger --grpc-web

# Watch the notification-service pod fail
kubectl get pods -n clearledger -w
# You will see: notification-service pod stuck in ImagePullBackOff or ErrImagePull
```

**Step 3 — Roll back using Method 1**

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

**Step 4 — Verify**

```bash
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
# Expected: Sync Status: Synced, Health Status: Healthy

kubectl get pods -n clearledger
# All pods Running, no ImagePullBackOff
```

You have now practised a rollback end-to-end. The `git revert` commit is permanently in the infra repo's history — a real audit record of a simulated recovery.

---

#### Quick reference

**Use Method 1 (git revert) when:**
- A bad image tag or manifest was pushed to `clearledger-infra` and you have a few minutes
- Any config change in the infra repo caused pods to break
- This is almost always the right answer — it is fast, safe, and leaves a clean audit trail

**Use Method 2 (emergency ArgoCD rollback) when:**
- The cluster is broken right now, users are affected, and you need it stable in under 30 seconds
- You are not yet sure which commit caused the problem and need time to investigate — roll back to stabilise, then use `git log` to find the culprit, then fix forward with Method 1

**Neither method applies when:**
- A pod is crashing but nothing was pushed to the infra repo recently — this is not a rollback problem. Check `kubectl logs`, Vault connectivity, and network policies instead.

`revisionHistoryLimit: 10` in `stages/stage-2-gitops/argocd/clearledger-app.yaml` means ArgoCD always has 10 previous deployments available for emergency rollback. Increase it if your release cadence is high.

---

### What you learned in Stage 2

- What GitOps means: Git is the single source of truth, and a tool enforces it
- What ArgoCD does: watches Git, compares it to the cluster, corrects drift automatically
- How the full flow works now: push code → CI builds image → CI updates infra repo → ArgoCD syncs cluster
- **No one runs `kubectl` to deploy anymore.** The pipeline updates Git, ArgoCD does the rest.
- **How to roll back safely:** `git revert` in the infra repo is the correct answer; ArgoCD emergency rollback is the break-glass option, and you must disable auto-sync first or selfHeal will silently undo it

### DevSecOps lesson — Stage 2 in one paragraph

**Git is the contract; the controller enforces it.** Stage 1 wrote *what should run* into `clearledger-infra`. Stage 2 installs a reconciler — ArgoCD — that continuously compares the cluster to that repo and fixes drift. Manual `kubectl set image` does not change Git; it only changes the live cluster, and `selfHeal` puts the cluster back. That is the DevSecOps/GitOps payoff: deployments are **auditable** (Git history), **repeatable** (revert a commit to roll back), and **tamper-evident** (unauthorized cluster edits get reverted). The full chain is now push → CI updates infra Git → ArgoCD syncs cluster — still no human deploy step. Stage 3 adds security gates on the CI side; Stage 4 adds a cluster gate for anything that tries to skip them.

---

## Stage 3 — Security Gates

> Every commit passes through security checks. The gates that protect the build artifact stop the pipeline; Kubernetes hardening findings become enforcement later.

**Goal:** six security tools scan every commit. Each one catches a different category of vulnerability. Some findings block immediately, such as secrets, SAST, vulnerable images, and production Dockerfile issues. Kubernetes manifest findings are collected first, then become deployment enforcement in Stage 4 with Kyverno. You will deliberately trigger each category to see exactly what it catches and why it matters.

> **Reminder:** Stage 1 already ran most of these tools — some in blocking mode, some as evidence only. See [Stage 1 security posture — strict vs evidence-only](#stage-1-security-posture--strict-vs-evidence-only) for the full map of what was relaxed in Stage 1 and which later stage tightens it.

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

No single tool covers everything. That is why you need all six. In Stage 1, Kubernetes Checkov runs as evidence so the first CI lesson stays focused on build-push-update. In Stage 3 and Stage 4, those findings become the security story: CI tells you what is wrong, and admission control prevents bad manifests from running.

**Pre-commit hooks** run these checks on your laptop *before* the commit even reaches Git. The CI pipeline runs them again on the server. This is defense in depth — two chances to catch a problem.

---

### 3.1 — Install pre-commit hooks

```bash
# macOS (Homebrew — avoids PEP 668 "externally-managed-environment" from pip3):
brew install pre-commit

# Linux / venv (if pip3 works on your system):
# python3 -m venv .venv && source .venv/bin/activate
# pip install pre-commit

pre-commit install
pre-commit run --all-files
```

If some hooks fail on first run, see [Stage 3 README — expected failures at Stage 3](../stages/stage-3-security-gates/README.md#pre-commit-run---all-files--expected-failures-at-stage-3). **Gitleaks and Ruff must pass** — YAML/Terraform issues on later-stage files are OK until you reach those stages.

Test it catches secrets locally before CI does:

```bash
echo 'AWS_SECRET = "'$(printf '%s%s' 'AKIA' 'IOSFODNN7EXAMPLE')'"' >> app/auth-service/main.py
git add app/auth-service/main.py && git commit -m "test"
# Gitleaks fires and blocks the commit — see "What you should see" below
git restore --staged app/auth-service/main.py
git checkout app/auth-service/main.py
```

The commit was blocked before it even reached Git. If the pre-commit hook was not installed, that fake AWS key would be in your Git history permanently (even if you delete the line later, Git remembers).

> **Already did Cosign in Stage 1?** That counts. Stage 3 does not require regenerating keys — confirm `infra/cosign.pub` exists and GitHub has `COSIGN_PRIVATE_KEY` + `COSIGN_PASSWORD`. Stage 4 turns signing into **enforcement** at the cluster gate.

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

This is where the learning happens. For each gate: **inject the bad change → run or push → read the failure → revert → confirm green again.**

Use **local dry-run** commands first (fast feedback). Then push to CI for portfolio screenshots at `github.com/YOUR_USERNAME/clearledger/actions`.

**Pattern for every gate:**

```bash
# 1. Break it (edit file)
# 2. Test locally OR push to main
# 3. Read the failure (terminal or GitHub Actions log)
# 4. Revert
git checkout -- path/to/file
# 5. Confirm clean
pre-commit run --all-files   # local
git push origin main           # CI green again
```

---

#### Gate 1 — Gitleaks (secrets)

**Inject:** hardcoded AWS key in any Python file.

```bash
echo 'AWS_KEY = "'$(printf '%s%s' 'AKIA' 'IOSFODNN7EXAMPLE')'"' >> app/auth-service/main.py
git add app/auth-service/main.py && git commit -m "test: trigger gitleaks"
```

**Done looks like (terminal — pre-commit):**

```text
🔑 Secrets scan (Gitleaks)...............................................Failed
- hook id: gitleaks
- exit code: 1

Finding:     AWS_KEY = "REDACTED"
RuleID:      aws-access-token
File:        app/auth-service/main.py
Line:        316
```

**Done looks like (CI — job `Secrets Scan (Gitleaks)`):** red ✗ on workflow; log contains `leaks found: 1` and the file path. **Build jobs do not start** — pipeline stops here.

**Revert:**

```bash
git restore --staged app/auth-service/main.py 2>/dev/null
git checkout app/auth-service/main.py
pre-commit run gitleaks --all-files   # → Passed
```

---

#### Gate 2 — Semgrep (SAST)

**Inject:** command injection via `shell=True` (remote code execution if deployed).

```bash
# Add inside any route in app/auth-service/main.py (temporary test):
#   subprocess.run(request.query_params.get("cmd"), shell=True)
```

Or dry-run on a throwaway file:

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

**Done looks like (terminal or CI job `SAST (Semgrep)`):**

```text
❯❱ python.lang.security.audit.subprocess-shell-true.subprocess-shell-true
          ❰❰ Blocking ❱❱
          Found 'subprocess' function 'run' with 'shell=True'. ...
```

Exit code **1**. CI: `SAST (Semgrep)` job red ✗; `Build + Scan` jobs **skipped** (they `need: sast`).

**Revert:** remove the injected lines; `git checkout app/auth-service/main.py`

---

#### Gate 3 — Checkov (IaC / Dockerfile)

**Inject:** remove `HEALTHCHECK` from a production Dockerfile (two lines at the bottom of `app/auth-service/Dockerfile`).

```bash
# Dry-run: copy Dockerfile without HEALTHCHECK, scan locally
python3 -m venv /tmp/sec-gates-venv && /tmp/sec-gates-venv/bin/pip install checkov
sed '/^HEALTHCHECK/,+1d' app/auth-service/Dockerfile > /tmp/Dockerfile-nohc
mkdir -p /tmp/checkov-demo/app/auth-service
cp /tmp/Dockerfile-nohc /tmp/checkov-demo/app/auth-service/Dockerfile
/tmp/sec-gates-venv/bin/checkov --directory /tmp/checkov-demo --framework dockerfile
```

**Done looks like (terminal or CI job `IaC Scan (Checkov)` → Scan Dockerfiles step):**

```text
Check: CKV_DOCKER_2: "Ensure that HEALTHCHECK instructions have been added to container images"
	FAILED for resource: /app/auth-service/Dockerfile.
...
Passed checks: 42, Failed checks: 1, Skipped checks: 0
```

Download artifact **`checkov-results`** → `checkov-dockerfile-results.json` for the full report.

> **Note:** CI uses `--hard-fail-on HIGH,CRITICAL`. Some Dockerfile checks (including missing HEALTHCHECK) may appear as **FAILED** in the log but rate below HIGH — you still learn to read Checkov output. For a louder finding, add `EXPOSE 22` instead → **CKV_DOCKER_1** (port 22 exposed).

**To break in CI:** edit `app/auth-service/Dockerfile`, commit, push; open Actions → `IaC Scan (Checkov)`.

**Revert:**

```bash
git checkout app/auth-service/Dockerfile
```

---

#### Gate 4 — Trivy (image CVEs)

**Inject:** older base image in `app/auth-service/Dockerfile`:

```bash
sed -i '' 's/FROM python:3.12-slim/FROM python:3.8-slim/' app/auth-service/Dockerfile
```

**Dry-run (no full build — scan the base image directly):**

```bash
trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed python:3.8-slim
```

**Done looks like (terminal or CI job `Build + Scan auth-service` → Trivy step):**

```text
│ setuptools (METADATA) │ CVE-2024-6345  │ HIGH     │ fixed  │ 57.5.0 │ 70.0.0 │ ...
│                       │ Remote code execution via download functions ...
```

Exit code **1**. Report Summary shows **37** vulnerabilities on `python:3.8-slim`. CI: `Build + Scan auth-service` red ✗; **`update-manifests` does not run** — cluster image tag unchanged.

**Revert:**

```bash
git checkout app/auth-service/Dockerfile
```

---

#### Summary — what “gate broken” looks like in GitHub Actions

| Gate | Failed job name | Pipeline stops? | Key log phrase |
|---|---|---|---|
| Gitleaks | `Secrets Scan (Gitleaks)` | Yes — first gate | `leaks found: 1` |
| Semgrep | `SAST (Semgrep)` | Yes — no builds | `subprocess-shell-true` or `Blocking` |
| Checkov | `IaC Scan (Checkov)` | Yes — no builds | `CKV_DOCKER_2` or `Failed checks:` |
| Trivy | `Build + Scan auth-service` | Yes — no manifest update | `CVE-` + `HIGH` / `CRITICAL` |

After each test: **revert, push, confirm all jobs green.**

**Take a screenshot of at least one red job** — portfolio evidence that you triggered and understood a security gate.

```bash
make check-3
```

### What you should see — terminal vs GitHub Actions

Stage 3 uses **two places** to catch problems. Know which to look at:

| Where | When | What runs |
|---|---|---|
| **Your terminal** (pre-commit) | Every `git commit` on your laptop | Gitleaks, Ruff, Hadolint, etc. |
| **GitHub Actions** (CI) | Every push to `main` | Full pipeline: Gitleaks, Semgrep, Checkov, Trivy, Grype, Cosign |

**Local secrets test — success looks like this in the terminal:**

```text
🔑 Secrets scan (Gitleaks)...............................................Failed
- hook id: gitleaks
- exit code: 1

Finding:     AWS_SECRET = "REDACTED"
RuleID:      aws-access-token
File:        app/auth-service/main.py
Line:        316
```

What that means:

- **`Failed`** on the Gitleaks hook — the gate worked
- **`exit code: 1`** — commit was **not** created (no new commit hash)
- **`RuleID: aws-access-token`** — which rule caught it
- Other hooks may show `Passed` or `Skipped` — that is fine

After you revert the test line, confirm clean:

```bash
pre-commit run --all-files
# Gitleaks ................................ Passed
```

**CI gate failures — look on GitHub, not only the terminal:**

Push a deliberate bad change (§3.4), then open `github.com/YOUR_USERNAME/clearledger/actions`. Each gate fails in its own job:

| Gate | Failed job name (approx.) | What to read in the log |
|---|---|---|
| Gitleaks | Secrets Scan | `leaks found`, file + line |
| Semgrep | SAST | rule id, vulnerable code path |
| Checkov | IaC Scan | policy id, Dockerfile or manifest path |
| Trivy / Grype | Build + Scan * | CVE list, severity HIGH/CRITICAL |

Revert the bad change, push again, watch the workflow go **green**.

### Stage 3 complete — done checklist (move to Stage 4)

You are **done with Stage 3** when all of these are true:

| # | Check | How to verify |
|---|---|---|
| 1 | Pre-commit installed | `pre-commit install` ran; hooks run on commit |
| 2 | Local secrets gate works | Fake AWS key **blocks** commit in terminal (see above) |
| 3 | Cosign ready | `infra/cosign.pub` exists; GitHub secrets `COSIGN_*` set (Stage 1 is fine) |
| 4 | Pipeline has all gates | `make check-3` lists gitleaks, semgrep, checkov, trivy, cosign |
| 5 | Health check green | `make check-3` ends with **`All checks passed. Ready for the next stage.`** |

**Recommended for portfolio (optional, not required to proceed):**

- Screenshot of **one** blocked gate — terminal Gitleaks output **or** a red GitHub Actions job
- Break at least one other gate in CI (Trivy, Semgrep, or Checkov) using §3.4, then revert

**What Stage 3 does *not* require yet:**

- Kubernetes Checkov findings blocking the pipeline (evidence only until **Stage 4**)
- Cosign **blocking** deploys (non-blocking until **Stage 4** Kyverno)
- DAST / ZAP (needs live app; optional later)

**What “move to Stage 4” means:** CI scans code and images before they reach GitOps. Stage 4 adds **admission control** — Kyverno rejects bad pods and unsigned images **inside the cluster**, even if someone bypasses CI with `kubectl`. Run `make check-4` after Stage 4.

### What you learned in Stage 3

- The difference between SAST, SCA, IaC scanning, image scanning, and secrets detection
- Why no single tool catches everything — each gate targets a different layer
- What pre-commit hooks are and why running checks locally + in CI is defense in depth
- What image signing proves and why it matters for supply chain security
- **The pattern:** deliberately break → read the error → understand it → fix it. This is how you build operational instinct.

### DevSecOps lesson — Stage 3 in one paragraph

**Security is not a final review before release — it is a pipeline.** In Stage 2, any commit could reach the cluster through GitOps. Stage 3 adds automated gates that **fail fast**: secrets never enter git, vulnerable code and images never get tagged for deploy, and every artifact is signed so you can prove where it came from. No single scanner sees everything — Gitleaks, Semgrep, Checkov, and Trivy each guard a different layer — so **defense in depth** means stacking tools, not picking one. Pre-commit on your laptop plus CI on push is the same idea twice: catch problems **before** they become incidents. Stage 3 secures the **path into production**; Stage 4 secures the **cluster door** for anything that tries to bypass that path.

---

## Stage 4 — Admission Control (Kyverno)

> Even if CI passes, the cluster can still refuse.

**Goal:** Kyverno intercepts every pod creation and rejects any that violate policy — before the container runtime ever sees them.

> **This is where Stage 1 evidence becomes enforcement.** Kubernetes Checkov findings that did not block CI in Stage 1 now stop bad pods at the cluster gate. Cosign signing that was non-blocking in Stage 1 is now required for deployment. See [Stage 1 security posture — strict vs evidence-only](#stage-1-security-posture--strict-vs-evidence-only).

### What you need to know first

CI scanning catches problems before code is merged. But what if someone applies a manifest directly with `kubectl`? What if a Helm chart you installed creates pods that violate your security standards? CI never sees those.

**Admission control** is a checkpoint built into Kubernetes itself. Every time something tries to create or update a resource in the cluster, the request passes through admission webhooks before it takes effect. If a webhook rejects the request, the resource is never created.

**Kyverno** is a Kubernetes-native policy engine that uses those webhooks. You write policies as YAML files (not code), and Kyverno enforces them on every resource in the cluster. For example: "reject any pod that runs as root" or "require resource limits on every container."

The difference from CI: CI scans your code *before* it reaches the cluster. Kyverno enforces policy *at the cluster gate itself*. Together they create two layers of defense.

| Policy | What it enforces | Framework |
|---|---|---|
| `disallow-root-containers` | `runAsNonRoot: true` | CIS K8s 5.2.6 |
| `require-resource-limits` | CPU/memory requests and limits | CIS K8s 5.2.4 |
| `disallow-privilege-escalation` | `allowPrivilegeEscalation: false` | CIS K8s 5.2.5 |
| `drop-all-capabilities` | `capabilities.drop: [ALL]` | CIS K8s 5.2.7 |
| `require-signed-images` | Cosign signature on ClearLedger images | SLSA Level 2 |

All policy files live in `infra/policies/`. Kyverno itself is installed via Helm using `stages/stage-4-admission-control/infra/kyverno/values.yaml`.

If install, policies, break-it scenarios, or `make check-4` fail, use [troubleshooting.md — Stage 4](troubleshooting.md#stage-4-admission-control-troubleshooting) before changing Helm charts or policy YAML.

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

1. **Disables cleanup CronJobs** — older Kyverno charts pull `bitnami/kubectl`, which was removed from Docker Hub and causes `ImagePullBackOff` on cleanup pods.
2. **Points Helm hooks at `bitnamilegacy/kubectl`** — so future `helm uninstall` does not hang on a missing image.
3. **Extends liveness probe timeouts** — the default `timeoutSeconds: 5, failureThreshold: 2` is too tight for a loaded single-node VM. Under CPU pressure the health endpoint can take >5s to respond, which triggers a restart cascade that saturates the node and makes the API server intermittently unreachable. The values file sets `timeoutSeconds: 30, failureThreshold: 5` so Kyverno survives load spikes without crash-looping.

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

If pods stay in `ContainerCreating` for a long time, the node is still pulling images from `ghcr.io/kyverno`. Wait — do not start a second Helm install on top of a partial one.

**Stability gate — run before §4.2:**

```bash
bash scripts/health-check.sh 4
```

All four Kyverno controllers should be `1/1 Running` with **RESTARTS 0–2** (not climbing). If restarts keep increasing, the node is likely under CPU pressure and Kyverno’s health probes are killing pods — confirm you installed with `stages/stage-4-admission-control/infra/kyverno/values.yaml` (extended probe timeouts). See `docs/troubleshooting.md` §Stage 4.

---

### 4.2 — Confirm your Cosign public key is in the policy

Stage 3 created `infra/cosign.pub`. Kyverno uses that key to verify image signatures at admission time.

```bash
cat infra/cosign.pub
grep -A5 "publicKeys" infra/policies/require-signed-images.yaml
```

The policy ships with a placeholder — you **must** paste your key before applying. Open `infra/policies/require-signed-images.yaml`, replace `PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE` with the full contents of `infra/cosign.pub` (including the `-----BEGIN PUBLIC KEY-----` lines):

```yaml
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                      -----END PUBLIC KEY-----
```

Your key will differ from the example above — it must match the key your CI uses to sign images in Stage 3.

---

### 4.3 — Apply the five core policies

Apply the five policies that map to CIS controls. **Do not** apply `verify-slsa-provenance.yaml` yet — it is an optional SLSA attestation policy (Audit mode) for a later enhancement.

The `require-signed-images` policy includes `failurePolicy: Fail` and `webhookTimeoutSeconds: 30` — without these, Kyverno may allow pods through when signature verification cannot reach the registry.

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

Each scenario removes or violates one control. Read the denial message — it names the policy, the rule, and the field that failed. That message is audit evidence.

| Scenario | What you simulate | Policy under test | Success looks like |
|---|---|---|---|
| 1 | Attacker applies a bare pod (no hardening) | Root, caps, privilege, limits | Four policies fire; pod `NotFound` |
| 2 | Developer fixes securityContext but forgets limits | Resource limits only | One policy fires; pod `NotFound` |
| 3 | Attacker pushes unsigned image to Docker Hub | Cosign signature | `require-signed-images` denies; pod `NotFound` |

---

#### Scenario 1 — root container (no securityContext)

**What you are simulating:** Someone with `kubectl` access bypasses CI and applies a minimal pod — no `securityContext`, no resource limits. This is exactly what Stage 1 Checkov flagged as evidence; Stage 4 now **blocks** it.

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

- `validate.kyverno.svc-fail denied the request` — the API server rejected the create; nothing was stored in etcd as a running pod.
- Four separate policies each list a **rule name** and the **JSON path** that failed (`/spec/containers/0/securityContext/` etc.).
- One sloppy manifest hits four CIS-aligned controls at once — that is defense in depth.

**Verify enforcement worked:**

```bash
kubectl get pod root-test -n clearledger
# Error from server (NotFound): pods "root-test" not found
```

If you see a pod in `Running` or `Pending`, policies are not enforcing — re-check `kubectl get clusterpolicy` shows all five `READY: True`.

**Take a screenshot.** This is portfolio evidence for CIS Kubernetes Benchmark 5.2.6 — enforced, not just configured.

---

#### Scenario 2 — missing resource limits

**What you are simulating:** A developer who read the securityContext requirements and fixed root/caps/privilege — but skipped resource limits. Common in real teams: “we hardened the container” but forgot CPU/memory bounds.

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

**How to read this output:**

- Only **one** policy appears this time — the earlier securityContext fields satisfied the other four rules.
- The failure path `/spec/containers/0/resources/limits/` tells you exactly what to add to fix the manifest.
- Compare this denial to Scenario 1: same webhook, fewer policies — Kyverno evaluates each rule independently.

**Verify:**

```bash
kubectl get pod nolimits-test -n clearledger
# Error from server (NotFound): pods "nolimits-test" not found
```

---

#### Scenario 3 — unsigned ClearLedger image

**What you are simulating:** A supply-chain attack — someone pushes a malicious image to Docker Hub under your repo name (`clearledger-auth-service`) without going through your signed CI pipeline. Stage 3 made Cosign signing possible; Stage 4 makes it **mandatory** at the cluster gate.

**Why this scenario needs setup:** Kyverno verifies signatures against the **registry**, not your local machine. The image tag must **exist on Docker Hub**. A fake tag like `:unsigned` that was never pushed causes `ImagePullBackOff` after admission — that looks like a broken deploy, not a security block.

**Step 1 — push a deliberately unsigned test image** (one-time):

```bash
export DOCKER_USERNAME=your-dockerhub-username   # e.g. veeno

docker pull nginx:alpine
docker tag nginx:alpine ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
docker push ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test

# Must fail — proves the image has no Cosign signature from your pipeline key:
cosign verify --key infra/cosign.pub \
  index.docker.io/${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
# Error: no signatures found
```

**Step 2 — try to deploy it with a compliant pod spec:**

The pod manifest is fully hardened (securityContext + limits) so **only** the signature policy can fail. Use `index.docker.io/` in the image URL — on Kyverno 1.12, `docker.io/...` may not trigger `verifyImages` matching.

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
  verify-cosign-signature: 'failed to verify image index.docker.io/veeno/clearledger-auth-service:unsigned-test:
    .attestors[0].entries[0].keys: no signatures found'
```

**How to read this output:**

- Note the webhook name is `mutate.kyverno.svc-fail`, not `validate` — image verification runs in Kyverno’s mutate pass (digest + signature check) before the pod is admitted.
- `no signatures found` means Kyverno reached Docker Hub, found the image, and confirmed it was **not** signed with your `infra/cosign.pub` key.
- The pod never exists — the attacker cannot get a shell even if the image is pullable.

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

**Contrast — signed image is allowed:**

When the image **is** signed by your pipeline and the pod spec is compliant, admission succeeds:

```bash
# Your deployed tag (signed in CI) — should start if spec is compliant:
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# docker.io/veeno/clearledger-auth-service:v0.1.0
```

Existing Deployments synced before policies existed keep running. New pods using your signed tags pass verification.

**Take a screenshot of the Scenario 3 denial** — it proves supply-chain enforcement, not just CI signing.

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

ArgoCD should still show **Synced** and **Healthy** — GitOps and admission control work together, not against each other.

---

### 4.6 — Policy exceptions (when a legitimate workload needs a bypass)

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

These have no technical effect — Kyverno ignores them. They exist so that six months from now, when someone asks "why does Postgres bypass this rule?", the answer is right there in the file.

**The rules for safe exceptions:**

1. **Scope narrowly** — target the exact resource that needs it, nothing more
2. **Commit to Git** — the exception is reviewed in a pull request, tracked in version history, and auditable
3. **Never weaken the policy itself** — the rule stays strict for everything else
4. **Review periodically** — exceptions should be temporary if possible, and re-evaluated on a schedule

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

Kyverno enforces *what workloads* are allowed to run. **kube-bench** audits *how the cluster itself is configured* against the CIS Kubernetes Benchmark. These are two different layers — both matter for compliance evidence.

```bash
bash stages/stage-4-admission-control/scripts/run-kube-bench.sh
```

This applies a Job, waits for completion, saves JSON to `stages/stage-4-admission-control/scripts/kube-bench-report.json`, and compares against the committed baseline. On MicroK8s you will see WARN/FAIL items for flags under `/var/snap/microk8s/current/args/` — see [stage-4 README](../stages/stage-4-admission-control/README.md#48--prove-your-cluster-passes-cis-benchmark) for fixes.

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

If kube-bench reports regressions, run the script manually and update the baseline after reviewing — that diff is audit evidence.

If Kyverno install, policies, break-it scenarios, or `make check-4` fail, see [troubleshooting.md — Stage 4](troubleshooting.md#stage-4-admission-control-troubleshooting).

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

**Recommended for portfolio (optional):**

- Screenshot of Kyverno blocking a root pod (§4.4 Scenario 1)
- Screenshot of unsigned-image denial (§4.4 Scenario 3)
- Screenshot of `kubectl get clusterpolicy` showing five `Enforce` policies

**What Stage 4 does *not* require yet:**

- `verify-slsa-provenance.yaml` (optional SLSA attestation — Audit mode, enable later)
- Vault / runtime secrets (Stage 5)
- Network policies (Stage 6)

**What “move to Stage 5” means:** Pods are hardened and images are signed, but database passwords still live in Kubernetes Secrets committed to Git. Stage 5 moves credentials into Vault.

### What you learned in Stage 4

- The difference between CI scanning (before merge) and admission control (at the cluster gate)
- What Kyverno is: a policy engine that intercepts every Kubernetes API request
- That enforcement means the bad resource never exists — not "we detected it after the fact"
- How to read a Kyverno denial: policy name → rule name → JSON path that failed
- How to write and apply cluster-wide security policies as YAML
- How to scope a PolicyException without weakening the policy for everyone else
- That operational issues (Helm, image pulls, registry URL format) affect whether controls actually fire
- **Why both CI and admission control are needed:** CI catches problems in your code; Kyverno catches everything else that touches the cluster

### DevSecOps lesson — Stage 4

**CI is the front door; admission control is the bouncer.** Stage 3 proved your pipeline signs images and scans manifests — but anyone with `kubectl apply` could bypass all of it. Kyverno closes that gap: every pod creation is evaluated against CIS-aligned policies before it runs. Checkov findings that were evidence-only in Stage 1 are now live enforcement. Cosign signatures that were non-blocking in Stage 1 are now required at deploy time.

**Evidence beats configuration.** An auditor does not care that you *have* a policy file in Git — they care that a non-compliant pod is rejected when someone tries to create it. The break-it scenarios produce that evidence: a terminal error naming the policy, the rule, and the failed field. Screenshot those denials. They prove CIS 5.2.x and supply-chain controls are **enforced**, not just documented.

**Defense in depth has a order.** CI → GitOps → admission control are three gates on the same path. Each catches what the previous one misses: CI never sees a manual `kubectl apply`; GitOps does not validate image signatures; Kyverno does not scan source code. Stacking all three is normal in regulated environments — no single gate is enough.

---

## Stage 5 — Secrets Management (Vault)

> No credentials in Git. No credentials in etcd. Vault injects them at runtime.

**Goal:** delete the Kubernetes app Secrets. The app keeps working. That is when secrets management clicks.

### What you need to know first

In Stage 0, you saw database passwords stored as base64-encoded strings in YAML files committed to Git. That is the default Kubernetes approach, and it has two problems:

1. **Anyone with repo access can read them.** base64 is encoding, not encryption.
2. **Kubernetes stores Secrets in etcd unencrypted by default.**

**HashiCorp Vault** holds credentials centrally. A **Vault agent** sidecar authenticates with Vault using the pod’s Kubernetes service account, reads KV secrets, and writes files under `/vault/secrets/`. The app reads those files — nothing is in Git or in `secretKeyRef` after migration.

**Where secrets live after Stage 5:**

| Location | App DB URL / JWT |
|---|---|
| Git / `clearledger-infra` | **No** |
| Kubernetes `auth-service-secret` | **No** (deleted after migration) |
| Vault KV `clearledger/data/auth-service` | **Yes** (source of truth) |
| Pod filesystem `/vault/secrets/*` | **Yes** (injected at runtime, ephemeral) |

Bootstrap values for the lab go in a **gitignored `.env`** file once — then into Vault with `seed-vault-secrets.sh`. They are **not** hardcoded in `setup.sh` or any committed file.

**Order matters — do not skip steps:**

```text
.env → install Vault → setup.sh → seed-vault-secrets.sh → push clearledger-infra → wait for 2/2 pods → delete K8s app Secrets
```

If you GitOps-sync Vault deployments **before** Vault is installed and seeded, auth/ledger pods will fail until Vault is ready and KV paths exist.

---

### 5.1 — Create `.env` (local only, never commit)

```bash
cp stages/stage-5-secrets-management/.env.example \
   stages/stage-5-secrets-management/.env
```

Edit `.env`:

1. **`VAULT_TOKEN`** — choose a dev root token (same value you pass to Helm in §5.2).
2. **`SEED_*`** — one-time values loaded **into Vault** (must match Postgres password + JWT so login still works after you delete K8s Secrets).

**Copy from existing K8s Secrets** (after Stages 0–4):

```bash
kubectl get secret auth-service-secret -n clearledger \
  -o jsonpath='{.data.database_url}' | base64 -d; echo
kubectl get secret auth-service-secret -n clearledger \
  -o jsonpath='{.data.jwt_secret}' | base64 -d; echo
kubectl get secret ledger-service-secret -n clearledger \
  -o jsonpath='{.data.database_url}' | base64 -d; echo
```

Paste into `.env` as `SEED_AUTH_DATABASE_URL`, `SEED_AUTH_JWT_SECRET`, `SEED_LEDGER_DATABASE_URL`.

**If `auth-service-secret` is already gone** (you deleted too early):

```bash
# Build database URL from Postgres bootstrap secret (default lab password: changeme-stage0)
PG_PASS=$(kubectl get secret postgres-secret -n clearledger \
  -o jsonpath='{.data.password}' | base64 -d)
echo "postgresql://clearledger:${PG_PASS}@postgres:5432/clearledger"

# JWT: use the same value you used at Stage 0, or read from Vault if already seeded:
kubectl exec -n vault vault-0 -- vault kv get -field=jwt_secret clearledger/auth-service 2>/dev/null \
  || echo "(set SEED_AUTH_JWT_SECRET manually — must match tokens already issued)"
```

**Example `.env` shape** (values are yours — never commit this file):

```text
VAULT_TOKEN=my-dev-root-token
SEED_AUTH_DATABASE_URL=postgresql://clearledger:changeme-stage0@postgres:5432/clearledger
SEED_AUTH_JWT_SECRET=stage0-jwt-secret-change-in-production
SEED_LEDGER_DATABASE_URL=postgresql://clearledger:changeme-stage0@postgres:5432/clearledger
```

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

**Expected — Vault pods:**

```text
NAME                                   READY   STATUS    RESTARTS   AGE
vault-0                                1/1     Running   0          1m
vault-agent-injector-8d6b668b4-xxxxx   1/1     Running   0          1m
```

**If `helm install` fails with “cannot re-use a name”** — Vault is already installed; use the `helm upgrade --install` block above.

---

### 5.3 — Configure Vault (platform + seed KV)

```bash
bash stages/stage-5-secrets-management/infra/vault/setup.sh
bash stages/stage-5-secrets-management/infra/vault/seed-vault-secrets.sh
```

| Script | Does | Does **not** |
|---|---|---|
| `setup.sh` | K8s auth, KV mount, policies, roles | Store app passwords in Git |
| `seed-vault-secrets.sh` | `vault kv put` from `.env` `SEED_*` | Print secret values |

Both scripts read **`VAULT_TOKEN` from `.env` only**.

**Expected — `setup.sh` (tail):**

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

**Expected — `seed-vault-secrets.sh`:**

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

Re-running `setup.sh` / `seed-vault-secrets.sh` is safe (idempotent for the lab).

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

ArgoCD watches **`clearledger-infra`**, not this app repo. Stage 5 must land there:

1. Vault-enabled `deployment.yaml` for **auth** and **ledger**.
2. **Delete** `manifests/auth-service/secret.yaml` and `manifests/ledger-service/secret.yaml` from the **infra repo**.

**First push of Stage 5 to your infra repo:**

```bash
# Copy stage-5 deployments into this repo’s infra/ (edit DOCKER_USERNAME → your Docker Hub user)
cp stages/stage-5-secrets-management/infra/manifests/auth-service/deployment.yaml \
   infra/manifests/auth-service/deployment.yaml
cp stages/stage-5-secrets-management/infra/manifests/ledger-service/deployment.yaml \
   infra/manifests/ledger-service/deployment.yaml
# sed -i '' 's/DOCKER_USERNAME/your-dockerhub-user/g' infra/manifests/auth-service/deployment.yaml
# sed -i '' 's/DOCKER_USERNAME/your-dockerhub-user/g' infra/manifests/ledger-service/deployment.yaml

git clone https://github.com/YOUR_USERNAME/clearledger-infra.git /tmp/clearledger-infra
cp infra/manifests/auth-service/deployment.yaml /tmp/clearledger-infra/manifests/auth-service/
cp infra/manifests/ledger-service/deployment.yaml /tmp/clearledger-infra/manifests/ledger-service/
rm -f /tmp/clearledger-infra/manifests/auth-service/secret.yaml
rm -f /tmp/clearledger-infra/manifests/ledger-service/secret.yaml

cd /tmp/clearledger-infra
git add -A
git status
git commit -m "feat(stage-5): Vault injection; remove app secrets from GitOps"
git push
cd -
```

**Expected — `git status` before commit:**

```text
modified:   manifests/auth-service/deployment.yaml
modified:   manifests/ledger-service/deployment.yaml
deleted:    manifests/auth-service/secret.yaml
deleted:    manifests/ledger-service/secret.yaml
```

**If your infra repo already has Stage 5** (nothing to commit), verify ArgoCD only:

```bash
kubectl get application clearledger -n argocd \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
# sync=Synced health=Healthy
```

If **OutOfSync**, hard-refresh and sync:

```bash
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web --prune
```

Wait until:

```bash
kubectl get application clearledger -n argocd \
  -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# Synced Healthy
```

**Do not `kubectl apply` deployments** if ArgoCD manages the cluster — `selfHeal` reverts manual changes. Git is the contract (Stage 2).

**Common rollout failures:**

| Symptom | Fix |
|---|---|
| `Duplicate value: "vault-secrets"` | Do **not** declare a `vault-secrets` volume in `deployment.yaml` — the injector creates it |
| `Service appeared 2 times` | Keep `Service` only in `service.yaml`, not at the bottom of `deployment.yaml` |
| Kyverno `containers/0` `runAsNonRoot` | Add `runAsNonRoot: true` on the **app** container `securityContext`, not only on `spec.securityContext` |
| Pods stuck `1/1` (no sidecar) | Confirm `injector.enabled=true` and deployment has `vault.hashicorp.com/agent-inject: "true"` |
| `permission denied` in vault-agent-init | Run `setup.sh` — K8s auth role not bound to service account |

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

**Expected — secrets remaining:**

```bash
kubectl get secret -n clearledger
```

```text
NAME              TYPE     DATA   AGE
postgres-secret   Opaque   2      6d
```

`postgres-secret` is **Postgres bootstrap only** — not app credentials. That stays until you harden Postgres separately.

**If delete says `NotFound`** — secrets were already removed. Continue to §5.6.

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

If Vault injection or ArgoCD sync fails, see [troubleshooting.md — Vault Issues](troubleshooting.md#vault-issues).

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

**Recommended for portfolio (optional):**

- Screenshot: login JSON beside `kubectl get secret -n clearledger` (only `postgres-secret` left)
- Screenshot: auth pod `2/2` with Vault sidecar
- Screenshot: Vault UI signed in (token from `.env`, not pasted in Git)

**What Stage 5 does *not* require yet:**

- Moving `postgres-secret` into Vault (Postgres bootstrap — optional hardening later)
- Production Vault HA / auto-unseal (dev mode is intentional for the lab)
- Falco / runtime detection (**Stage 6**)

**What “move to Stage 6” means:** Credentials are out of Git and etcd, but a compromised pod can still read `/vault/secrets/*` at runtime. Stage 6 adds Falco to detect that.

### What you learned in Stage 5

- Why Kubernetes Secrets are not secret management (encoding ≠ encryption; etcd exposure)
- That **Vault KV** is the source of truth; `.env` is a one-time bootstrap channel, never committed
- How Vault agent injection works via deployment annotations and service account JWT
- That GitOps must drop `secret.yaml` from **`clearledger-infra`**, not only from the app repo
- That **order matters**: Vault ready → seed KV → GitOps → healthy pods → delete K8s Secrets
- **The security improvement:** app credentials are not in Git, not in etcd as K8s Secrets, and disappear when the pod stops

### DevSecOps lesson — Stage 5

**Secrets belong in a vault, not in YAML.** Stage 4 hardened *what runs*; Stage 5 removes *what attackers find in Git and etcd*. The migration pattern is: configure Vault → seed KV from a local `.env` once → deploy via GitOps without `secret.yaml` → delete K8s app Secrets → prove the app still works. Operational scripts configure the platform; they do not embed credentials. Rotation becomes updating Vault and letting the agent refresh files — not editing manifests in Git.

---

## Stage 6 — Runtime Security (Falco)

> The pipeline secured what enters the cluster. Falco watches what happens inside.

**Goal:** Understand what runtime security *detects* and *why* — then prove it by triggering an alert and reading it like an operator would.

This stage is not “install Falco and move on.” You are learning a **gap in the stack**: everything before Stage 6 secures **what gets deployed**; Falco secures **what running software actually does**. That is the same problem space as incident response, forensics, and zero-trust — not just another Helm chart.

### What you need to know first

Everything up to this point catches problems *before* they reach a running container — CI scans code, Kyverno blocks bad manifests, Vault removes credentials from Git. But what happens when a container is compromised at runtime? An attacker who exploits a vulnerability in your app might:

- Open a shell inside the container
- Read sensitive files like `/etc/passwd` or `/etc/shadow`
- Download tools or malware
- Make unexpected network connections

None of those actions involve creating new Kubernetes resources, so Kyverno will not see them. They are not code changes, so CI will not see them. You need something that watches what happens *inside running containers*.

**Falco** is a runtime security tool that monitors system calls (syscalls) — the low-level operations every process uses to interact with the Linux kernel (opening files, spawning processes, making network connections). Falco uses **eBPF**, a Linux kernel technology that lets it observe syscalls with near-zero performance overhead, without modifying your containers.

**Network policies** complement Falco: Falco *detects* suspicious activity; network policies *block* unauthorized pod-to-pod traffic. Apply them **only in Stage 6** — before Vault and GitOps are stable they break DNS and legitimate traffic. Manifests: `infra/deferred-by-stage/stage-6-runtime-security/netpol/` (not in `clearledger-infra` until you choose).

**Order matters:**

```text
Install Falco → custom rules → ingress → break-it scenarios → network policies → verify app still works
```

### How Stage 6 fits the full stack (Stages 1–6)

Each earlier stage guards a **different moment**. Stage 6 is the first that watches **inside a running pod**:

| Stage | Layer | When it acts | Example threat it catches |
|---|---|---|---|
| **3 — CI gates** | Before merge / build | `git push` | Secret in code, CVE in image, bad Dockerfile |
| **4 — Kyverno** | Pod creation (admission) | `kubectl apply` / ArgoCD sync | Root container, unsigned image, no limits |
| **5 — Vault** | Secret storage & injection | Pod startup | Password in Git or etcd; credentials only in Vault KV |
| **6 — Falco** | **Inside the running container** | After pod is Running | Shell spawn, read `/etc/passwd`, wget at runtime |
| **6 — NetworkPolicy** | Pod-to-pod traffic | Every connection | ledger → notification direct call **blocked** |

```text
git push
  → [Stage 3: Gitleaks, Trivy, Cosign …]     ← code & image
  → [Stage 1–2: CI updates infra → ArgoCD]     ← desired state
  → [Stage 4: Kyverno admission]               ← bad manifest never runs
  → Pod starts
  → [Stage 5: Vault agent injects secrets]     ← no creds in YAML
  → App running
  → [Stage 6: Falco eBPF] watches syscalls     ← NEW: in-container behavior
  → [Stage 6: NetworkPolicy] filters traffic   ← NEW: east-west firewall
```

**Beginner takeaway:** Kyverno asked “Is this pod *allowed to be created*?” Falco asks “What is this pod *doing right now*?” Network policies ask “Who is this pod *allowed to talk to*?” All three are needed.

**What Stage 6 does *not* replace:** Falco does not scan source code (Stage 3) or block bad manifests at create time (Stage 4). If you skip Stages 3–5, Falco still alerts — but you already shipped vulnerable code, unsigned images, and secrets in Git.

---

### 6.1 — Install Falco and Falcosidekick UI

```bash
bash stages/stage-6-runtime-security/scripts/install-falco.sh
```

This runs `helm upgrade --install` with `modern_ebpf`, enables Falcosidekick + Web UI, enables the **k8s-metacollector** (`collectors.kubernetes.enabled: true`) so custom rules can match `k8smeta.ns.name = clearledger`, loads rules from `infra/falco/clearledger-rules-content.yaml`, applies the rules ConfigMap and ingress.

**If Falco is already installed**, the script is safe to re-run (upgrade).

**Expected — Falco pods:**

```text
NAME                                      READY   STATUS    RESTARTS   AGE
falco-w4fh6                               2/2     Running   0          2m
falco-falcosidekick-...                   1/1     Running   0          2m
falco-falcosidekick-ui-...                1/1     Running   0          2m
falco-falcosidekick-ui-redis-0            1/1     Running   0          2m
```

Open **`http://falco.local`** — Falcosidekick UI. Log in with the chart defaults:

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

#### Reading the Falcosidekick UI (first login)

After login you land on the **Events** tab — a table of Falco detections from the last 24 hours. The UI can look busy even before you run any break-it scenario. Use this guide so you know what matters.

**1. Know the columns**

| Column | What to read |
|---|---|
| **Time** | When it happened — newest at top after refresh |
| **Priority** | How serious Falco rated it (see below) |
| **Rule** | The detection name — this is the headline |
| **Output** | One-line detail: process, file, connection, pod name |
| **Tags** (right) | Extra context — look for `clearledger` on lab alerts |

**2. Priority levels (focus top-down)**

| Priority | Meaning in this lab |
|---|---|
| **Critical** | Act on these first — shell spawn, sensitive file read, vault secrets tampering |
| **Warning** | Suspicious but not always malicious — outbound connections, package managers |
| **Notice** / **Info** | Often **background noise** — not what the break-it scenarios target |

**3. Background noise vs alerts you caused**

Right after install you may already see events such as **Contact K8S API Server From Container** with process `argocd-application-controller` and priority **Notice**. That is **normal**: ArgoCD pods talk to the Kubernetes API continuously. You did not break anything.

**Ignore for Stage 6 demos:**

- Rules whose **Output** mentions `argocd`, `kube-system`, or `falco` namespace pods
- **Notice**-level stock Falco rules you did not trigger on purpose

**Look for after you run §6.2 (demo) or §6.3 (manual scenarios)** (custom ClearLedger rules):

| Rule name | Priority | You triggered it by… |
|---|---|---|
| **Shell Spawned in ClearLedger Container** | Critical | `kubectl exec … /bin/sh` (Scenario 1) |
| **Sensitive File Read in ClearLedger** | Critical | `kubectl exec … cat /etc/passwd` (Scenario 2) |
| **Package Manager Executed in ClearLedger Container** | Warning | `wget` / `curl` in exec (Scenario 3) |
| **Unexpected Outbound Connection from ClearLedger** | Warning | Outbound call from app container (Scenario 3) |
| **Unauthorized Write to Vault Secrets Directory** | Critical | Writing to `/vault/secrets` (advanced) |

Custom rules include the tag **`clearledger`** in the Tags column. If you filter or scan for that tag, lab alerts stand out from cluster baseline noise.

**4. Simple workflow (do this once)**

1. Open **`http://falco.local`** and log in (`admin` / `admin`).
2. Note any existing **Notice** events — baseline only; do not chase them yet.
3. Run **`make demo-6`** (§6.2) or **Scenario 1** from §6.3 in your terminal.
4. Wait **5–10 seconds**, then **refresh** the Events page.
5. Find a new row: **Priority = Critical**, **Rule = Shell Spawned in ClearLedger Container**, **Output** contains `auth-service` and your pod name.
6. Expand or read **Output** — it should show `cmd=sh -c id && exit` (proof Falco saw the exec).

**5. If you only see Notice / ArgoCD events**

- Confirm you ran the exec with **`-c auth-service`** (not the vault-agent sidecar).
- Confirm custom rules loaded: `schema validation: ok` in Falco logs (command below).
- Try Falco pod logs if the UI is slow: `kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50`

**6. What “good” looks like for the portfolio**

Screenshot a **Critical** row for **Shell Spawned in ClearLedger Container** or **Sensitive File Read in ClearLedger** — not the ArgoCD **Notice** rows. That shows runtime detection on *your app*, not generic cluster chatter.

**Where alerts appear (read this before the break-it scenarios):**

| Where | What you use it for |
|---|---|
| **`http://falco.local`** | Browse recent alerts (easiest for beginners) — open after each scenario |
| **Falco pod logs** | Raw engine output if UI is empty: `kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50` |
| **`make check-6`** | Confirms Falco + netpol installed — does not prove alerts fired |

In the UI, use the workflow in §6.1 (“Reading the Falcosidekick UI”). After each scenario, refresh and look for **Critical** / **Warning** rows whose rule names contain **ClearLedger** — not **Notice** rows from ArgoCD or other cluster components.

**Verify custom rules loaded:**

```bash
kubectl get configmap clearledger-falco-rules -n falco
# NAME                      DATA   AGE
# clearledger-falco-rules   1      2m

kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=30 | grep clearledger_rules
```

**Expected:**

```text
/etc/falco/rules.d/clearledger_rules.yaml | schema validation: ok
```

If you see `LOAD_ERR_COMPILE_CONDITION` instead, the custom rule YAML uses an invalid field — see [troubleshooting.md — Stage 6](../docs/troubleshooting.md#stage-6--runtime-security-falco).

---

### 6.2 — Guided demo (see alerts appear — start here)

**Recommended for first-time users.** Run this **after** §6.1 (Falco installed and UI reachable). The script simulates post-exploit behavior, triggers a real detection, and tells you how to read the alert in the UI.

```bash
make demo-6
# or:
bash stages/stage-6-runtime-security/scripts/demo-falco-alerts.sh
```

#### What the script does (step by step)

| Step | What you see | What is happening |
|---|---|---|
| **1. Context** | “Why this demo exists” + attack story | Frames Stage 6 as runtime detection, not tool install |
| **2. Preflight** | Target pod name printed | Checks Falco namespace, Falcosidekick Redis, and a running `auth-service` pod exist |
| **3. Open UI** | Browser opens `http://falco.local` | Login: `admin` / `admin` — stay on **Events** tab |
| **4. Pause** | `Press Enter when logged in…` | Waits until you are ready (skipped if `SKIP_PROMPT=1`) |
| **5. Baseline** | `Events in UI now: N` | Records current event count; tells you to ignore Notice/argocd noise |
| **6. Pause** | `Press Enter when… noted the current count…` | Second pause so you can watch the UI before the trigger |
| **7. Countdown** | `3… 2… 1…` | Time to focus on the Events tab |
| **8. Trigger** | `uid=1000…` in terminal | Runs the same exec as §6.3 Scenario 1 (see command below) |
| **9. Confirm** | `Falco matching syscall → rule → UI store` then `✓ Runtime detection confirmed` | Polls Falcosidekick’s Redis store for a **new** event whose rule contains `Shell Spawned in ClearLedger` (not just a higher event count — ArgoCD Notice rows can inflate count without your alert) |
| **10. Triage hints** | “Now read the alert like an operator” | Checklist of Priority, Rule, Output fields — full detail in **“After the demo”** below |

**Exact command the script runs** (same as §6.3 Scenario 1):

```bash
kubectl exec -n clearledger \
  auth-service-<pod-suffix> \
  -c auth-service -- /bin/sh -c 'id && exit'
```

The script picks the pod name automatically (`-c auth-service` targets the app container, not the Vault sidecar).

**Non-interactive** (CI or no Enter prompts): `SKIP_PROMPT=1 make demo-6`

**Tip:** Split screen — terminal on the left, Events tab on the right. After step 9, **refresh the browser**; a new **Critical** row should appear at the top.

#### After the demo — read your first alert (do not skip this)

When the terminal prints `✓ Runtime detection confirmed`, **refresh the Events tab** and find the new row at the top. You are not checking a checkbox — you are practicing **incident triage** on a real detection.

**What you just simulated (the attack story):**

An attacker exploited a bug in `auth-service` (SQL injection, RCE, etc.). They did not change Git or create new pods — Kyverno and CI would never see it. They ran a shell inside the already-running container to see who they are (`id`) before going further. **Falco saw the syscall**, matched your custom rule, and recorded an event.

**What Falco actually observed (the system layer):**

| Layer | What happened |
|---|---|
| **Linux kernel** | A new process (`sh`) was created inside a container cgroup |
| **eBPF probe** | Falco’s driver saw `spawned_process` without a container restart |
| **Rule engine** | Condition matched: namespace `clearledger` + shell binary |
| **Enrichment** | k8s-metacollector attached pod name `auth-service-…` |
| **Falcosidekick** | Event stored and shown in the UI |

**What the alert row looks like (Critical vs Notice):**

Before the demo you may see rows like this — **Notice**, rule **Contact K8S API Server From Container**, process `argocd-applicat`:

```text
Priority: Notice          ← lower severity, often baseline cluster activity
Rule:     Contact K8S API Server From Container
Output:   … process=argocd-applicat … k8smeta_ns_name=argocd
Tags:     mitre_discovery, k8s, network
```

After `make demo-6` you should see a **different** row — **Critical**, rule **Shell Spawned in ClearLedger Container**:

```text
Priority: Critical        ← act on this first
Rule:     Shell Spawned in ClearLedger Container
Output:   … pod=auth-service-5756d9fcb9-bmdlr cmd=sh -c id && exit
          k8smeta_ns_name=clearledger
Tags:     clearledger, shell, attack
```

**Field-by-field — what to look at on YOUR alert:**

| Field | What to verify | Why it matters |
|---|---|---|
| **Priority** | `Critical` (red badge) | Triage order — shells in prod apps are high risk |
| **Rule** | Contains `ClearLedger` | Your custom policy fired, not generic stock noise |
| **Time** | Within last minute | Confirms this event is from *your* demo, not old ArgoCD rows |
| **Output → `pod=`** | `auth-service-…` | Which workload is compromised or being investigated |
| **Output → `cmd=`** | `sh -c id && exit` | Exact command — matches what you ran; proof of detection |
| **Output → `k8smeta_ns_name=`** | `clearledger` | Scoped to your app namespace |
| **Tags** | `clearledger`, `shell`, `attack` | Filtering and routing in Stage 7 (Grafana/Loki) |

**Questions an operator asks (practice saying these out loud):**

1. **Is this expected?** — No. Production app containers should not spawn interactive shells unless someone is debugging with approval.
2. **Who did it?** — In the lab, *you* via `kubectl exec`. In a real incident, trace `user=` / audit logs / who has `exec` RBAC.
3. **What stage failed?** — Not Kyverno (pod was compliant). Runtime behavior escaped pre-deploy controls.
4. **What next?** — Snapshot the event, check other alerts on the same pod, review recent deploys, consider isolating the pod (netpol / scale-down) — Stage 6.4 adds *prevention* after you have seen *detection*.

**What you should *not* chase in this lab:**

- **Notice** rows from `argocd`, `kube-system`, or `falco` — normal GitOps/API traffic
- Event count going up from ArgoCD alone — only your **Critical ClearLedger** row proves the demo worked

**Portfolio screenshot:** Capture the **Critical** shell alert row with `cmd=sh -c id && exit` visible — not the ArgoCD Notice rows.

---

### 6.3 — Break-it scenarios (manual)

Each simulates attacker behavior. After each command, check **`http://falco.local`** or Falco pod logs. Use these if you prefer step-by-step control instead of `make demo-6`.

**Scenario 1 — Shell in a running pod (command injection simulation):**

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

**What this means:** Stage 4 allowed the pod (it is compliant). Stage 6 detected *behavior inside* the pod — exactly what an attacker would do after command injection.

**If you see no alert:** confirm the exec used `-c auth-service` (not the vault-agent sidecar), rules show `schema validation: ok`, and the pod image name contains `clearledger`.

**Scenario 2 — Read a sensitive file (reconnaissance):**

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

**Scenario 3 — Download tool at runtime (optional):**

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- sh -c "wget -q ifconfig.me -O - 2>/dev/null || true"
```

May fire **Package manager executed** and/or **Unexpected outbound connection** (WARNING).

**Take screenshots of Scenarios 1 and 2** — portfolio evidence for runtime detection.

---

### 6.4 — Apply network policies (zero-trust segmentation)

Network policies run **after** Falco demos so Stages 1–5 stay debuggable first (netpol too early breaks DNS and breaks the app — you saw that in Stage 2 if `netpol/` was in `clearledger-infra`).

```bash
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
kubectl get networkpolicy -n clearledger
```

**Expected:**

```text
NAME                         POD-SELECTOR               AGE
default-deny-all             <none>                     10s
allow-auth-service           app=auth-service           10s
allow-ledger-service         app=ledger-service         10s
allow-notification-service   app=notification-service   10s
```

**Verify the app still works** (ingress + allowed east-west paths only):

```bash
curl -s http://clearledger.local/auth/health | jq .
# {"status":"ok","service":"auth-service"}

curl -s http://clearledger.local/notifications/health | jq .
# {"status":"ok",...}
```

**Scenario 4 — blocked cross-service traffic (optional):**

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=ledger-service -o name | head -1) \
  -c ledger-service -- sh -c "wget -q http://notification-service/ -O - --timeout=5" 2>&1
# Expected: wget: download timed out  OR  Connection refused
# NetworkPolicy default-deny-all + no allow rule for ledger → notification
```

**How this connects:** Falco **detected** the shell in §6.2/§6.3; netpol **prevents** ledger from reaching notification without going through allowed paths. Detection + prevention together.

If notification health fails after netpol, see [troubleshooting.md — Stage 6](../docs/troubleshooting.md#stage-6--runtime-security-falco).

---

### 6.6 — Health check

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

### Stage 6 complete — done checklist (move to Stage 6.5 / 7)

| # | Check | How to verify |
|---|---|---|
| 1 | Falco running | `kubectl get pods -n falco` — DaemonSet `2/2` |
| 2 | Custom rules loaded | `kubectl get configmap clearledger-falco-rules -n falco` |
| 3 | Shell alert fired **and you read it** | `make demo-6` → Critical row with `cmd=sh -c id && exit`, pod `auth-service-…`, tags `clearledger` — see §6.2 “After the demo” |
| 4 | Network policies applied | `kubectl get networkpolicy -n clearledger` — four policies |
| 5 | App still healthy | `curl` auth + notification health return 200 |
| 6 | Health check | `make check-6` green |

**Recommended for portfolio:** screenshots of shell + sensitive-file alerts in Falco UI.

**What “move to Stage 6.5 / 7” means:** Falco *detects* runtime threats; Stage 6.5 (optional) proves *resilience* under failure; Stage 7 correlates alerts in Grafana.

### What you learned in Stage 6

- What runtime security catches that CI and admission control cannot: threats inside running containers
- What Falco is: eBPF syscall monitoring with custom YAML rules
- What network policies are: Kubernetes firewall rules between pods
- How to trigger and interpret alerts — incident response skills
- **The full stack:** code scanning → admission control → secrets management → runtime detection → (next) observability

### DevSecOps lesson — Stage 6

**Detection at runtime closes the last gap on the node.** CI and Kyverno guard the path in; Vault guards credentials at rest in Git/etcd; Falco watches what processes *do* after a pod is running. Network policies add **prevention** while Falco adds **detection** — both are normal in regulated environments. The break-it scenarios produce audit evidence: named rules, pod, container, and command — exactly what you need when triaging a real incident.

---

## Stage 6.5 — Chaos Engineering (Optional)

> Falco detects threats. Chaos engineering proves you **survive** failure.

**Goal:** Understand the difference between **detection** and **resilience**, then prove auth-service stays available when a pod is killed.

**Why the Litmus UI looked empty:** ChaosCenter is a **control plane**. It does not know about your cluster until an **agent** (subscriber pod) registers. Install now connects the agent automatically; you then **run chaos from the UI** while watching the terminal.

**Path:**

```bash
make fix-65-prereqs
export LITMUS_PASSWORD='your-password'   # only if you changed it from default litmus
bash stages/stage-6.5-chaos-engineering/scripts/install-litmus.sh
# → open http://litmus.local
# → follow §6.5.1c (navigate) + §6.5.2 (ChaosHub → Launch Experiment)
# → optional §6.5.3 (make demo-65 — same test from terminal)
```

| Section | Content |
|---------|---------|
| [§6.5.0](#650--before-you-start-fix-auth-service-restarts) | `make fix-65-prereqs` — auth 2/2 Ready |
| [§6.5.1](#651--install-litmuschaos-operator-ui-cluster-connection) | One install script + expected pods |
| [§6.5.1c](#651c--how-to-navigate-the-litmus-ui-read-before-you-click) | Sidebar, status badges, click order |
| [§6.5.1d](#651d--why-infrastructure-shows-pending) | Fix **PENDING** infrastructure |
| [§6.5.2](#652--how-to-use-chaoshub-and-run-your-first-chaos-experiment) | **ChaosHub → Pod Delete → Launch Experiment** + terminals |
| [§6.5.3](#653--same-experiment-from-the-terminal-make-demo-65) | `make demo-65` (YAML path) |
| [§6.5.3a](#653a--real-output-examples-verified-on-the-lab-cluster) | Real terminal output samples |

This stage is not “install Litmus and move on.” You deliberately kill a pod, watch health stay **200**, and watch Kubernetes recover — in the **UI and terminal together**.

### What you need to know first

| Question | Stage 6 (Falco) | Stage 6.5 (Chaos) |
|---|---|---|
| Did something bad happen? | Yes — alerts on shells, file reads | Not the focus |
| Did the **service stay up** when a pod died? | No — Falco does not answer this | **Yes — this is the point** |
| Did the system **recover** automatically? | No | **Yes — measure MTTR** |

**Chaos engineering** deliberately injects controlled failures (pod kill, latency, memory pressure) and you observe:

1. **Availability** — do users still get HTTP 200 during the failure?
2. **Recovery** — does Kubernetes recreate the pod?
3. **Blast radius** — does one broken pod take down the whole app?

**LitmusChaos** runs experiments defined as Kubernetes YAML (`ChaosEngine`). The operator creates a short-lived **runner pod** that executes the failure (e.g. delete one pod) while you watch health checks and `kubectl get pods`.

**Why this matters for DevOps:** You already proved security controls (Stages 3–6). Regulators and DORA Pillar 3 also ask: *did you test that the system survives failure?* This stage produces that evidence.

### How Stage 6.5 fits the stack

```text
Stage 6 Falco     → "We saw suspicious behavior"
Stage 6.5 Chaos   → "We killed a pod and login still worked"
Stage 7 Grafana   → "We can graph MTTR and error rates over time"
```

**Kyverno interaction (important):** Stage 4 policies block non-compliant pods in `clearledger`. Litmus runner pods do not pass those checks. Therefore **ChaosEngine YAML lives in the `litmus` namespace** but **targets** apps in `clearledger` via `spec.appinfo.appns`. This is a real-world pattern: platform tools run in a platform namespace.

---

### 6.5.0 — Before you start (fix auth-service restarts)

Chaos kills pods. **Replacement pods must start cleanly** or the lab becomes “debugging CrashLoopBackOff” instead of learning resilience.

**Symptoms:** `auth-service` **1/2 Ready**, **CrashLoopBackOff**, many ReplicaSets, ArgoCD **503**, `connection to postgres timed out` in logs.

**Common causes:**

| Cause | Fix |
|---|---|
| Stage 6 `default-deny-all` without **postgres ingress** | `make fix-65-prereqs` (adds `allow-postgres`) |
| ArgoCD syncing old deployment (no `startupProbe`, 256Mi) | `make fix-65-prereqs` |
| Cold-start slower than liveness probe | `startupProbe` in `infra/manifests/auth-service/deployment.yaml` |

**One command:**

```bash
make fix-65-prereqs
kubectl get pods -n clearledger -l app=auth-service
```

**Pass:** exactly **2 pods**, both **2/2 Ready**. Do not run chaos until this is true.

> **ArgoCD users:** If your app syncs from `clearledger-infra.git`, copy `infra/manifests/auth-service/deployment.yaml` and the Stage 6 netpol files into that repo and sync — otherwise self-heal may revert the fix within minutes.

---

### 6.5.1 — Install LitmusChaos (operator, UI, cluster connection)

One script installs everything and connects your cluster to the UI:

```bash
export LITMUS_PASSWORD='your-password'   # only if you changed it from default litmus
bash stages/stage-6.5-chaos-engineering/scripts/install-litmus.sh
make open-litmus   # http://litmus.local
```

| Component | Role |
|-----------|------|
| `litmus-core` + `kubernetes-chaos` | Chaos **operator** — runs `ChaosEngine` YAML (`make demo-65`) |
| `chaos` (ChaosCenter) | Web UI + MongoDB — **§6.5.2** |
| `litmus-ingress.yaml` | Exposes **http://litmus.local** |
| `connect-litmus-infra.sh` (end of install) | Registers agent — Overview **Active 1** |

**What the install script does (step by step):**

| Step | Action | Purpose |
|------|--------|---------|
| 1 | `kubectl apply` → `litmus-install.yaml` | Creates `litmus` namespace |
| 2 | `kubectl apply` → `litmus-rbac.yaml` | `litmus-admin` SA (pod delete in `clearledger`) |
| 3 | `helm install litmus-core` | Watches `ChaosEngine` CRs, creates runner pods |
| 4 | `helm install litmus-k8s` | Installs `pod-delete`, latency, memory-hog experiments |
| 5 | `helm install chaos` | ChaosCenter UI + MongoDB |
| 6 | `kubectl apply` → `litmus-ingress.yaml` | UI at **http://litmus.local** (+ `/backend/` for API) |
| 7 | `connect-litmus-infra.sh` | Subscriber agent → infrastructure **Active** (not Pending) |

**Login:**

| Field | Value |
|-------|-------|
| URL | **http://litmus.local** |
| Username | `admin` |
| Password | `litmus` (or the password you set at first login) |

**Expected pods after install:**

```text
kubectl get pods -n litmus
NAME                                            READY   STATUS
litmus-f95fd6fc4-xxxxx                          1/1     Running    ← litmus-core operator
chaos-litmus-frontend-xxxxx                     1/1     Running    ← UI
chaos-litmus-server-xxxxx                       1/1     Running    ← GraphQL API
chaos-mongodb-0                                 1/1     Running
clearledger-chaos-infra-subscriber-xxxxx        1/1     Running    ← cluster connected
clearledger-chaos-infra-chaos-operator-xxxxx    1/1     Running
```

**Pass before §6.5.2:** open **http://litmus.local** → **Overview** shows **Infrastructures: Active 1**. If **0** or infrastructure **Pending**, see §6.5.1b / §6.5.1d.

---

### 6.5.1b — If Overview still shows “0 infrastructures”

The UI cannot run experiments until the cluster agent is connected.

```bash
export LITMUS_PASSWORD='your-password'   # default is litmus
bash stages/stage-6.5-chaos-engineering/scripts/connect-litmus-infra.sh
kubectl get pods -n litmus | grep subscriber    # should be Running
```

Hard-refresh the browser (`Cmd+Shift+R`). **Do not** bookmark `/account/.../settings` URLs — start at **http://litmus.local** only.

---

### 6.5.1c — How to navigate the Litmus UI (read before you click)

Think of ChaosCenter as **three layers**:

```text
1. Project (admin-project)     ← top-left dropdown
2. Environment (clearledger-lab) ← where your cluster is registered
3. Infrastructure (clearledger-cluster) ← the agent on YOUR Kubernetes cluster
```

#### Left sidebar — what each item is for

| Nav item | What it is | When you use it |
|----------|------------|-----------------|
| **Overview** | Dashboard: how many infrastructures are **Active** | First stop after login — must show **Active 1** |
| **Environments** | Groups infrastructures (e.g. Pre-Prod lab) | Click **clearledger-lab** to see your cluster |
| **ChaosHub** | Catalog of fault templates (pod-delete, latency, …) | Pick **pod-delete** before creating an experiment |
| **Chaos Experiments** | Your saved tests + **Run** button | Where you actually start chaos |
| **Resilience Probes** | Health checks during experiments | Optional; skip in this lab |

#### Status badges — what to look for

| Badge | Meaning | What to do |
|-------|---------|------------|
| **PENDING** (purple) | Agent registered in UI but **not confirmed** yet — subscriber has not finished handshake | Wait 1–2 min, refresh. Still PENDING? Run §6.5.1d |
| **Active** (green) | Cluster connected — you can run experiments | Go to §6.5.2 |
| **Overview: 0 infrastructures** | No agent installed | `make connect-litmus` |
| **Blank white page** | Wrong URL or API not reachable | Use **http://litmus.local** only; re-apply `litmus-ingress.yaml` |

#### Quick map of the left nav

| Item | Use in this lab |
|------|-----------------|
| **Overview** | Is the cluster connected? Must show **Infrastructures: Active 1** |
| **Environments** | **clearledger-lab** → **clearledger-cluster** — status must be **Active** |
| **ChaosHubs** | Pick **Pod Delete** → **Launch Experiment** (main UI path — §6.5.2) |
| **Chaos Experiments** | List past runs; open one to see the timeline after you click **Run** |
| **Resilience Probes** | Skip for now |
| **Project Setup** | Skip for now |

#### Navigation path for this lab (click order)

1. **http://litmus.local** → log in
2. **Overview** → confirm **Infrastructures: Active 1**
3. **Environments** → **clearledger-lab** → **clearledger-cluster** → **Active** (not Pending)
4. **ChaosHubs** → default hub → **Pod Delete** → **Launch Experiment** (§6.5.2)
5. **Chaos Experiments** → watch status **Running → Completed**

You do **not** need deep **Settings** URLs (`/account/.../settings/...`) — they often show a blank page.

---

### 6.5.1d — Why infrastructure shows **PENDING**

**PENDING** means: Litmus created the infrastructure record in MongoDB, but the **subscriber** has not yet confirmed that all agent pods on your cluster are healthy.

Common cause in this lab: the **event-tracker** pod crashes (missing CRD when we skip duplicate CRD install). The subscriber waits for event-tracker → never confirms → UI stays **PENDING**.

**Fix (already in `connect-litmus-infra.sh`):**

```bash
export LITMUS_PASSWORD='your-password'
make connect-litmus
```

**Verify from terminal:**

```bash
kubectl get pods -n litmus | grep -E 'subscriber|event-tracker'
# subscriber: Running
# event-tracker: should be gone or not required

kubectl logs -n litmus -l app.kubernetes.io/name=subscriber --tail=5
# look for: "AgentID: ... has been confirmed"

kubectl get cm subscriber-config -n litmus -o jsonpath='{.data.IS_INFRA_CONFIRMED}'
# true
```

Refresh **Environments → clearledger-lab** — **clearledger-cluster** should change from **PENDING** to **Active**.

---

### 6.5.2 — How to use ChaosHub and run your first chaos experiment

**Time:** ~20 minutes. **You need:** browser at **http://litmus.local** + two terminal windows on your Mac (where `kubectl` and `/etc/hosts` for `clearledger.local` work).

> **One-line lesson:** Stage 6 (Falco) asks *“did something bad happen?”* Stage 6.5 asks *“did we stay up when a pod died?”*

#### Where you are in the UI

You are in the right place when you see:

**ChaosHubs → default hub → Chaos Experiments (10)**

That page lists experiment **cards** (Pod Delete, Pod CPU Hog, Pod Memory Hog, …). Each card is a reusable fault template.

#### ChaosHub screen — what you see

| What you see | What it means |
|--------------|---------------|
| **Pod Delete** card | Kills pod(s) matching a label — **use this one for the lab** |
| **Launch Experiment** (purple button) | Opens the wizard to target **your** app on **clearledger-cluster** |
| **Pod CPU Hog** / **Pod Memory Hog** / others | Optional follow-ups — run **one experiment at a time**, only after pod-delete succeeds |
| **Chaos Faults (53)** tab | Low-level faults; skip — use **Chaos Experiments** cards instead |
| Search box | Filter cards by name (e.g. type `pod delete`) |

#### Step 0 — Open the right page

| Do | Don't |
|----|-------|
| Go to **http://litmus.local** | Open old `/account/.../settings/projects` bookmarks (blank page) |
| Log in: `admin` + your password | Expect data before login |

**After login you should see:**

- Left nav: **Overview**, **Environments**, **ChaosHub**, **Chaos Experiments**
- **Overview** card: **Infrastructures → Active 1** (if **0**, run §6.5.1b first)

**What “connected” means:** A `subscriber` pod in `litmus` talks to ChaosCenter. The UI is no longer an empty shell — it can schedule experiments on **your** cluster.

```bash
kubectl get pods -n litmus | grep subscriber
# clearledger-chaos-infra-subscriber-...   1/1   Running
```

#### Step 1 — Understand the map (2 min)

```text
Litmus ChaosCenter (litmus.local)     ← you click "Run" here
        │
        ▼
subscriber / chaos-operator (litmus ns)  ← agent on YOUR cluster
        │
        ▼
auth-service pods (clearledger ns)    ← target: kill 50%, watch recovery
```

**Stage 6 (Falco)** asked: *did something suspicious happen?*
**Stage 6.5** asks: *if a pod dies, do users still get HTTP 200?*

#### Step 2 — Open terminals before you click Run (2 min)

**Terminal A — watch pods:**

```bash
kubectl get pods -n clearledger -l app=auth-service -w
```

**Terminal B — watch health every 5 seconds:**

```bash
while true; do
  date +%H:%M:%S
  curl -s -o /dev/null -w "health=%{http_code}\n" http://clearledger.local/auth/health
  sleep 5
done
```

Leave both running. You will correlate what the UI shows with what Kubernetes actually does.

#### Step 3 — Launch pod-delete from ChaosHub (10 min)

> **Litmus UI note:** ChaosCenter labels change between versions (e.g. “Tune fault”, “Target selection”, “Chaos Experiment”). Follow the **concepts** below — match fields by meaning, not exact button text. If your wizard has extra steps (probes, hooks), accept defaults unless the lab table lists a value.

**Click path:**

1. Left nav → **ChaosHubs** (or **Chaos Hub**) → open the **default** hub
2. Tab **Chaos Experiments** — find the **Pod Delete** card (*injects random pod delete failures…*)
3. Click **Launch Experiment** (purple button on the card — may say **Create** or **Use** on older builds)

**Wizard — map each screen to these values:**

| Concept (what Litmus is asking) | Set to | UI labels you might see |
|---------------------------------|--------|-------------------------|
| **Where to run** | Infrastructure **clearledger-cluster** (**Active**, not Pending) | “Infrastructure”, “Chaos Infrastructure”, “Execution plane” |
| **Target namespace** | `clearledger` | “Namespace”, “Application namespace” |
| **Target selector** | Label `app=auth-service` | “Label”, “App label”, “Target application” |
| **Workload type** | **Deployment** | “Kind”, “Workload type”, “Resource type” |
| **Blast radius** | **50%** pods affected | “Pods affected”, “Percentage”, “PODS_AFFECTED_PERC” |
| **Duration** | **30** seconds | “Total chaos duration”, “Duration”, “Chaos interval” |
| **Fault name** | `pod-delete` (usually pre-filled from hub) | “Experiment name”, “Fault” |

**Typical wizard flow (screens may merge or reorder):**

```text
1. Select infrastructure  → clearledger-cluster (Active)
2. Target application     → namespace clearledger, label app=auth-service, kind Deployment
3. Tune fault / parameters → 50% pods, 30s duration
4. Save / Create experiment
5. Run now (not Schedule)
```

**Finish:**

1. Click **Save** / **Create** / **Finish** (whatever completes the wizard)
2. Click **Run** / **Execute** / **Start** on the experiment (not **Schedule** for this lab)
3. Left nav → **Chaos Experiments** → open your run → status **Running → Completed** (or **Succeeded**)

**Alternate path:** **Chaos Experiments** → **+ New Experiment** / **New Chaos Experiment** → search **pod-delete** → same values as the table above.

#### What to look for (UI + terminals together)

Run the terminals from **Step 2** on your Mac before you click **Run** in the UI.

| Where | Good sign | Bad sign |
|-------|-----------|----------|
| **Terminal A** (`kubectl … -w`) | One pod **Terminating**, then a new pod → **2/2 Ready** | 0 Running pods, or stuck CrashLoopBackOff |
| **Terminal B** (`curl …/auth/health`) | `health=200` **while** one pod is down | `502` / `503` / timeout during chaos |
| **UI — Chaos Experiments** | Status **Running** → **Completed** | Stuck **Running** forever, or Error |
| **UI — experiment timeline** | Steps/probes advance during the 30s window | Blank timeline (infra not connected) |

**Write this in your notes (DORA / resilience evidence):**

> We deleted 50% of auth-service pods; `/auth/health` stayed 200; Kubernetes recreated the pod within ~2 minutes.

#### Step 4 — Confirm recovery (3 min)

```bash
kubectl get pods -n clearledger -l app=auth-service
# exactly 2 pods, both 2/2 Ready
```

In the UI: **Environments** → **clearledger-lab** → your infrastructure → past runs should list the experiment.

#### Step 5 — What you learned (say it out loud)

1. **Replicas matter** — one dead pod ≠ outage if the Service has another healthy endpoint.
2. **Probes matter** — unhealthy pods are removed from the Service endpoints.
3. **Detection ≠ resilience** — Falco would not prove `health=200` during a pod kill; chaos did.

#### Step 6 — Optional second demo (only after Step 3 succeeds)

Wait until auth is back to **2/2 Ready**, then try **one** more card from ChaosHub:

| Card | Target | What it teaches |
|------|--------|-----------------|
| **Pod Memory Hog** | `notification-service` in `clearledger` | Memory pressure → OOMKill → restart |
| **Pod CPU Hog** | `auth-service` | CPU saturation under load |

Or apply the YAML equivalents (one at a time):

```bash
kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/notification-service-memory-hog.yaml
# wait for recovery, then:
kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/ledger-service-network-latency.yaml
```

---

### 6.5.3 — Same experiment from the terminal (`make demo-65`)

Use this **after** the ChaosHub exercise (§6.5.2), or if you prefer a scripted demo first. It runs the **same pod-delete test** without clicking through the UI wizard.

```bash
make fix-65-prereqs    # if auth pods are not 2/2 Ready
make demo-65
```

**What the script does:**

| Step | What happens |
|------|----------------|
| Preflight | Checks Litmus is installed and 2 `auth-service` pods are Running |
| Apply | `kubectl apply -f auth-service-pod-delete.yaml` (ChaosEngine in namespace `litmus`) |
| Watch | Prints `/auth/health` every 10s for ~60s |
| Report | Shows recovery pod count + `ChaosResult` verdict |

**Expected results on the cluster:**

| Signal | Expected |
|--------|----------|
| `ChaosEngine` | `auth-service-pod-delete` in namespace `litmus` |
| `ChaosResult` | **Completed** / **Pass** |
| Auth pods after demo | **2** pods **2/2 Ready** (one was killed and replaced) |
| Events | `Killing` on old pod → `Scheduled` / `Started` on new pod |

```bash
kubectl get chaosresult -n litmus
kubectl get pods -n clearledger -l app=auth-service
```

**Pass criteria for `make demo-65`:**

| Signal | Pass? |
|--------|-------|
| Script ends with **PASS** | Required |
| `ChaosResult` **Completed / Pass** | Required |
| **2** auth pods **Running** after demo | Required |
| `health=200` on most checks | Ideal; script also passes if ChaosResult is Pass and pods recovered |

**See the run in the UI after the terminal demo:** **Chaos Experiments** (left nav) → refresh → open the latest run.

**Stage 6 netpol:** Re-apply if new auth pods stuck in `Init:0/1`:

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

#### Terminal B on your Mac (expected when hosts are correct)

```text
22:05:01
health=200
22:05:06
health=200
22:05:11
health=200
```

> Pod count may show **1** while the replacement pod is still starting — that is expected.

#### Terminal A during chaos (`kubectl get pods -w`)

```text
NAME                            READY   STATUS        RESTARTS   AGE
auth-service-84cc988c4d-hdb45   2/2     Running       0          67m
auth-service-84cc988c4d-b59sj   2/2     Terminating   0          15m    ← killed
auth-service-84cc988c4d-dxz9q   0/2     Pending       0          0s     ← replacement
auth-service-84cc988c4d-dxz9q   0/2     Init:0/1      0          2s
auth-service-84cc988c4d-dxz9q   2/2     Running       0          90s
```

#### Terminal B on your Mac (manual health loop)

```text
22:05:01
health=200
22:05:06
health=200
22:05:11
health=200
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

Each file is a **`ChaosEngine`** — a request to Litmus: “run experiment X against app Y for Z seconds.”

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

**1. During chaos — availability**

| Signal | Good | Bad |
|---|---|---|
| `curl http://clearledger.local/auth/health` | **200** while one pod is down | 502/503/timeout |
| `kubectl get pods -l app=auth-service` | 1 Running + 1 Init/Pending (replacement starting) | 0 Running |

**Why 200 is enough:** The Kubernetes **Service** load-balances to healthy endpoints. One replica dying should not kill the Service if the other passes readiness probes.

**2. After chaos — recovery**

| Signal | Good | Bad |
|---|---|---|
| Pod count | 2/2 **Ready** (may take 1–2 min — Vault agent init) | Stuck at 1 replica |
| Events | `Killing` then `Scheduled` / `Started` on new pod | Repeated CrashLoopBackOff |
| ArgoCD | Synced (if you deleted a pod, Deployment controller heals — GitOps desired state unchanged) | — |

**3. Litmus `ChaosResult` verdict**

```bash
kubectl get chaosresult -n litmus
```

Verdict may show **Error** if Litmus targets a pod still in `Init:0/1` (Vault agent starting). That is a Litmus timing issue, not necessarily failed resilience.

**Your pass criteria for this lab:**

- `/auth/health` returned **200** at least once during the chaos window
- A pod was **Killed** (see events)
- Deployment returned to **2 replicas**

**4. Falco during chaos**

Falco may or may not alert on pod delete — that is normal. Pod deletion by the kubelet/Litmus is not the same as an attacker shell. No ClearLedger Critical alerts is **expected**.

**Optional second terminal during demo:**

```bash
kubectl get pods -n clearledger -l app=auth-service -w
```

Watch one pod terminate and a new one appear — that is Kubernetes self-healing in real time.

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

**Expected:** see full sample in [§6.5.3a](#653a--real-output-examples-verified-on-the-lab-cluster) (`make check-65` block). Minimum:

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

### What you learned in Stage 6.5

- **Detection ≠ resilience** — Falco alerts do not prove HA
- **Replicas + Services + probes** — why `replicas: 2` is not cosmetic
- **ChaosEngine YAML** — declarative failure injection as code
- **Platform vs app namespaces** — Kyverno blocks chaos runners in `clearledger`; engines run in `litmus`
- **MTTR** — time from pod kill to 2/2 Ready again (Stage 7 graphs this)

### DevSecOps lesson — Stage 6.5

Security tooling tells you when something looks wrong. **Resilience testing** tells you whether the business keeps running anyway. Together they match what production teams and DORA expect: detect incidents *and* prove you tested recovery before auditors ask.

---

## Stage 7 — Security Observability

> Security you cannot measure you cannot prove.

**Goal:** Understand how **metrics**, **logs**, and **dashboards** fit together — then prove it by running commands in the terminal, watching the same events appear in Grafana, and explaining what each panel means.

This stage is **not** “install Grafana and move on.” **Stage 7 is not complete** until your dashboards show **real** Kyverno violations and Falco alerts that **you triggered** in §7.4 — plus portfolio screenshots (§7.6). `make check-7` only proves the stack is up; it does **not** prove you can detect security events.

> **Already installed?** If `kubectl get pods -n monitoring` shows Grafana **3/3** and Loki **1/1**, skip §7.1 and start at **§7.2** (verify the stack), then **§7.4** (hands-on lab).

---

### What you need to know first

Each earlier stage has its own view: CI logs, Kyverno CLI, Falco UI, `kubectl logs`. Stage 7 **correlates** them.

| Tool | What it stores | Think of it as… |
|---|---|---|
| **Prometheus** | Numbers over time (counters, rates) | A spreadsheet of metrics scraped every 15–30s |
| **Loki** | Log lines from pods (Falco, apps) | Searchable text — like `grep` across the cluster |
| **Grafana** | Charts that query Prometheus + Loki | The screen you show an auditor |

**ServiceMonitors / PodMonitors** tell Prometheus *where to scrape*. No monitor for Kyverno → Kyverno panels stay empty. No PodMonitor for `auth-service` → Request Rate stays empty until §7.5 (metrics-enabled images deployed via GitOps).

**Promtail** ships container logs into Loki. No Loki → log panels say “No data” even when `kubectl logs` works.

#### How Stage 7 fits the full stack

| Stage | What happened | What shows up in Grafana |
|---|---|---|
| **3 — CI** | Scans in GitHub Actions | Compliance narrative (tools marked ACTIVE) |
| **4 — Kyverno** | Blocked bad `kubectl apply` | **Kyverno Policy Violations** (Prometheus) |
| **5 — Vault** | Secrets injected at runtime | Indirectly — fewer secret-in-Git incidents |
| **6 — Falco** | Shell / sensitive file read | **Security Event Timeline** (Loki) |
| **6 — NetworkPolicy** | Blocked pod traffic | Runtime layer in compliance view |
| **Apps** | HTTP requests, failed logins | **Service Health** (Loki + Prometheus) |

```text
You run a command (terminal)
  → Kyverno / Falco / app logs an event
  → Prometheus or Loki stores it (15–90s later)
  → Grafana panel updates
```

**Beginner takeaway:** The terminal proves the event happened. The dashboard proves you can **detect and measure** it later.

---

### 7.0 — Free node resources (scale down Litmus)

Stage 6.5 is complete — you do not need the Litmus UI, MongoDB, or chaos operator running while Prometheus, Loki, and Grafana start. They compete for the same 4 CPUs on a single-node lab VM. Scaling Litmus to zero frees ~500–800MB RAM and reduces CPU churn before the observability install.

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

```bash
bash stages/stage-7-observability/scripts/install-observability.sh
```

The installer is idempotent: if everything is already healthy, it only refreshes dashboards and monitors. Use `FORCE=1` only when Helm values changed or Loki keeps restarting.

**Expected — monitoring namespace pods (names vary):**

```text
NAME                                              READY   STATUS    RESTARTS   AGE
kube-prometheus-stack-grafana-....                3/3     Running   0          5m
kube-prometheus-stack-prometheus-....             2/2     Running   0          5m
loki-0                                            1/1     Running   0          5m
loki-promtail-....                                1/1     Running   0          5m
```

```bash
kubectl get pods -n monitoring
```

**Expected — Loki healthy:**

```bash
kubectl exec -n monitoring loki-0 -- wget -qO- http://127.0.0.1:3100/ready
```

```text
ready
```

**Expected — Grafana can reach Loki (same path log panels use):**

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  wget -qO- --timeout=5 http://loki:3100/ready
```

```text
ready
```

**Expected — Grafana UI reachable:**

```bash
curl -sI http://grafana.local | head -n 1
```

```text
HTTP/1.1 302 Found
```

Log in: **http://grafana.local** — `admin` / `admin123`

> Empty panels right after install are **normal**. You have not generated events yet. Continue to §7.2–§7.4.

If Helm fails: wait 30s, then `FORCE=1 bash stages/stage-7-observability/scripts/install-observability.sh`. See [troubleshooting.md — Stage 7](troubleshooting.md#stage-7--observability-grafana--prometheus--loki).

---

### 7.2 — Verify Prometheus, Loki, and Grafana (before opening dashboards)

Run these three checks so you know **which layer** is broken if a panel is empty.

#### Check 1 — Prometheus has Kyverno metrics

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=kyverno_admission_requests_total' 2>/dev/null \
  | head -c 400
```

**Expected:** JSON with `"status":"success"` and a `"metric"` block (values may be `0` until you trigger a violation in §7.4).

If you see `"status":"success"` but `"result":[]`, Prometheus is up but Kyverno has not recorded admissions yet — that is fine before the lab.

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

**Expected:** `"status":"success"` — `"result":[]` means no Falco lines in Loki yet, not a broken Loki.

#### Check 3 — Grafana imported ClearLedger dashboards

```bash
curl -s -u admin:admin123 'http://grafana.local/api/search?tag=clearledger' | jq -r '.[].title'
```

**Expected — six titles:**

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

#### Where to go first

Do not open all six dashboards at once — Loki can struggle on a small cluster. Use this order:

| Order | Dashboard | Why start here |
|---|---|---|
| **1** | [Kyverno Policy Violations](http://grafana.local/d/clearledger-kyverno-violations) | You already practiced Kyverno in Stage 4 — easy win |
| **2** | [Security Event Timeline](http://grafana.local/d/clearledger-security-events) | Ties to Stage 6 Falco — log-based |
| **3** | [Service Health + Auth](http://grafana.local/d/clearledger-service-health) | App traffic and failed logins |
| **4** | [Compliance Posture](http://grafana.local/d/clearledger-compliance) | Single pane — sums the story for auditors |
| **5** | [Audit Log Analysis](http://grafana.local/d/clearledger-audit-logs) | Control-plane audit (often empty on MicroK8s) |
| **6** | [DORA Metrics](http://grafana.local/d/clearledger-dora-metrics) | Deploy frequency / lead time proxies |

**Always set time range:** top-right → **Last 15 minutes** (while learning).

Use **UID links** above, not long auto-generated URLs — old cached slugs cause `not correct url` in the browser console.

#### How to read a panel (30-second guide)

| Panel type | Usually powered by | What you are looking for |
|---|---|---|
| **Stat** (big number) | Prometheus or Loki | Did count go **above 0** after your test? |
| **Time series** (line chart) | Prometheus or Loki | Spike or new line **after** the timestamp you ran the command |
| **Logs** (scrollable lines) | Loki | Your event text — rule name, `CRITICAL`, `Failed login attempt` |
| **Pie / bar** | Prometheus or Loki | Which rule or priority dominated in the window |

**Prometheus panels** = numbers scraped from `/metrics` endpoints (Kyverno, ArgoCD, apps).

**Loki panels** = log lines (Falco JSON in `falco` namespace, auth-service stdout).

If **only** log panels fail with `connection refused`, Loki is down or restarting — see §7.1 sanity checks. Metric panels can still work.

#### What “good” looks like before vs after the lab

| Dashboard | Before §7.4 | After §7.4 (success) |
|---|---|---|
| Kyverno | Violations = 0 or flat | **Policy Violations (last hour) > 0** |
| Security Event Timeline | Empty log table | **CRITICAL** row with shell / `Terminal shell in container` |
| Service Health | Failed logins = 0 | **Failed Login Attempts > 0** |
| Compliance | Top stats zero | **Policy Violations**, **Runtime Threats**, **Failed Auth** non-zero |

---

### 7.4 — Hands-on lab: terminal → dashboard proof

This is the core learning section. Each exercise: run the command, wait, then confirm in Grafana.

**Timing:** wait **30–90 seconds** after each command for Prometheus scrape and Loki ingestion.

> **Prefer a guided script?** The same steps run interactively with pauses:
> `bash stages/stage-7-observability/scripts/generate-dashboard-data.sh`

---

#### Exercise A — Kyverno block → Prometheus → Kyverno dashboard

**Terminal** — apply a pod that violates Stage 4 policy (runs as root):

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

**Expected terminal output (success = blocked):**

```text
Error from server: error when creating "STDIN": admission webhook "validate.kyverno.svc" denied the request:
policy disallow-root-containers/validate-run-as-non-root fail: Running as root is not allowed
```

If the pod **creates** instead, Kyverno is not enforcing — run `make check-4` before continuing.

**Confirm Prometheus saw it** (optional):

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=kyverno_admission_requests_total{request_allowed="false"}' 2>/dev/null \
  | grep -o '"value":\[[^]]*\]' | head -3
```

**Expected:** a `"value"` entry with a recent Unix timestamp and a number **greater than 0**.

**Grafana** — open [Kyverno Policy Violations](http://grafana.local/d/clearledger-kyverno-violations?from=now-15m&to=now)

| Panel | What to look for |
|---|---|
| Policy Violations (last hour) | Number **> 0** |
| Violations by Policy | Bar for `disallow-root-containers` or similar |
| Violation Rate | Line tick up in the last few minutes |

---

#### Exercise B — Falco shell → Loki → Security Event Timeline

**Terminal** — exec into auth-service (Stage 6 same technique):

```bash
AUTH_POD=$(kubectl get pod -n clearledger -l app=auth-service \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "Using pod: $AUTH_POD"
kubectl exec -n clearledger "$AUTH_POD" -c auth-service -- /bin/sh -c 'id && exit'
```

**Expected:** command prints `uid=0(root)` or similar and exits — Falco rules fire on shell spawn.

**Confirm Falco logged it:**

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5 | grep -i shell || \
  kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5
```

**Expected:** a line containing `Terminal shell in container` or priority `Critical`.

**Confirm Loki has it** (after ~60s):

```bash
kubectl exec -n monitoring loki-0 -- wget -qO- \
  'http://127.0.0.1:3100/loki/api/v1/query?query=%7Bnamespace%3D%22falco%22%7D&limit=2' 2>/dev/null \
  | grep -o 'Terminal shell[^"]*' | head -1
```

**Expected:** substring like `Terminal shell in container` (or non-empty grep output).

**Grafana** — open [Security Event Timeline](http://grafana.local/d/clearledger-security-events?from=now-15m&to=now)

| Panel | What to look for |
|---|---|
| Falco Alerts by Priority | **CRITICAL** line or spike |
| Recent CRITICAL / WARNING Events | Log row with your pod name and shell rule |
| CRITICAL Alerts (period) | Stat **≥ 1** |

---

#### Exercise C — Failed login → Loki → Service Health

**Terminal** — send traffic and bad logins:

```bash
for i in $(seq 1 10); do
  curl -s http://clearledger.local/auth/health >/dev/null
  curl -s -X POST http://clearledger.local/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"lab-attacker@evil.com","password":"wrong"}' >/dev/null
done
echo "done"
```

**Expected:** `done` (no output per curl is fine).

**Confirm auth-service logged failures:**

```bash
kubectl logs -n clearledger -l app=auth-service --tail=20 | grep -i 'Failed login' | tail -3
```

**Expected:**

```text
Failed login attempt for email: lab-attacker@evil.com
```

**Grafana** — open [Service Health](http://grafana.local/d/clearledger-service-health?from=now-15m&to=now)

| Panel | What to look for |
|---|---|
| Failed Login Attempts | Stat **> 0** |
| Successful Logins | May stay 0 — that is fine |
| Auth Service Logs | Lines with `Failed login attempt` |

---

#### Exercise D — Compliance dashboard (auditor view)

After A + B + C, open [Compliance Posture](http://grafana.local/d/clearledger-compliance?from=now-1h&to=now)

**Expected — top row stats non-zero:**

| Stat | Source exercise |
|---|---|
| Policy Violations | Exercise A (Kyverno) |
| Runtime Threats | Exercise B (Falco) |
| Failed Auth Attempts | Exercise C (auth logs) |

This is the **one screenshot** that shows defense-in-depth: admission + runtime + application.

---

### 7.5 — Optional: Prometheus metrics for Request Rate

Log panels work without image changes. **Request Rate** needs app images that expose `/metrics`.

The `/metrics` endpoint is already in the app source (`app/*/prom_metrics.py`) and is included in every CI build. If your cluster still runs **old image tags** from before that code landed, Prometheus has nothing to scrape.

**Preferred — GitOps (same path as Stage 1–2):**

```bash
git push origin main
# CI builds signed images → updates clearledger-infra → ArgoCD syncs
# Wait for ArgoCD Synced + Healthy, then verify (~60s after rollout):
```

> Skip this section if `http_requests_total` already returns data in Prometheus.

**Lab shortcut only** — bypasses Git; ArgoCD `selfHeal` may revert within ~3 minutes unless you update `clearledger-infra` or temporarily disable self-heal (see §2 rollback):

```bash
export DOCKER_USERNAME=your-dockerhub-user
bash stages/stage-7-observability/scripts/build-metrics-images.sh
```

**Expected — query after rollout (~60s):**

```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=http_requests_total' 2>/dev/null \
  | grep -o '"__name__":"http_requests_total"' | head -1
```

```text
"__name__":"http_requests_total"
```

Then refresh **Service Health** — **Request Rate** lines should appear.

---

### 7.6 — Stage 7 complete checklist + screenshots

#### Done vs not done

| Status | What you have |
|---|---|
| **Not done** | Grafana opens, six dashboards listed, panels empty or only old noise |
| **Not done** | `make check-7` passes but you never ran §7.4 |
| **Done** | You ran §7.4 (or `make demo-7`), waited 30–90s, panels show **your** events, three screenshots saved |

#### Portfolio screenshots (required)

Set time range to **Last 15 minutes** before each capture. Include the Grafana time picker and panel titles in the frame.

| # | Open this URL | Exact panel(s) that must be visible | What the screenshot must show |
|---|---|---|---|
| **1** | http://grafana.local/d/clearledger-security-events | **Recent CRITICAL / WARNING Events** (log panel) | At least one row with **CRITICAL** and text like `Terminal shell in container` (from Exercise B) |
| **2** | http://grafana.local/d/clearledger-kyverno-violations | **Violations (last hour)** (big stat, top row) | Number **≥ 1** (red background). Optional: **Violation Rate** chart ticked up in last 15m |
| **3** | http://grafana.local/d/clearledger-compliance | Top row stats | **Policy Violations**, **Runtime Threats**, and **Failed Auth Attempts** all **> 0** after Exercises A–C |
| **4 (optional)** | http://grafana.local/d/clearledger-service-health | **Failed Login Attempts** | Stat **> 0** and/or **Auth Service Logs** with `Failed login attempt` lines |

**Where to save files:** e.g. `docs/evidence/stage-7-screenshot-1-falco.png` (or your portfolio folder). Filename should say what proof it is.

**Stage 7 is done when:** `make check-7` passes **and** screenshots **1–3** show events from **your** §7.4 run — not from a demo video or someone else’s cluster.

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

Warnings about Loki restarts or missing dashboards — fix with §7.1 before claiming Stage 7 complete.

---

### 7.8 — Technical issues we hit (and how to explain them in interviews)

Use this when an interviewer asks *”What broke in observability?”* or *”How do Prometheus, Loki, and Grafana fit together?”*

#### CI pipeline issues fixed before Stage 7 could complete

These CI problems blocked the delivery of metrics-enabled images and are worth documenting because they represent real DevSecOps pipeline concerns.

**`}}` in GitHub Actions workflow (Jun 2026)**

Python dict literals inside `run:` blocks produce `}}` when closing nested structures (e.g. `{“sha1”: e[“SHA”]}`). GitHub's expression engine parses `}}` as a closing delimiter even inside `run:` blocks — it rejected every workflow run before any job started (0 jobs, 0s completion, `failure`). Fixed by extracting nested dicts into named variables so `}}` never appears on a single line.

**Stale Trivy vulnerability database**

Trivy caches its CVE database on the runner. After several days, the cache exceeds the 5-day max-age and `trivy image` fails before scanning a single layer. Fixed with `GRYPE_DB_MAX_ALLOWED_BUILT_AGE=336h` (grype) and a `prepare-scanners` job that downloads the Trivy DB once per workflow — all scan jobs then use `--skip-db-update`.

**Docker DNS drops mid `pip install`**

The Multipass VM uses NAT. Docker containers during `docker build` inherited Docker's embedded DNS resolver (`127.0.0.1:53`), which became unreliable when NAT sessions were reused. Pip downloads timed out mid-transfer, then all retries failed with `[Errno -2] Name or service not known`. Fixed by configuring the Docker daemon to use Google DNS directly (`/etc/docker/daemon.json` with `{“dns”:[“8.8.8.8”,”8.8.4.4”]}`) and adding TCP keepalive (`net.ipv4.tcp_keepalive_time=60`) on the VM so NAT sessions stay alive during long downloads.

**Python 3.13 wheel compatibility**

Upgrading from `python:3.12-slim` to `python:3.13-slim` (to fix CVE-2026-4224, CVE-2026-3644, CVE-2025-13462) broke the build because `asyncpg==0.29.0` and `psycopg2-binary==2.9.9` had no pre-built cp313 wheels. Upgraded to `asyncpg==0.31.0` and `psycopg2-binary==2.9.12` which ship cp313 wheels. CVE-2026-7210 (CRITICAL) is suppressed in `.grype.yaml` and `.trivyignore` because its only fix is in Python 3.15.0b2 (beta — not acceptable for production).

**Kyverno blocking ArgoCD syncs on image tag updates**

After Stage 4 (Kyverno in Enforce mode), every ArgoCD sync that touched the `frontend` and `notification-service` deployments was blocked by Kyverno's `disallow-root-containers` autogen rule. The pod-level `securityContext.runAsNonRoot: true` was present but Kyverno's autogen generates per-container rules that require the field at container level individually. Auth-service and ledger-service already had it at container level; frontend and notification-service only had it at pod level. Fixed by adding `runAsNonRoot: true` to the container-level `securityContext` in both manifests in `clearledger-infra`.

**Kustomize + ArgoCD image substitution**

The infra repo was refactored to use Kustomize (prod pattern): deployment manifests use placeholder images (`clearledger/frontend:gitops`) and `kustomization.yaml` substitutes them with real registry images and SHA tags. ArgoCD auto-detects `kustomization.yaml` and runs `kustomize build` before applying. CI's `update-manifests` job uses `kustomize edit set image` to update only the `kustomization.yaml` — not individual deployment files — keeping manifests clean and immutable. The CI pipeline uses `rsync` to copy canonical manifests from the app repo, ensuring the infra repo never drifts from the source of truth.

---

| Issue | What learners saw | Root cause | Fix (what we did) | Interview one-liner |
|---|---|---|---|---|
| **Empty dashboards after install** | Six dashboards exist, every panel says “No data” | Grafana is a **viewer** — it does not create events. Kyverno/Falco/app logs must happen first. | §7.4 lab: trigger denial, shell, failed login; set **Last 15 minutes** | *“Dashboards are empty until security events exist and the time range includes them.”* |
| **Loki `connection refused` in browser** | Log panels red; metrics panels OK | Loki pod **crash-looping** under heavy LogQL; Kubernetes **liveness probe** killed it while busy (1s timeout, no memory cap) | More memory + slower probes in `loki-stack-values.yaml`; shorter default dashboard ranges; Grafana query timeout | *“We separated ‘pod Running’ from ‘service accepting queries’ and right-sized Loki for a single-node lab.”* |
| **Opening all dashboards at once** | Loki restarts climb; everything goes empty | Six boards × 3h LogQL = query storm on one Loki replica | Open **one dashboard at a time**; default **1h/6h** not 3h/24h; cap `max_query_length` | *“We treated observability like production: rate-limit queries and load-test the path Grafana uses.”* |
| **`make check-7` passes but Stage 7 not done** | Health check green, screenshots still empty | Health check only tests **pods + `/ready`**, not “Falco alert visible” | Done checklist in §7.6: require **your** events + screenshots 1–3 | *“Synthetic checks prove uptime; product proof needs correlated events on named dashboards.”* |
| **Kyverno panel stays 0** | Terminal shows admission denied, Grafana shows 0 | Prometheus had not scraped yet, or no `request_allowed="false"` series in range | Wait 30–90s; use **Violations (last hour)** panel; confirm metric with PromQL in §7.2 | *“Admission denial is immediate; metrics are eventually consistent on scrape interval.”* |
| **Request Rate panel always empty** | Failed logins work, HTTP rate flat | Cluster runs old images without `/metrics`; PodMonitor had nothing to scrape | `git push` (CI → infra repo → ArgoCD) or lab shortcut `build-metrics-images.sh` + PodMonitor `clearledger-apps` | *“Logs and metrics are separate pipelines — Promtail does not replace Prometheus app metrics.”* |
| **Wrong Grafana dashboard links** | Console: `not correct url` / `skipping rendering` | Old dashboard UID/slug cached (em-dash vs hyphen) | UID-only URLs in §7.3; installer purges stale UIDs | *“We standardized dashboard UIDs in Git and treated Grafana URLs like API contracts.”* |
| **Only six dashboards (not 30+)** | “Where did Kubernetes / Node dashboards go?” | `defaultDashboardsEnabled: false` on purpose | ClearLedger sidecar imports only `clearledger` tag | *“We reduced noise for a security lab — one tag, six audit-focused boards.”* |
| **Audit Log dashboard empty** | Expected on MicroK8s | Cluster audit logs not shipped to Loki yet | Documented as future work; Falco + Kyverno + app logs still prove the lab | *“We scoped MVP observability to signals we actually emit; audit log shipping is a Phase 2 sink.”* |
| **Falco panels all "No data"** | Wrong rule names; libbpf noise; rules used only `k8smeta` | Promtail ships `falco` container JSON; custom rules output `Shell spawned in ClearLedger` | LogQL: `{namespace="falco", container="falco"} != "libbpf" \| json`; rules: `k8s.ns.name` OR `k8smeta.ns.name` | *“Dashboards must match the log line Promtail actually ingests.”* |
| **Failed login stat empty, log stream OK** | Stat used `$__range` + wrong substring | App logs say `Failed login attempt for …` | `instant` + `[1h]` + `\|= "Failed login attempt"` | *“Stat and log panels need different Loki query windows.”* |
| **Runtime Threats = No data** | PromQL metrics not in Prometheus | `falcosecurity_*` counters never scraped | Compliance panel uses Loki count of Falco `Critical` lines | *“Use logs when metrics are not wired.”* |
| **Pod Status = No data** | Wrong `condition="true"` label on `kube_pod_status_ready` | Metric is 0/1 per pod, no condition label | `sum(kube_pod_status_ready{namespace="clearledger"} == 1)` | *“Validate PromQL in Prometheus Explore before pasting into Grafana.”* |
| **Request Rate empty** | `http_requests_total` has no `namespace` label | PodMonitor only scrapes clearledger pods | `sum by (app) (rate(http_requests_total[$__rate_interval]))` | *“Counter labels must match what the app actually exports.”* |
| **Runtime Threat Trend empty** | LogQL panel wired to Prometheus | Compliance dashboard panel id 6 | Datasource **Loki** + same Falco LogQL as timeline | *“Datasource type must match query language.”* |
| **Kyverno stat 0, table > 0** | Stat used fixed `[1h]`, table used `$__range` | Align windows to dashboard time picker | Both use `$__range` after dashboard refresh | *“Stat and table panels must share the same time window.”* |
| **Kyverno stat 0, table shows 1.07** | 24h window + sparse counter | Event outside stat window | `ceil(sum(increase(...[1h])))` on stat panels | *“Pick a PromQL window that includes your test.”* |
| **Argo CD 503 / redirect loop** | Only `server.insecure` patched | Missing `server.grpc.web` and `server.url` | `stages/stage-2-gitops/infra/argocd-cmd-params.yaml` + ingress reload | *“Ingress-terminated TLS needs the full Argo CD server parameter set.”* |

**Story arc for interviews (30 seconds):**

> “We wired Stages 4–6 into Grafana with ServiceMonitors for Prometheus and Promtail for Loki. The hard part wasn’t Helm — it was proving the **full path**: terminal action → metric or log → panel. We hit Loki instability under query load, fixed probes and limits, and defined Stage 7 done only when **our** Kyverno denial and Falco CRITICAL alert appeared on named dashboards with screenshots.”

---

### 7.9 — Re-apply dashboards after wiring fixes

If panels were empty before the query fixes in this repo:

```bash
bash stages/stage-7-observability/scripts/install-observability.sh
SKIP_PROMPT=1 make demo-7
```

Set **Last 15 minutes**, then refresh each dashboard.

---

### 7.10 — After `make demo-7`: what each dashboard should look like

Ran on this lab cluster after `SKIP_PROMPT=1 make demo-7` (same as §7.4). Use this to compare your screen.

#### 1 — Kyverno Policy Violations

**URL:** http://grafana.local/d/clearledger-kyverno-violations?from=now-15m&to=now

| Panel | Expected appearance |
|---|---|
| **Policy Violations (24h)** | Large number ≥ 1 (may be red background) |
| **Violations (last hour)** | **≥ 1** — primary proof after Exercise A |
| **Active Policies** | Count of ready Kyverno policies (e.g. 5–10+, not zero) |
| **Violation Rate** | Line with a bump in the last ~15 minutes |
| **Top Violated Resource Kinds** | `Pod` bar visible |
| **Violations by Namespace** | `clearledger` line or bar |

**Terminal proof that matches:** `Error from server: admission webhook ... denied` listing `disallow-root-containers`, `require-resource-limits`, etc.

---

#### 2 — Security Event Timeline (Falco)

**URL:** http://grafana.local/d/clearledger-security-events?from=now-15m&to=now

| Panel | Expected appearance |
|---|---|
| **Falco Alerts by Priority** | Line or bar for **CRITICAL** (and maybe WARNING) in last 15m |
| **Alerts by Rule Name** | Slice for rules like **Terminal shell in container** |
| **Recent CRITICAL / WARNING Events** | Log lines: `priority=CRITICAL`, rule about **shell**, pod `auth-service-…` |
| **CRITICAL Alerts (period)** | Stat **≥ 1** |
| **WARNING Alerts (period)** | May be 0 or higher (background noise OK) |
| **Total Events (period)** | ≥ 1 |

**Terminal proof:** `kubectl exec … /bin/sh -c 'id && exit'` → Falco logs mention shell in container.

---

#### 3 — Service Health + Auth Security

**URL:** http://grafana.local/d/clearledger-service-health?from=now-15m&to=now

| Panel | Expected appearance |
|---|---|
| **Failed Login Attempts** | Stat **> 0** (after demo curl loop) |
| **Successful Logins** | May stay **0** — OK |
| **Transaction / large txn stats** | May stay 0 unless you generated ledger traffic |
| **Request Rate** | **Often empty** until CI deploys metrics-enabled images (§7.5) — not required for Stage 7 done |
| **Auth Service Logs** | Lines containing `Failed login attempt` |

---

#### 4 — Compliance Posture (auditor one-pager)

**URL:** http://grafana.local/d/clearledger-compliance?from=now-1h&to=now

| Top stat | Expected after full demo |
|---|---|
| **Policy Violations** | > 0 |
| **Runtime Threats** | > 0 |
| **Failed Auth Attempts** | > 0 |
| Control table lower on page | Tools listed **ACTIVE** (narrative, not live metrics) |

This is screenshot **#3** — three defenses in one frame.

---

#### 5 — Audit Log Analysis

**Empty on MicroK8s — by design, not a bug.** The dashboard queries `{job="kubernetes-audit"}` which requires the Kubernetes API server to write audit logs and Promtail to ship them to Loki. MicroK8s does not enable audit logging by default. This is documented as Phase 2 work. Do not use this dashboard alone to judge Stage 7 completion — the other five dashboards carry the proof.

---

#### 6 — DORA Metrics

Needs ArgoCD deploy activity to accumulate. Shows real data after multiple CI runs. After the pipeline fixes in Stage 7 (serialized builds, Trivy DB prep, Python 3.13 upgrade), you should see at least one successful deploy in the Deployment Frequency panel.

---

#### 7 — Request Rate (Service Health dashboard)

**Was empty until Stage 7 completes the full delivery chain.** Requires:

- App images built with `prom_metrics.py` middleware (`/metrics` endpoint) — added in this stage via CI
- PodMonitor `clearledger-apps` scraping the pods — installed by `install-observability.sh`
- Network policy allowing `monitoring` namespace ingress on port 8000 — fixed in this stage

Once all three are in place, `http_requests_total` appears in Prometheus and the Request Rate panel shows live traffic (confirmed at ~0.83 req/s after Stage 7 fixes).

---

### What you learned in Stage 7

- **Prometheus** proves countable security events (Kyverno denials, HTTP rates)
- **Loki** proves forensic detail (Falco JSON, auth log lines)
- **Grafana** is the narrative layer — not a second install step after the lab
- You can trace: **terminal action → backend signal → panel update**
- ServiceMonitors / PodMonitors are what connect Stages 4–6 to charts
- Empty dashboards mean “no events yet” or “wrong time range” — not “broken security”
- Compliance posture is how you answer an auditor in **one screen**
- Network policies must explicitly allow the `monitoring` namespace to reach app pods on port 8000, otherwise PodMonitor scrapes silently fail with `context deadline exceeded`
- Kubernetes Audit Log dashboard is empty on MicroK8s by design — the API server audit pipeline (audit-policy → file → Promtail → Loki) is not enabled by default
- Request Rate requires the full chain: app image with `/metrics`, PodMonitor, and network policy — any one missing means the panel stays empty

#### Stage 7 done checklist

- `make check-7` → 6/6 ✓ (Stage 6.5 Litmus failure is expected — scaled down for memory)
- `http://grafana.local/d/clearledger-kyverno-violations` — Violations stat > 0
- `http://grafana.local/d/clearledger-security-events` — CRITICAL Falco alert visible
- `http://grafana.local/d/clearledger-compliance` — Policy Violations + Runtime Threats + Failed Auth Attempts all > 0
- `http://grafana.local/d/clearledger-service-health` — Failed Login Attempts > 0, Request Rate > 0
- Portfolio screenshots 1–3 saved

---

## Stage 7.5 — OpenTelemetry (Optional)

> Metrics and logs tell you what happened. Traces tell you **where time was spent and which service caused the delay.**

**Goal:** send a real transaction and open Grafana Tempo to see its full journey: `POST /transactions` (ledger-service) → `GET /verify` (auth-service) → SQL INSERT (postgres) as a single waterfall with exact timings on each hop.

### What you need to know first

You have already seen what metrics and logs give you in Stage 7. Here is the gap they leave:

- **Prometheus** tells you `ledger-service had 50 requests in the last minute, 2 were errors`
- **Loki** tells you `request X logged a 500 error at 14:23:07`
- Neither tells you: which call inside ledger-service failed? Was it the auth-service JWT check, the Postgres write, or the Redis publish? And how long did each step take?

**Distributed tracing** answers this. Every request gets a **Trace ID** at the entry point. As it crosses service boundaries, each service adds a **Span** — a named, timed operation. The result is a waterfall diagram showing the complete call tree with exact durations.

**OpenTelemetry (OTel)** is the vendor-neutral standard for this. The ClearLedger services already have OTel instrumentation in the code (`opentelemetry-instrumentation-fastapi`, `opentelemetry-instrumentation-sqlalchemy`). They send spans via gRPC to an **OTel Collector**, which forwards them to **Grafana Tempo** for storage. Grafana then queries Tempo and renders the trace.

**Why your pods have been logging warnings since Stage 7:**

```
WARNING: Transient error StatusCode.UNAVAILABLE encountered while exporting traces
```

This is the OTel exporter in each app trying to reach `otel-collector.monitoring.svc.cluster.local:4317` — which doesn't exist yet. The app degrades gracefully (traces are dropped, everything else works). Stage 7.5 installs the collector and stops these warnings permanently.

---

### How the pipeline works

```
app pod (ledger-service)
  │  OTel SDK auto-instruments FastAPI + SQLAlchemy
  │  sends spans via gRPC to port 4317
  ▼
OTel Collector (monitoring namespace, port 4317)
  │  batches and forwards
  ▼
Grafana Tempo (monitoring namespace, port 4317 for OTLP, 3100 for query)
  │  stores traces
  ▼
Grafana → Explore → Tempo datasource → trace waterfall
```

---

### 7.5.1 — Check memory and load before starting

Tempo adds ~300MB. Confirm you have headroom and the node is not already saturated:

```bash
multipass exec clearledger -- free -h
# You need at least 1.5Gi available

multipass exec clearledger -- uptime
# load average (1m) should be below ~10 on a 4-CPU VM

bash scripts/health-check.sh 7
```

If memory is low or load is high, confirm Litmus is still scaled down (§7.0):

```bash
kubectl get pods -n litmus --field-selector=status.phase=Running
# Expected: no resources found
```

If Litmus pods are still Running, scale them down again before installing Tempo.

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
kubectl exec -n monitoring tempo-0 -- wget -qO- http://localhost:3100/ready
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

**Verify it can receive traces (check the collector logs):**

```bash
kubectl logs -n monitoring deploy/otel-collector --tail=10
# Expected: service started, no errors
```

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

---

### 7.5.7 — View the trace in Grafana

1. Open **http://grafana.local**
2. Left sidebar → **Explore** (compass icon)
3. Top datasource dropdown → select **Tempo**
4. Search type: **Search** tab
5. Service name: `ledger-service`
6. Click **Run query**
7. Click on the most recent trace

**What you should see:**

```
POST /transactions   (ledger-service)   ~50ms total
  ├── GET /verify    (auth-service)     ~12ms  ← JWT verification call
  ├── INSERT         (postgres)         ~8ms   ← database write
  └── PUBLISH        (redis)            ~2ms   ← notification trigger (if amount ≥ 10000)
```

Each bar is a span. The width is proportional to time spent. Clicking a span shows its attributes — the SQL query text, HTTP status code, service name.

**Connecting traces to logs:** Click any span → **Logs** tab → Grafana jumps to the matching Loki log entries for that pod at that exact timestamp.

**Take a screenshot of the trace waterfall.** This is your portfolio proof for Stage 7.5.

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

---

### What you learned in Stage 7.5

- The three observability signals and when each one is the right tool: metrics for aggregates, logs for forensics, traces for request journeys
- What a span is (a named, timed operation) and how spans nest to form a trace
- How W3C TraceContext headers propagate a Trace ID across service boundaries automatically — without changing business logic
- How to find performance bottlenecks: look at span durations to see which service or database call is the slowest
- Why OTel is vendor-neutral: the same instrumentation works with Tempo today and Datadog or Jaeger tomorrow with only a collector config change
- The collector pattern: apps never talk directly to storage — they talk to a collector, which routes to whatever backend you configure

### DevSecOps lesson — Stage 7.5 in one paragraph

**Observability is not one tool, it is three signals working together.** Prometheus told you ledger-service had an error spike. Loki told you which log line fired. Tempo told you the auth-service JWT check was taking 200ms because it was hitting a cold Postgres connection — that is the root cause, and neither metrics nor logs could show it alone. OpenTelemetry is the 2026 standard because it is vendor-neutral and already built into modern frameworks — you instrument once and route to whatever backend you choose. The collector in the middle is the routing layer: change the exporter config, not the application.

---

## Stage 8 — AWS Migration

> The architecture survives the migration because the contracts are portable.

**Goal:** the same application, the same security layers, running on AWS managed services instead of your laptop.

### Demo stack vs production

| | Demo stack (`make aws-up`) | Production add-ons (documented, not auto-applied) |
|---|---|---|
| Label | **Demo stack** — production-*shaped*, not production-*ready* | Production hardening checklist below |
| Deploy | ArgoCD app `clearledger-aws` → `stages/stage-8-aws-migration/manifests/` | Staging env → promote same SHA |
| TLS | HTTP ALB | `ingress-aws-https.example.yaml` + ACM |
| Observability | Stage 7 stack installed by spinup | Same + alert routing |
| CI | `ci-aws.yaml` — Gitleaks, Semgrep, Checkov, Trivy, Cosign | + full DAST against `AWS_DAST_BASE_URL` |

> **Do not** `kubectl apply` app Deployments on AWS after bootstrap. Git + ArgoCD is the contract (Stage 2). Spinup may apply kustomize **once** if Git is not pushed yet; push `kustomization.yaml` and let ArgoCD own the cluster.

### Secrets: three patterns (Vault → ESO → CSI)

| Pattern | Where | How pods get secrets |
|---|---|---|
| **1. Vault agent** | Homelab Stages 5–7 | Sidecar injects **files** at `/vault/secrets/*` |
| **2. ESO** | AWS Stage 8 (**this lab**) | Syncs Secrets Manager → **K8s Secret** → `secretKeyRef` / env |
| **3. CSI Driver** | AWS Stage 8 (installed + §8.5 exercise) | Mounts SM secrets as **files** — no Secret object in etcd |

```text
Vault:  SM/Vault KV → agent sidecar → /vault/secrets/database_url (file)
ESO:    Secrets Manager → ESO (IRSA) → K8s Secret → DATABASE_URL env
CSI:    Secrets Manager → CSI volume (IRSA on app SA) → /mnt/secrets/database_url (file)
```

**This lab uses ESO by default** (`manifests/deployments/auth-service.yaml` + `external-secrets.yaml`). **CSI is installed on every AWS spinup** (step 11) — SecretProviderClasses are in Git; the §8.5 exercise swaps auth to file mounts. See `manifests/csi/` and `docs/secrets-patterns.md`.

**IRSA** is how AWS trusts Kubernetes identities (ESO pod or app pod). No `AWS_ACCESS_KEY_ID` in Git or cluster config.

---

### 8.1 — Two ways through Stage 8

| Path | When to use it |
|---|---|
| **Quick** — `make aws-up` | You want the full demo stack fast (~45–60 min). Read §8.2 so you know what ran. |
| **Manual** — §8.3 step by step | You are learning AWS migration mechanics, interviewing, or debugging a failed spinup. |

> **Do not skip the manual section if you only ran `make aws-up`.** The Makefile wraps `aws-spinup.sh`; without §8.2–§8.5 you will not know what Terraform, ESO, CSI, or ArgoCD each contributed.

**Quick path:**

```bash
# Edit terraform/secrets.tf first — replace CHANGE_ME_BEFORE_APPLY
make aws-up    # wraps stages/stage-8-aws-migration/scripts/aws-spinup.sh
make aws-down  # destroys billable resources
```

---

### 8.2 — What `make aws-up` runs (15 steps)

| Step | Script banner | What it does |
|---|---|---|
| 1 | Prerequisites | `aws`, `terraform`, `kubectl`, `docker`, `helm`, `git`, `kustomize`; `aws sts get-caller-identity` |
| 2 | Terraform | VPC, EKS 1.31, RDS, ECR, ALB IAM, Secrets Manager, GuardDuty, CloudTrail, IRSA roles, GitHub OIDC role |
| 3 | GuardDuty & CloudTrail | Confirms detectors and trail logging |
| 4 | Build & push ECR | `docker build` + push auth/ledger/notification; optional Cosign sign |
| 5 | GitOps manifests | Patches `manifests/kustomization.yaml` with ECR registry + git SHA; patches ESO/CSI region |
| 6 | kubeconfig | `aws eks update-kubeconfig` |
| 7 | ArgoCD | Stable manifest install in `argocd` namespace |
| 8 | Kyverno | Helm install + `infra/policies/` ClusterPolicies |
| 9 | Falco | Helm + **falco** IRSA role (not ESO role) |
| 10 | ESO + IRSA SAs | External Secrets Operator + workload ServiceAccounts with IRSA annotations |
| 11 | **CSI driver** | `install-csi-secrets.sh` — Secrets Store CSI Driver + AWS provider + SecretProviderClasses |
| 12 | Observability | Stage 7 stack (`install-observability.sh`) |
| 13 | GitOps deploy | ArgoCD Application `clearledger-aws` → `stages/stage-8-aws-migration/manifests/` |
| 14 | ALB | Waits for `clearledger-ingress` hostname |
| 15 | Summary | Prints HTTP URL, tear-down reminder, pointer to §8.3 |

Default deploy uses **ESO** (step 10). Step 11 installs **CSI** so you can run §8.5 without reinstalling anything.

---

### 8.3 — Manual walkthrough

Run these yourself at least once. Paths are from the repo root.

**Before you start**

```bash
aws sts get-caller-identity
terraform --version
# Edit stages/stage-8-aws-migration/terraform/secrets.tf — no CHANGE_ME_BEFORE_APPLY
```

**Steps 1–2 — Terraform**

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

**Steps 3–4 — Security services + ECR images**

```bash
aws guardduty list-detectors
aws cloudtrail get-trail-status --name clearledger-trail

ECR_REGISTRY=$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw ecr_registry_url)
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY"
TAG=$(git rev-parse --short HEAD)
docker build -t "${ECR_REGISTRY}/clearledger/auth-service:${TAG}" app/auth-service && docker push ...
# Repeat for ledger-service, notification-service (or run step 4 block from aws-spinup.sh)
```

**Step 5 — GitOps source of truth**

```bash
# aws-spinup.sh sed-patches these — do the same manually or copy kustomization after spinup:
# stages/stage-8-aws-migration/manifests/kustomization.yaml  → ECR + tag
# manifests/external-secrets.yaml + manifests/csi/*.yaml       → region
git add stages/stage-8-aws-migration/manifests/
git commit -m "stage8: ECR images ${TAG}"
git push
```

**Step 6 — Cluster access**

```bash
eval "$(terraform -chdir=stages/stage-8-aws-migration/terraform output -raw kubeconfig_command)"
kubectl get nodes
```

**Steps 7–12 — Platform stack** (same order as spinup)

```bash
# 7 ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 8 Kyverno
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait
kubectl apply -f infra/policies/

# 9 Falco (use falco_role_arn from terraform output)
helm upgrade --install falco falcosecurity/falco -n falco --create-namespace \
  -f stages/stage-6-runtime-security/infra/falco/helm-values.yaml \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=FALCO_ROLE_ARN"

# 10 ESO + app ServiceAccounts (eso_role_arn + auth/ledger/notify IRSA from terraform)
helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=ESO_ROLE_ARN" --wait
export REPLACE_AUTH_IRSA_ROLE_ARN=...  # from terraform output
envsubst < stages/stage-8-aws-migration/manifests/clearledger-serviceaccounts.yaml | kubectl apply -f -

# 11 CSI driver + SecretProviderClasses
bash stages/stage-8-aws-migration/scripts/install-csi-secrets.sh

# 12 Observability
bash stages/stage-7-observability/scripts/install-observability.sh
```

**Steps 13–14 — Deploy via ArgoCD (not raw kubectl on Deployments)**

```bash
kubectl apply -f stages/stage-8-aws-migration/argocd/clearledger-aws-app.yaml
argocd app sync clearledger-aws   # or wait for auto-sync
kubectl get ingress clearledger-ingress -n clearledger
```

ArgoCD watches **`stages/stage-8-aws-migration/manifests/` in this repo** (app `clearledger-aws`). Homelab Stages 1–7 still use `clearledger-infra`; AWS Stage 8 uses the in-repo kustomize path so ESO/CSI manifests stay colocated.

---

### 8.4 — Verify ESO (default secret path)

After sync, confirm External Secrets pulled from Secrets Manager:

```bash
kubectl get externalsecret,secret -n clearledger
kubectl describe externalsecret auth-service-secrets -n clearledger | grep -A2 Status
kubectl get pods -n clearledger -l app=auth-service
kubectl exec -n clearledger deploy/auth-service -c auth-service -- env | grep DATABASE_URL
# Expect DATABASE_URL set from K8s Secret — not a file path
```

If `SecretSynced=False`, check ESO logs and IRSA:

```bash
kubectl logs -n external-secrets deploy/external-secrets -c external-secrets | tail -30
kubectl get sa auth-service -n clearledger -o yaml | grep role-arn
```

---

### 8.5 — Hands-on: CSI driver (file mounts)

CSI is **installed** at spinup step 11. Default pods still use ESO. This exercise switches **auth-service** to the same file-mount code path as Vault homelab (`DATABASE_URL_FILE` / `JWT_SECRET_FILE`).

**1. Confirm CSI is running**

```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get secretproviderclass -n clearledger
```

**2. Swap deployment in Git (GitOps)**

Edit `stages/stage-8-aws-migration/manifests/kustomization.yaml`:

```yaml
# Change:
  - deployments/auth-service.yaml
# To:
  - deployments/auth-service-csi.yaml
```

Commit, push, then:

```bash
argocd app sync clearledger-aws
kubectl rollout status deployment/auth-service -n clearledger
```

**3. Verify files inside the pod**

```bash
kubectl get pod -n clearledger -l secrets=csi
kubectl exec -n clearledger deploy/auth-service -c auth-service -- ls -la /mnt/secrets
kubectl exec -n clearledger deploy/auth-service -c auth-service -- sh -c 'wc -c /mnt/secrets/database_url'
curl -s "http://$(kubectl get ingress clearledger-ingress -n clearledger -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/auth/health"
```

**4. Compare ESO vs CSI**

| | ESO (default) | CSI (this exercise) |
|---|---|---|
| Secret in etcd? | Yes — K8s Secret object | No — volume mount only |
| Pod env | `DATABASE_URL` from `secretKeyRef` | `DATABASE_URL_FILE=/mnt/secrets/database_url` |
| IAM identity | IRSA on ESO SA (reads SM) | IRSA on **auth-service** SA (mounts SM) |
| App code | Same — `_read_secret()` in `app/auth-service/main.py` | Same |

Revert by switching kustomization back to `auth-service.yaml` and syncing.

---

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

When Terraform runs, it creates a role called `clearledger-github-actions-ecr`. The Stage 8 pipeline in `.github/workflows/ci-aws.yaml` assumes that role using OIDC, logs in to ECR, pushes images, then updates `stages/stage-8-aws-migration/manifests/kustomization.yaml` — ArgoCD app `clearledger-aws` syncs the cluster.

**After the stack is up** (§8.3 or `make aws-up`), configure GitHub for ongoing AWS CI:

```text
GitHub production environment secrets:
  GITHUB_ACTIONS_ROLE_ARN = terraform output github_actions_ecr_role_arn

GitHub Variables:
  AWS_ACCOUNT_ID = your 12-digit AWS account ID
  AWS_REGION     = eu-west-1
```

Run **CI — AWS (ECR + OIDC)** from the Actions tab (manual). Same gates as `ci.yaml`; updates `kustomization.yaml` in this repo — not `clearledger-infra`.

| Workflow | When it runs | Registry | GitOps target |
|---|---|---|---|
| `ci.yaml` | Push to `main` | Docker Hub | `clearledger-infra` (Stages 1–7) |
| `ci-aws.yaml` | Manual | ECR | `stages/stage-8-aws-migration/manifests/` |

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
main → ci-aws.yaml → update stages/stage-8-aws-migration/manifests/kustomization.yaml → ArgoCD clearledger-aws syncs
```

Homelab Stages 1–7 still use `clearledger-infra` + Docker Hub. Stage 8 AWS uses the in-repo kustomize path above.

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
kustomization.yaml (Stage 8 path) records desired state.
ArgoCD clearledger-aws deploys from Git.
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
- Three AWS secret delivery paths: ESO (default), CSI file mounts (§8.5), vs Vault on homelab
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
