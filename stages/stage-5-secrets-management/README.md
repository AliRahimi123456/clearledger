# Stage 5 — Secrets Management (HashiCorp Vault)

**Goal:** Delete Kubernetes app Secrets from Git and the cluster; the app keeps working because Vault injects credentials at runtime.

## Am I ready?

- [ ] `make check-4` passes — Kyverno policies enforcing, break-it scenarios worked
- [ ] Kyverno pods `1/1 Running` with **RESTARTS under 5**
- [ ] App still works at `http://clearledger.local` after Stage 4 policies applied

**Done when:** `make check-5` passes, K8s app Secrets deleted, login still works via Vault-injected files.

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 5](../../docs/LAB-GUIDE.md#stage-5--secrets-management-vault)** — `.env` bootstrap, Vault install, seed KV, GitOps migration, delete K8s Secrets, troubleshooting.

## Hands-on checkpoint

- Vault seeded (`setup.sh` + `seed-vault-secrets.sh`); `secret.yaml` removed from **`clearledger-infra`**
- Auth pods **`2/2`**; `ls /vault/secrets/` shows `database_url`, `jwt_secret`
- `kubectl get secret -n clearledger` — no auth/ledger app secrets; login curl returns `access_token`
- `make check-5` ends with **All checks passed. Ready for the next stage.**

## What you can now claim

> You moved app credentials out of Git and etcd into Vault. The app still runs after you deleted the Kubernetes Secrets — that is the proof.

---

## Reference

| Script | Purpose |
|---|---|
| `infra/vault/setup.sh` | K8s auth, KV mount, policies, roles |
| `infra/vault/seed-vault-secrets.sh` | `vault kv put` from gitignored `.env` `SEED_*` vars |

Order: `.env` → install Vault → setup → seed → push `clearledger-infra` → wait for `2/2` pods → delete K8s app Secrets.

---

## → Next: [Stage 6 — Runtime Security](../stage-6-runtime-security/README.md)
