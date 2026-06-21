# Stage 0 — Raw Kubernetes

**Goal:** ClearLedger runs on Kubernetes — you deployed everything by hand, with no CI or GitOps yet.

## Am I ready?

- [ ] Host meets [system requirements](../../docs/LAB-GUIDE.md#before-you-start) (24 GB+ RAM recommended)
- [ ] `multipass`, `kubectl`, `helm`, `docker`, and `jq` installed and verified
- [ ] Docker Desktop running (needed for image builds in §0.3)

**Done when:** `make check-0` passes and `http://clearledger.local` shows the login screen.

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 0](../../docs/LAB-GUIDE.md#stage-0--the-running-system)** — `make setup`, Docker Hub push (§0.3), six deploy layers (§0.5), ingress, health checks.

## Hands-on checkpoint

- `$DOCKER_USERNAME` set; four images on Docker Hub with tag `v0.1.0`
- All app pods `Running` in `clearledger`; Postgres + Redis healthy
- `curl` auth/ledger/notification health endpoints return **200**; UI loads at `http://clearledger.local`
- `make check-0` green

## What you can now claim

> You provisioned MicroK8s, built and pushed container images, and deployed a multi-service app manually — and can explain **why manual deploys do not scale** (no audit trail, no rollback, no consistency).

---

## Reference

| Component | Type |
|---|---|
| `auth-service`, `ledger-service`, `notification-service`, `frontend` | Deployments |
| `postgres` | StatefulSet |
| `redis` | Deployment |
| Stage 0 deployments | `stages/stage-0-raw-kubernetes/infra/manifests/` (use `secretKeyRef`, not Vault) |

---

## → Next: [Stage 1 — CI Pipeline](../stage-1-ci-pipeline/README.md)
