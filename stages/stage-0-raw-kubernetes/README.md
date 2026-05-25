# Stage 0 — Raw Kubernetes

> **The starting point:** ClearLedger runs on Kubernetes. You deployed it
> entirely with `kubectl`. No automation. No pipelines. No GitOps.
> You understand exactly what you are responsible for.

---

## What You Will Learn

- How to provision a local Kubernetes cluster with Multipass + MicroK8s
- How to build and push container images to Docker Hub
- What Deployments, StatefulSets, Services, Secrets, and Ingress objects actually do
- How to debug pods that won't start
- Why manual deployments do not scale — and why that discomfort matters

---

## What You Are Deploying

| Component | Type | Notes |
|---|---|---|
| `frontend` | Deployment (1 replica) | Static SPA — login, dashboard, transactions |
| `auth-service` | Deployment (2 replicas) | JWT auth, PostgreSQL backend |
| `ledger-service` | Deployment (2 replicas) | Transactions, Redis pub/sub |
| `notification-service` | Deployment (1 replica) | Redis subscriber |
| RBAC | `infra/manifests/rbac/rbac.yaml` | Per-SA Role: `get`/`list` **endpoints** only; `clearledger-viewer`; no Secret API for workloads |
| `postgres` | StatefulSet | Persistent storage |
| `redis` | Deployment | In-memory pub/sub |
| Ingress | nginx | Routes by path prefix |

---

## Prerequisites

Complete [QUICKSTART.md](../../QUICKSTART.md) first. Cluster must be running.

---

## Steps

### 1. Build and Push Images

```bash
docker login
# Enter your Docker Hub username and access token

# Replace YOUR_USERNAME with your Docker Hub username
DOCKER_USERNAME=your-username

docker build -t $DOCKER_USERNAME/clearledger-auth-service:v0.1.0 ./app/auth-service
docker build -t $DOCKER_USERNAME/clearledger-ledger-service:v0.1.0 ./app/ledger-service
docker build -t $DOCKER_USERNAME/clearledger-notification-service:v0.1.0 ./app/notification-service
docker build -t $DOCKER_USERNAME/clearledger-frontend:v0.1.0 ./app/frontend

docker push $DOCKER_USERNAME/clearledger-auth-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-ledger-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-notification-service:v0.1.0
docker push $DOCKER_USERNAME/clearledger-frontend:v0.1.0
```

### 2. Deploy — Order Matters

```bash
# Replace the placeholder in Stage 0 manifests (do not commit this change)
sed -i "s|DOCKER_USERNAME|your-actual-username|g" \
  infra/manifests/auth-service/deployment.yaml \
  infra/manifests/ledger-service/deployment.yaml \
  infra/manifests/notification-service/deployment.yaml \
  infra/manifests/frontend/deployment.yaml

# Namespace first — everything else depends on it
kubectl apply -f infra/manifests/namespace.yaml

# Database secrets and PostgreSQL
kubectl apply -f infra/manifests/postgres/postgres-secret.yaml
kubectl apply -f infra/manifests/postgres/postgres.yaml

# Wait for Postgres to be ready before starting the app services
kubectl wait --for=condition=ready pod -l app=postgres \
  -n clearledger --timeout=120s

# Redis
kubectl apply -f infra/manifests/redis/redis.yaml

# ServiceAccounts + namespace RBAC (least privilege) — before workloads
kubectl apply -f infra/manifests/rbac/rbac.yaml

# Application secrets and services
kubectl apply -f infra/manifests/auth-service/secret.yaml
kubectl apply -f infra/manifests/auth-service/deployment.yaml
kubectl apply -f infra/manifests/ledger-service/secret.yaml
kubectl apply -f infra/manifests/ledger-service/deployment.yaml
kubectl apply -f infra/manifests/notification-service/deployment.yaml
kubectl apply -f infra/manifests/frontend/deployment.yaml

# Ingress
kubectl apply -f infra/manifests/ingress.yaml
```

### 0.6 — Apply RBAC (Least Privilege Service Accounts)

The **default** ServiceAccount in a namespace typically receives only the
`system:discovery` cluster role binding (read-only discovery) in stock clusters,
but workloads should **never** rely on it: any accidental `ClusterRoleBinding`
elsewhere, or a permissive distribution default, can widen blast radius. ClearLedger
runs each app under its **own** ServiceAccount with a **Role** that grants only
`get` and `list` on **Endpoints** (enough for patterns that resolve Services via the
API). **No** `secrets` verbs — Stage 0 still mounts credentials with `secretKeyRef`
(the kubelet populates volumes); Stage 5 moves credentials to Vault files.

| Account | Role | Why |
|---------|------|-----|
| `auth-service` | `auth-service` Role | Endpoints read — no Secret API access |
| `ledger-service` | `ledger-service` Role | Same |
| `notification-service` | `notification-service` Role | Same |
| `clearledger-viewer` | `clearledger-viewer` Role | Read-only platform view (`pods`, `services`, `endpoints`, `events`, `configmaps`) — **never** Secrets |
| `default` | `RoleBinding` → ClusterRole `clearledger-deny-secrets` | Documents intent (RBAC cannot deny; see comments in `rbac.yaml`) |

Verify restrictions:

```bash
kubectl auth can-i get secrets \
  --as=system:serviceaccount:clearledger:auth-service -n clearledger
# Expected: no

kubectl auth can-i get endpoints \
  --as=system:serviceaccount:clearledger:auth-service -n clearledger
# Expected: yes

kubectl auth can-i get pods \
  --as=system:serviceaccount:clearledger:clearledger-viewer -n clearledger
# Expected: yes

kubectl auth can-i get secrets \
  --as=system:serviceaccount:clearledger:clearledger-viewer -n clearledger
# Expected: no
```

Template for Stage 0 lives at `stages/stage-0-raw-kubernetes/infra/rbac/rbac.yaml`
(keep in sync with `infra/manifests/rbac/rbac.yaml`).

### 3. Watch Everything Come Up

```bash
kubectl get pods -n clearledger -w
```

Expected state:
```
NAME                                    READY   STATUS    RESTARTS
auth-service-xxx                        1/1     Running   0
auth-service-yyy                        1/1     Running   0
ledger-service-xxx                      1/1     Running   0
ledger-service-yyy                      1/1     Running   0
notification-service-xxx                1/1     Running   0
postgres-0                              1/1     Running   0
redis-xxx                               1/1     Running   0
```

---

## Verify the System

> If a command returns an error, check that all pods are Running first:
> `kubectl get pods -n clearledger`
> If any pod shows Error or CrashLoopBackOff, check:
> `kubectl describe pod POD_NAME -n clearledger`

```bash
# Register a user
curl -s -X POST http://clearledger.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test@clearledger.io", "password": "SecurePass123"}' | jq .
#
# Expected:
# {
#   "user_id": "a1b2c3d4-...",
#   "email": "test@clearledger.io"
# }

# Login and capture the JWT
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "test@clearledger.io", "password": "SecurePass123"}' \
  | jq -r .access_token)
#
# Expected:
# {
#   "access_token": "eyJ...",
#   "token_type": "bearer",
#   "user_id": "a1b2c3d4-..."
# }

echo "Token: $TOKEN"

# Credit transaction
curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount": 5000.00, "direction": "credit", "description": "Salary"}' | jq .
#
# Expected:
# {
#   "id": "tx-uuid-...",
#   "user_id": "a1b2c3d4-...",
#   "amount": 5000.0,
#   "direction": "credit",
#   "description": "Salary",
#   "created_at": "2025-..."
# }

# Large transaction — triggers a notification alert
curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount": 15000.00, "direction": "debit", "description": "Property payment"}' | jq .

# Check balance
curl -s http://clearledger.local/ledger/balance \
  -H "Authorization: Bearer $TOKEN" | jq .
#
# Expected:
# {
#   "user_id": "a1b2c3d4-...",
#   "balance": -10000.0
# }
# (5000 credit - 15000 debit = -10000)

# Check alerts — the large transaction should appear here
curl -s http://clearledger.local/notifications/alerts | jq .
#
# Expected (the 15000 transaction triggered the threshold):
# {
#   "total": 1,
#   "alerts": [{
#     "alert_id": "ALT-0001",
#     "type": "LARGE_TRANSACTION",
#     "amount": 15000.0,
#     ...
#   }]
# }
```

---

## Access the Web UI

Open your browser:

```
http://clearledger.local
```

Register an account, log in, and create a few transactions.
Create one transaction over $10,000 — watch the alert appear.

This is the same data you have been creating with curl commands.
The UI calls the same API. The DevSecOps pipeline secures both.

---

## Feel the Pain Point

Now simulate a bug fix. You need to deploy v0.2.0:

```bash
# Build and push the new version
docker build -t $DOCKER_USERNAME/clearledger-auth-service:v0.2.0 ./app/auth-service
docker push $DOCKER_USERNAME/clearledger-auth-service:v0.2.0

# Manually update the running deployment
kubectl set image deployment/auth-service \
  auth-service=$DOCKER_USERNAME/clearledger-auth-service:v0.2.0 \
  -n clearledger
```

Now ask yourself:
- What if someone else applies the old manifest while you are asleep?
- How do you know what is running vs what is in Git?
- How do you roll back if v0.2.0 is broken?
- What is the audit trail for this change?

You have no good answers. **That feeling is the lesson.** Stage 1 solves the build.
Stage 2 solves the deploy. You need to feel both problems before fixing them.

---

## What the Cluster Looks Like Now

```
Manual builds → Manual kubectl apply → Cluster
                                          ↑
                              No link to Git. No audit trail.
                              Anyone with kubectl access can
                              change anything, anytime.
```

---

## What Is Still Broken

Everything. This is intentional. The problems in order:

1. **Builds are manual** — Stage 1 fixes this
2. **Deploys are manual** — Stage 2 fixes this
3. **No security scanning** — Stage 3 fixes this
4. **Cluster has no policy enforcement** — Stage 4 fixes this
5. **Secrets are in Git and etcd in plaintext** — Stage 5 fixes this
6. **No runtime threat detection** — Stage 6 fixes this
7. **No visibility into security posture** — Stage 7 fixes this

---

## Before You Move On

Run the health check to confirm this stage is working:

```bash
bash scripts/health-check.sh 0
```

Green output = ready for the next stage.
Red output = something needs fixing. The message tells you what.

## → Next: [Stage 1 — CI Pipeline](../stage-1-ci-pipeline/README.md)
