# DAST smoke (ClearLedger)

Dynamic checks against the **running** API. Complements SAST (Semgrep) in CI: static analysis cannot prove auth, routing, or token validation behave correctly at runtime.

## When to run

- After ingress is reachable from your machine (`clearledger.local` in `/etc/hosts`, or Stage 8 ALB DNS).
- On a schedule against a **non-production** preview environment via `workflow_dispatch` in GitHub Actions.

## Run locally

```bash
chmod +x scripts/dast/smoke.sh
BASE_URL=http://clearledger.local ./scripts/dast/smoke.sh
```

## What it checks

| Check | Expectation |
|-------|-------------|
| `/auth/health`, `/ledger/health`, `/notifications/health` | HTTP 200 |
| `/auth/verify` without `Authorization` | Not HTTP 200 |
| `/auth/verify` with malformed / forged JWT | Not HTTP 200 |

Extend this script with Nuclei, OWASP ZAP Baseline, or ledger-specific BOLA cases (two users, cross-tenant IDs) as your lab grows.

## Local Integration Testing (docker-compose)

For testing the frontend locally without a Kubernetes cluster:

```bash
docker compose -f docker-compose.integration.yml up --build -d
```

This starts the full stack (postgres, redis, auth, ledger, notifications,
frontend, nginx) with path routing that mirrors the Kubernetes ingress.
Access at: http://localhost:3000

Then run the DAST smoke tests:

```bash
BASE_URL=http://localhost:3000 bash scripts/dast/smoke.sh
```

Or the frontend integration script:

```bash
BASE_URL=http://localhost:3000 bash scripts/test-frontend-integration.sh
```

Tear down:

```bash
docker compose -f docker-compose.integration.yml down -v
```
