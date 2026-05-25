# Stage 5 — Secrets Management (HashiCorp Vault)

> **The problem you felt in Stage 4:** Your policies enforce what runs.
> Your pipeline scans what builds. But open `infra/manifests/auth-service/secret.yaml`.
> The database password is right there. In Git. In etcd. Readable by anyone
> with `kubectl get secret -n clearledger` access. Kyverno cannot fix this.
>
> **What changes here:** No plaintext secrets anywhere. Not in Git, not in
> manifests, not in etcd. Vault holds the credentials. Vault's agent sidecar
> injects them into the pod at startup as files. The app reads files. Nothing
> is hardcoded anywhere.

---

## What You Will Learn

- How Vault's Kubernetes auth method works (the trust chain, step by step)
- How the Vault agent sidecar injects secrets without changing app code
- How to write Vault policies with least-privilege access
- What happens when you delete the K8s Secrets — and why nothing breaks
- Why secret rotation becomes trivial with this pattern

---

## What You Are Installing

| Tool | Purpose |
|---|---|
| HashiCorp Vault | Secret store + dynamic credential injection |
| Vault Helm chart | Runs Vault as a Kubernetes-native StatefulSet |

---

## Prerequisites

- Stage 4 complete — Kyverno policies enforcing pod security

---

## The Trust Chain (Read This Before Running Anything)

When a pod starts, Vault authenticates it via the Kubernetes API:

```
1. Pod starts with a Kubernetes service account JWT (auto-mounted)
2. Vault agent reads the JWT from /var/run/secrets/kubernetes.io/serviceaccount/token
3. Vault agent sends: "I am auth-service in namespace clearledger, here is my JWT"
4. Vault calls the Kubernetes TokenReview API to validate the JWT
5. Kubernetes confirms: "Yes, this is a valid auth-service service account token"
6. Vault issues a short-lived Vault token scoped to the auth-service policy
7. Vault agent uses the Vault token to read clearledger/data/auth-service
8. Vault agent writes the secrets to /vault/secrets/database_url and /vault/secrets/jwt_secret
9. App container reads the files — never sees a Vault token, never sees a credential URL
```

The pod never has hardcoded credentials. It earns a time-limited Vault token
by proving its Kubernetes identity.

---

## Steps

### 1. Install Vault

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken="root-dev-token" \
  --set ui.enabled=true

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault \
  -n vault --timeout=120s
```

Add Vault ingress:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: vault
spec:
  ingressClassName: nginx
  rules:
    - host: vault.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vault-ui
                port:
                  number: 8200
EOF
```

Access Vault at `http://vault.local` — token: `root-dev-token`

### 2. Configure Vault Kubernetes Auth

```bash
kubectl exec -n vault vault-0 -- vault login root-dev-token

kubectl exec -n vault vault-0 -- vault auth enable kubernetes

kubectl exec -n vault vault-0 -- \
  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

### 3. Store Secrets in Vault

```bash
kubectl exec -n vault vault-0 -- vault secrets enable -path=clearledger kv-v2

kubectl exec -n vault vault-0 -- \
  vault kv put clearledger/auth-service \
    database_url="postgresql://clearledger:$(openssl rand -base64 12)@postgres:5432/clearledger" \
    jwt_secret="$(openssl rand -base64 64)"

kubectl exec -n vault vault-0 -- \
  vault kv put clearledger/ledger-service \
    database_url="postgresql://clearledger:$(openssl rand -base64 12)@postgres:5432/clearledger"

kubectl exec -n vault vault-0 -- \
  vault kv put clearledger/postgres \
    username="clearledger" \
    password="$(openssl rand -base64 12)"
```

### 4. Create Vault Policies (Least Privilege)

```bash
kubectl exec -n vault vault-0 -- vault policy write auth-service - <<'EOF'
path "clearledger/data/auth-service" {
  capabilities = ["read"]
}
EOF

kubectl exec -n vault vault-0 -- vault policy write ledger-service - <<'EOF'
path "clearledger/data/ledger-service" {
  capabilities = ["read"]
}
EOF
```

Each service reads only its own secrets. Cross-service secret access is denied by default.

### 5. Create Kubernetes Auth Roles

```bash
# ServiceAccounts are defined in infra/manifests/rbac/rbac.yaml (apply if not already):
kubectl apply -f infra/manifests/rbac/rbac.yaml

kubectl exec -n vault vault-0 -- \
  vault write auth/kubernetes/role/auth-service \
    bound_service_account_names=auth-service \
    bound_service_account_namespaces=clearledger \
    policies=auth-service \
    ttl=1h

kubectl exec -n vault vault-0 -- \
  vault write auth/kubernetes/role/ledger-service \
    bound_service_account_names=ledger-service \
    bound_service_account_namespaces=clearledger \
    policies=ledger-service \
    ttl=1h
```

### 6. Apply Updated Deployments and RBAC

The updated files in `stages/stage-5-secrets-management/infra/manifests/`
replace `secretKeyRef` env vars with Vault agent annotations. ServiceAccounts
live in `infra/manifests/rbac/rbac.yaml` (synced from `stages/.../infra/rbac/rbac.yaml`).
Vault binds to the existing `auth-service` / `ledger-service` accounts.

```bash
# Copy updated deployments
cp stages/stage-5-secrets-management/infra/manifests/auth-service/deployment.yaml \
   infra/manifests/auth-service/deployment.yaml
cp stages/stage-5-secrets-management/infra/manifests/ledger-service/deployment.yaml \
   infra/manifests/ledger-service/deployment.yaml

# Sync RBAC + ServiceAccounts (includes clearledger-viewer and default SA binding)
cp stages/stage-5-secrets-management/infra/rbac/rbac.yaml \
   infra/manifests/rbac/rbac.yaml

# Commit to the infra repo — ArgoCD applies everything
git add infra/manifests/
git commit -m "feat: add Vault agent injection and service accounts (Stage 5)"
git push
```

ArgoCD will reconcile RBAC (ServiceAccounts + Roles) and the updated Deployments.
The Vault agent sidecar injects on pod startup (`automountServiceAccountToken: true`
is required on Vault-enabled workloads so the agent can read the projected SA JWT).

### 7. Delete the Old K8s Secrets

```bash
kubectl delete secret auth-service-secret -n clearledger
kubectl delete secret ledger-service-secret -n clearledger

# Verify they are gone
kubectl get secrets -n clearledger
# No auth-service-secret or ledger-service-secret. Good.
```

### 8. Verify Vault Injection

```bash
# Watch the vault-agent-init container pull secrets at pod startup
kubectl logs -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c vault-agent-init

# Verify secret files exist inside the pod
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- ls /vault/secrets/
# database_url  jwt_secret

# Verify the app still works — credentials come from Vault now
curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "test@clearledger.io", "password": "SecurePass123"}' | jq .
```

### 9. Rotate a secret (Vault is not one-time bootstrap)

PCI and SOC programs expect **rotation**, not only initial injection.

1. **Inspect current data** (KV v2 path is `clearledger/data/auth-service` in the API, but the CLI often uses the mount alias you configured in earlier steps):

```bash
kubectl exec -n vault vault-0 -- vault kv get clearledger/auth-service
```

2. **Write a new `database_url`** while keeping `jwt_secret` unchanged (replace the URL with one that matches a real password you set in Postgres for this exercise):

```bash
kubectl exec -n vault vault-0 -- vault kv put clearledger/auth-service \
  database_url="postgresql://clearledger:NEW_STRONG_PASS@postgres:5432/clearledger" \
  jwt_secret="PASTE_EXISTING_JWT_SECRET_FROM_STEP_1"
```

3. **Reload files in the workload** — with `vault.hashicorp.com/agent-pre-populate-only: "false"`,
the Vault agent sidecar refreshes injected templates without a pod restart.
Wait for the renewal/refresh cycle and confirm the file content changed:

```bash
echo "Waiting 65 seconds for Vault agent renewal cycle..."
sleep 65

kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- sh -lc 'cat /vault/secrets/jwt_secret | head -1 | cut -c1-10'
```

4. **Verify** health and login (update the JSON password if you changed the DB user password and your test user row was recreated):

```bash
curl -s http://clearledger.local/auth/health | jq .
curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "test@clearledger.io", "password": "SecurePass123"}' | jq .
```

5. **JWT secret rotation** in production is safest with an overlap window (accept old + new during token TTL),
then remove the old key. The rotation script in `scripts/rotate-secret.sh` demonstrates this pattern so
previously issued tokens remain valid while new tokens are signed with the new key.

---

## 5.7 — Secret Rotation (The Ongoing Operational Requirement)

Installing Vault is not secrets management. **Rotating secrets is secrets management.**

PCI‑DSS **8.3.9** requires passwords used by applications to be changed at least every **90 days**.
Without automation, rotation becomes a 3am manual operation every quarter.
With Vault agent injection, rotation becomes a controlled change you can do during business hours.

This stage includes two rotation demonstrations:

### Scenario A — JWT secret rotation (stateless)

JWT rotation can be **zero downtime** and **zero pod restarts** because the
Vault agent sidecar refreshes injected templates.

```bash
chmod +x stages/stage-5-secrets-management/scripts/rotate-secret.sh
BASE_URL=http://clearledger.local bash stages/stage-5-secrets-management/scripts/rotate-secret.sh
```

### Scenario B — Database credential rotation (stateful)

Database rotation requires coordination because the database must accept both old and new credentials
during a brief overlap period (intentional).

```bash
chmod +x stages/stage-5-secrets-management/scripts/rotate-db-credentials.sh
BASE_URL=http://clearledger.local bash stages/stage-5-secrets-management/scripts/rotate-db-credentials.sh
```

Correct order of operations:
1. Create new DB user
2. Update Vault
3. Wait for Vault agent refresh
4. Drop old user / rename new

### Vault metadata: version history

```bash
kubectl exec -n vault vault-0 -- vault kv metadata get clearledger/auth-service
```

Vault KV v2 keeps a version history (default **10 versions**) so rollback is always available.

### Production pattern: rotate on a schedule

CronJob scaffold (monthly):
`infra/manifests/vault/rotation-cronjob.yaml`

This is the production pattern: automated rotation on schedule with deadlines to avoid stuck runs.

## The Learning Moment

The app works identically. But now:

```bash
# This reveals nothing:
cat infra/manifests/auth-service/deployment.yaml
# No passwords. No connection strings. Just Vault annotations.

# This reveals nothing:
kubectl get secret -n clearledger
# No auth-service-secret. No ledger-service-secret. Gone.

# The only place the credentials exist:
kubectl exec -n vault vault-0 -- vault kv get clearledger/auth-service
# And only someone with Vault access can run this.
```

If someone reads your Git repo, your manifests, your etcd backup — they find
no credentials. The credentials exist only in Vault, pulled fresh at pod startup.

---

## What the Cluster Looks Like Now

```
git push → [gates] → [ArgoCD] → [Kyverno] → Pod starts
                                                │
                                         [Vault agent sidecar]
                                                │
                                    Authenticates with cluster JWT
                                                │
                                    Reads clearledger/data/auth-service
                                                │
                                    Writes /vault/secrets/database_url
                                                │
                                    App reads file — no hardcoded credentials
```

---

## What Is Still Broken

The pipeline enforces gates. Kyverno enforces policy. Vault protects secrets.
But what is happening *inside* the running pods right now?

If an attacker executes a command injection via the API, they get a shell
inside your pod. That shell can read `/vault/secrets/database_url`. It can
make outbound connections to their server. It can install tools. And you
would have no idea until it's too late.

**Stage 6 adds runtime threat detection with Falco.**

---

---

## Before You Move On

Run the health check to confirm this stage is working:

```bash
bash scripts/health-check.sh 5
```

Green output = ready for the next stage.
Red output = something needs fixing. The message tells you what.

## → Next: [Stage 6 — Runtime Security](../stage-6-runtime-security/README.md)
