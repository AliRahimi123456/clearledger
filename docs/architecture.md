# ClearLedger Architecture

## Services

### auth-service (FastAPI)

Responsibilities: user registration, login, JWT issuance, token verification.

**API endpoints:**
- `POST /register`: create a new user
- `POST /login`: authenticate and receive a JWT
- `GET /verify`: validate a JWT (called by ledger-service on every request)
- `GET /health`: health check

**Dependencies:** PostgreSQL

**Secret injection:** database_url, jwt_secret (via Vault agent in Stage 5+)

---

### ledger-service (FastAPI)

Responsibilities: create transactions, return balance, list transaction history.

**API endpoints:**
- `POST /transactions`: create a credit or debit transaction
- `GET /balance`: return current balance for the authenticated user
- `GET /transactions`: list the last 100 transactions
- `GET /health`: health check

**Dependencies:** PostgreSQL, Redis (pub/sub), auth-service (JWT verification)

**Event pattern:** When a transaction exceeds the notification threshold (default $10,000),
ledger-service publishes a `large_transaction` event to the `ledger-events` Redis channel.

**Secret injection:** database_url (via Vault agent in Stage 5+)

---

### notification-service (FastAPI)

Responsibilities: subscribe to ledger events, maintain an alert log, expose alerts via API.

**API endpoints:**
- `GET /alerts`: return the last 50 transaction alerts
- `GET /health`: health check

**Dependencies:** Redis (subscriber)

**Pattern:** A background thread subscribes to `ledger-events` at startup.
Large transaction events become alerts stored in memory (replace with a database in production).

---

## Data Flow

![ClearLedger Data Flow](../assets/images/dataflow.png)

```
User
 │
 ▼ POST /auth/register or /auth/login
auth-service ──► PostgreSQL (users table)
 │
 ◄── JWT token
 │
 ▼ POST /ledger/transactions (Authorization: Bearer TOKEN)
ledger-service ──► auth-service /verify (validates JWT)
              ──► PostgreSQL (transactions table)
              ──► Redis publish (if amount ≥ threshold)
 │
notification-service ◄── Redis subscribe (background thread)
                     ──► in-memory alerts[]
```

---

## Security Layers by Stage

| Stage | Layer | Mechanism |
|---|---|---|
| 0 | Container isolation | Non-root user, readOnlyRootFilesystem, drop ALL caps |
| 3 | Pipeline gates | Gitleaks, Semgrep, Checkov, Trivy, Syft, Cosign |
| 4 | Admission control | Kyverno ClusterPolicies |
| 5 | Secret management | HashiCorp Vault + agent sidecar injection |
| 6 | Runtime detection | Falco eBPF + custom rules |
| 6 | Network isolation | Kubernetes NetworkPolicy (default-deny-all) |
| 7 | Observability | Grafana + Prometheus + Loki |

---

## Namespace Layout

All ClearLedger workloads run in the `clearledger` namespace.
Supporting infrastructure uses dedicated namespaces:

| Namespace | Contents |
|---|---|
| `clearledger` | auth-service, ledger-service, notification-service, postgres, redis |
| `argocd` | ArgoCD GitOps controller |
| `kyverno` | Kyverno admission controller |
| `vault` | HashiCorp Vault |
| `falco` | Falco DaemonSet + Falcosidekick |
| `monitoring` | Prometheus, Grafana, Loki, Promtail |
| `external-secrets` | External Secrets Operator (Stage 8) |

---

## Image Registry

**All stages:** Docker Hub at `hub.docker.com`.
Images are public. No authentication needed to pull.
Authentication (DOCKER_USERNAME + DOCKER_PASSWORD secrets) is only needed
to push from the CI pipeline.

**Stage 8 (AWS):** You can continue using Docker Hub or migrate to Amazon ECR.
The Stage 8 Terraform creates ECR repositories as an alternative.
Both work identically with ArgoCD and Kyverno.

---

## DNS Resolution

All services are reached via `/etc/hosts` entries on the host machine.
The Multipass VM IP maps to:

| Domain | Service | Stage Introduced |
|---|---|---|
| `clearledger.local` | nginx ingress → app services | 0 |
| `argocd.local` | ArgoCD UI | 2 |
| `vault.local` | Vault UI | 5 |
| `falco.local` | Falcosidekick UI | 6 |
| `litmus.local` | Litmus ChaosCenter UI | 6.5 |
| `grafana.local` | Grafana UI | 7 |
