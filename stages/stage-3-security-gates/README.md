# Stage 3 — Security Gates in the Pipeline

**Goal:** Every commit passes six security checks before the manifest is updated — a failure stops the pipeline.

## Am I ready?

- [ ] `make check-2` passes — ArgoCD deploys from `clearledger-infra`
- [ ] You understand what CI already scans (LAB-GUIDE [Stage 1 security posture](../../docs/LAB-GUIDE.md#stage-1-security-posture--strict-vs-evidence-only))

**Done when:** `make check-3` passes and you triggered each gate at least once (LAB-GUIDE §3.4).

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 3](../../docs/LAB-GUIDE.md#stage-3--security-gates)** — pre-commit hooks, Cosign keys, break each gate on purpose (§3.4), real CVE scan failures (§3.5), [Enable DAST](../../docs/LAB-GUIDE.md#enable-dast-optional--after-stage-2) (optional), troubleshooting.

## Hands-on checkpoint

- Pre-commit installed; fake AWS key **blocks** a local commit
- `infra/cosign.pub` exists; pipeline lists gitleaks, semgrep, checkov, trivy, cosign
- Broke at least one gate in CI (§3.4), read the log, reverted, workflow green
- `make check-3` ends with **All checks passed. Ready for the next stage.**

## What you can now claim

> **Security is a pipeline, not a final review** — stacked gates (Gitleaks, Semgrep, Checkov, Trivy, Cosign) fail fast before bad code or images reach GitOps; pre-commit + CI is defense in depth.

---

## Reference

| Gate | Tool |
|---|---|
| Secrets | Gitleaks |
| SAST | Semgrep |
| IaC | Checkov |
| Image CVEs | Trivy |
| SBOM | Syft + Grype |
| Signing | Cosign |
| DAST (optional) | `scripts/dast/smoke.sh`, ZAP — [Enable DAST](../../docs/LAB-GUIDE.md#enable-dast-optional--after-stage-2) |

Unexpected Trivy/Grype failure (not from §3.4): [§3.5](../../docs/LAB-GUIDE.md#35--when-a-scan-fails-on-a-cve-you-didnt-inject).

Pre-commit expected failures on later-stage files: see LAB-GUIDE [§3.1](../../docs/LAB-GUIDE.md#31--install-pre-commit-hooks).

---

## → Next: [Stage 4 — Admission Control](../stage-4-admission-control/README.md)
