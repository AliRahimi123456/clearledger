# Stage 5 — Secrets Management (HashiCorp Vault)

> **The problem you felt in Stage 4:** Policies enforce pod shape, but credentials still sit in
> `secret.yaml` in Git and in etcd. Kyverno cannot fix that.
>
> **What changes here:** Application credentials live in **Vault KV only**. A gitignored
> **`.env`** bootstraps Vault once — nothing secret is committed. ArgoCD deploys
> Vault-injected manifests from **`clearledger-infra`** with app `secret.yaml` files removed.

See **[LAB-GUIDE.md § Stage 5](../../docs/LAB-GUIDE.md#stage-5--secrets-management-vault)** for the full walkthrough (example outputs, troubleshooting).

---

## Quick path

```bash
cp stages/stage-5-secrets-management/.env.example stages/stage-5-secrets-management/.env
# Edit VAULT_TOKEN and SEED_* — see lab guide §5.1

set -a && source stages/stage-5-secrets-management/.env && set +a
# helm install vault ... (§5.2 — use upgrade --install if already installed)
kubectl apply -f stages/stage-5-secrets-management/infra/vault-ingress.yaml

bash stages/stage-5-secrets-management/infra/vault/setup.sh
bash stages/stage-5-secrets-management/infra/vault/seed-vault-secrets.sh

# GitOps — §5.4: cp deployments to clearledger-infra, rm secret.yaml, git push
# Wait for auth pods 2/2 — §5.5, then delete K8s app secrets
make check-5   # §5.7
```

---

## Scripts (no credentials inside)

| Script | Purpose |
|---|---|
| `infra/vault/setup.sh` | K8s auth, KV mount, policies, roles |
| `infra/vault/seed-vault-secrets.sh` | `vault kv put` from `.env` `SEED_*` vars |

---

## → Next: [Stage 6 — Runtime Security](../stage-6-runtime-security/README.md)
