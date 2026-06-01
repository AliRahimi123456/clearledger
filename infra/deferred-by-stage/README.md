# Deferred manifests (not for `clearledger-infra`)

Files here are **not** copied into `clearledger-infra` and are **not** applied by ArgoCD in Stages 1–2.

They live in this repo so you know what to turn on later, at the stage listed in the path.

| Path | Apply in | How |
|---|---|---|
| `stage-6-runtime-security/netpol/` | **Stage 6** — Runtime Security | `kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml` |

**Why separate from `infra/manifests/`?**

`infra/manifests/` is the GitOps source of truth (pushed to `clearledger-infra`, synced by ArgoCD). Network policies use default-deny and will break the app if ArgoCD applies them before Stage 6.

**If you already pushed `manifests/netpol/` to GitHub:** delete that folder from `clearledger-infra`, sync ArgoCD, then continue Stage 2. Re-apply netpol from this folder in Stage 6.
