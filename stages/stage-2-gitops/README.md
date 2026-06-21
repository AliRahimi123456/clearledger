# Stage 2 — GitOps with ArgoCD

**Goal:** Git is the single source of truth — ArgoCD syncs the cluster to `clearledger-infra`; the pipeline never runs `kubectl` again.

## Am I ready?

- [ ] `make check-1` passes — CI green, infra repo on GitHub with secrets
- [ ] Verified on GitHub: `auth-service/deployment.yaml` uses `secretKeyRef` (no Vault annotations yet)
- [ ] `http://clearledger.local` still healthy

**Done when:** `make check-2` passes and `http://argocd.local` shows ArgoCD syncing `clearledger` (`Synced` / `Healthy`).

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 2](../../docs/LAB-GUIDE.md#stage-2--gitops-with-argocd)** — pre-sync Git verification, ArgoCD install, Application manifest, first sync, drift/rollback exercises.

## Hands-on checkpoint

- `repoURL` in `stages/stage-2-gitops/argocd/clearledger-app.yaml` points at **your** `clearledger-infra`
- App pods `Running`; Application `sync=Synced health=Healthy`
- `curl` auth health **200**; logs show requests — not `DATABASE_URL is not set`
- `make check-2` green

## What you can now claim

> **GitOps means the cluster reconciles to Git automatically** — you can prove drift is corrected (`selfHeal`) and roll back via Git history, not manual `kubectl`.

---

## Reference

| File | Purpose |
|---|---|
| `stages/stage-2-gitops/argocd/clearledger-app.yaml` | ArgoCD Application (patch `YOUR_GITHUB_USERNAME`) |
| `stages/stage-2-gitops/infra/argocd-ingress.yaml` | `argocd.local` ingress |
| `clearledger-infra/manifests/` | GitOps source of truth |

Network policies are **Stage 6** — not in `infra/manifests/` yet.

---

## → Next: [Stage 3 — Security Gates](../stage-3-security-gates/README.md)
