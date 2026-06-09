# Kubernetes manifests → `clearledger-infra`

Everything under this folder is synced to **`clearledger-infra`** by CI and applied by **ArgoCD** from Stage 2 onward.

## Structure

| File / folder | Purpose |
|---|---|
| `kustomization.yaml` | Lists all resources; **CI updates image SHAs here** |
| `*/deployment.yaml` | Placeholder images: `clearledger/<service>:gitops` |
| `auth-service/secret.yaml`, `ledger-service/secret.yaml` | **Local only** (Stages 0–4) — excluded from CI sync after Stage 5 |

**Do not add Stage 6+ material here.** Deferred manifests live in [`../deferred-by-stage/`](../deferred-by-stage/README.md).

## How CI updates GitOps (prod pattern)

1. Copy this entire tree → `clearledger-infra/manifests/`
2. `kustomize edit set image clearledger/auth-service=registry/...:sha`
3. ArgoCD renders `kustomize build` and syncs

You edit deployments here; CI propagates them. Image tags are never edited by hand in GitOps.
