# Contributing to ClearLedger

## Branch workflow

All changes go through a pull request. Direct pushes to main are blocked.

1. Create a branch: git checkout -b fix/description-of-change
2. Make your change
3. Push: git push origin fix/description-of-change
4. Open a pull request
5. Wait for pipeline to pass
6. Get at least one review

## Pipeline gates

Every PR must pass all security gates before merge:
- Gitleaks: no hardcoded secrets
- Semgrep: no SAST findings
- Checkov: no HIGH/CRITICAL IaC issues
- Trivy: no unfixed CRITICAL/HIGH CVEs
- Image signing: all images signed with Cosign

If a gate fails, fix the issue in your branch and push again.

## Reporting Issues

Open a GitHub issue with:
- Your OS and Multipass version
- The stage you were on
- The exact command that failed
- The full error output

## Suggesting Features

Open an issue describing the DevSecOps practice or tool you'd like to see
added. Reference the relevant compliance framework if applicable.

## Running Locally

See docs/LAB-GUIDE.md — complete setup from scratch.
The health check script validates each stage:

```bash
bash scripts/health-check.sh [0-7]
make check-65   # Stage 6.5 (chaos)
make check-75   # Stage 7.5 (OpenTelemetry)
```

> If you see `.cursor/` appearing as tracked after cloning,
> run: `git rm -r --cached .cursor/ && git commit -m "chore: untrack cursor folder"`

## Definition of Done for PRs

- bash scripts/health-check.sh all passes
- No new words in .gitignore that aren't used
- Stage READMEs updated if the stage behaviour changed
- Compliance mapping updated if a new control was added
