# Deferred manifests (not for `clearledger-infra` at bootstrap)

Files here are **not** in the initial `clearledger-infra` push (Stage 1.3). Apply them manually at the stage named in the path.

| Path | Apply in | How |
|---|---|---|
| `stage-5-secrets-management/vault/` | **Stage 5** — Secrets Management | Add `rotation-cronjob.yaml` to `clearledger-infra/manifests/kustomization.yaml` after Vault is installed |
| `stage-6-runtime-security/netpol/` | **Stage 6** — Runtime Security | `kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml` |

**Why separate from `infra/manifests/`?**

`infra/manifests/` is the GitOps source of truth (pushed to `clearledger-infra`, synced by ArgoCD). Vault rotation needs a running Vault server. Network policies use default-deny and will break the app if ArgoCD applies them before Stage 6.

**If you already pushed `manifests/netpol/` or `manifests/vault/` to GitHub:** delete those folders from `clearledger-infra`, sync ArgoCD, then re-apply from this folder at the correct stage.
