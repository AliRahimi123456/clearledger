# Stage 8 — AWS Migration

**Goal:** The same application and security layers on AWS (EKS, ECR, RDS, ALB) — swap endpoints, not architecture.

## Am I ready?

- [ ] Homelab complete through Stage 7 (Stage 7.5 optional)
- [ ] `make check-7` passes (and `make check-75` if you did traces)
- [ ] AWS account with billing alerts — `make aws-up` creates billable resources

**Done when:** app reachable on AWS ALB, ArgoCD syncing `clearledger-aws`, and you run `make aws-down` when finished to stop charges.

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 8](../../docs/LAB-GUIDE.md#stage-8--aws-migration)** — Terraform (`make aws-up`), ESO secrets, ArgoCD app, CI OIDC to ECR, production hardening checklist, teardown.

## Hands-on checkpoint

- `make aws-up` completes; `kubectl get nodes` shows EKS workers
- ArgoCD Application `clearledger-aws` **Synced / Healthy**
- App health via ALB DNS; GitHub Actions can assume ECR role via OIDC (no long-lived AWS keys in secrets)
- `make aws-down` when done — confirm no lingering charges

## What you can now claim

> **The architecture is portable** — same GitOps, Kyverno, Falco, and observability patterns on EKS; you understand what changes (ECR, ESO, ALB, IRSA) vs what stays identical (app code, policies, dashboards).

---

## Reference

| | Demo stack (`make aws-up`) | Production add-ons |
|---|---|---|
| Deploy | ArgoCD `clearledger-aws` | Staging → prod promotion |
| Secrets | **ESO** → Secrets Manager | Optional CSI file mounts — [secrets-patterns.md](docs/secrets-patterns.md) |
| CI | `.github/workflows/ci-aws.yaml` + OIDC | Environment approvals |
| Teardown | `make aws-down` | Always destroy when not in use |

Secrets comparison (Vault vs ESO vs CSI): [docs/secrets-patterns.md](docs/secrets-patterns.md) · Cost reference: [LAB-GUIDE § AWS Cost](../../docs/LAB-GUIDE.md#aws-cost-reference)

---

## → Homelab complete

Return to [docs/LAB-GUIDE.md](../../docs/LAB-GUIDE.md) for interview prep and compliance mapping.
