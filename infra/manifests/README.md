# Kubernetes manifests → `clearledger-infra`

Everything under this folder is synced to **`clearledger-infra`** by CI and applied by **ArgoCD** from Stage 2 onward.

## Stage boundaries

| Stage | What `infra/manifests/` contains |
|---|---|
| **0** | Manual deploy uses `stages/stage-0-raw-kubernetes/infra/manifests/` for deployments only |
| **2–4** | `secretKeyRef` deployments + `auth-service/secret.yaml` and `ledger-service/secret.yaml` |
| **5** | Copy Vault deployments from `stages/stage-5-secrets-management/infra/manifests/`; delete app secrets from infra repo; add rotation CronJob from `infra/deferred-by-stage/stage-5-secrets-management/vault/` |

**Do not add Stage 6+ material here.** Deferred manifests live in [`../deferred-by-stage/`](../deferred-by-stage/README.md).

## Structure

| File / folder | Purpose |
|---|---|
| `kustomization.yaml` | Lists all resources; **CI updates image SHAs here**; replace `YOUR_DOCKERHUB_USERNAME` in Stage 1.3 |
| `*/deployment.yaml` | Placeholder images: `clearledger/<service>:gitops` |
| `auth-service/secret.yaml`, `ledger-service/secret.yaml` | Stages 2–4 only — removed from `clearledger-infra` at Stage 5 |

## How CI updates GitOps (prod pattern)

1. Copy this entire tree → `clearledger-infra/manifests/`
2. `kustomize edit set image clearledger/auth-service=registry/...:sha`
3. ArgoCD renders `kustomize build` and syncs

You edit deployments here; CI propagates them. Image tags are never edited by hand in GitOps.
