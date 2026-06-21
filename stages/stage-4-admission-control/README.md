# Stage 4 — Admission Control (Kyverno)

**Goal:** Kyverno intercepts every pod creation and rejects policy violations — even when someone bypasses CI with `kubectl`.

## Am I ready?

- [ ] `make check-3` passes — pre-commit and CI security gates active
- [ ] `infra/cosign.pub` exists (from Stage 3)
- [ ] ArgoCD still syncing — app reachable at `http://clearledger.local`

**Done when:** `make check-4` passes and all three break-it scenarios in LAB-GUIDE §4.4 deny bad pods.

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 4](../../docs/LAB-GUIDE.md#stage-4--admission-control-kyverno)** — Kyverno install, Cosign key in policy, five ClusterPolicies, break-it scenarios, kube-bench (§4.7).

## Hands-on checkpoint

- Four Kyverno controllers `Running`; five ClusterPolicies `READY: True`, mode **Enforce**
- Scenario 1: root pod **denied**; Scenario 3: unsigned image **denied** (after pushing `unsigned-test` tag)
- App pods still `Running`; `make check-4` green
- Optional: `bash stages/stage-4-admission-control/scripts/run-kube-bench.sh` — no new FAIL regressions

## What you can now claim

> **Admission control enforces policy at the cluster door** — unsigned images, root containers, and missing limits are blocked at deploy time, not discovered in production.

---

## Reference

| Policy | Severity |
|---|---|
| Disallow root containers | HIGH |
| Require resource limits | MEDIUM |
| Require signed images | CRITICAL |
| Disallow privilege escalation | HIGH |
| Drop all capabilities | HIGH |

Install values: `stages/stage-4-admission-control/infra/kyverno/values.yaml` · Policies: `infra/policies/`

Troubleshooting: [docs/troubleshooting.md § Stage 4](../../docs/troubleshooting.md#stage-4-admission-control-troubleshooting)

---

## → Next: [Stage 5 — Secrets Management](../stage-5-secrets-management/README.md)
