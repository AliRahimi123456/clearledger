# Stage 3 — Security Gates in the Pipeline

> **The problem you felt in Stage 2:** Any code push reaches ArgoCD and
> gets deployed. A leaked secret, a command injection vulnerability, an
> old base image with 47 CVEs — all of it gets deployed automatically
> with no safety net.
>
> **What changes here:** Every commit passes through six security checks
> before the manifest is updated. A failure at any gate stops the pipeline.
> The cluster only ever receives code that passed every check.

---

## What You Will Learn

- Secrets scanning with Gitleaks (catches hardcoded credentials)
- SAST with Semgrep (catches code-level vulnerabilities)
- IaC scanning with Checkov (catches Kubernetes and Dockerfile misconfigs)
- Container image CVE scanning with Trivy
- SBOM generation with Syft + vulnerability scanning with Grype
- Image signing with Cosign (supply chain integrity)
- How to test each gate by deliberately triggering it
- Why DAST (runtime API tests) complements SAST — and how to run the lab smoke script

---

## What You Are Adding to the Pipeline

| Gate | Tool | Catches |
|---|---|---|
| Secrets scan | Gitleaks | Hardcoded API keys, passwords, tokens |
| SAST | Semgrep | SQL injection, command injection, OWASP Top 10 |
| IaC scan | Checkov | Missing securityContext, privileged containers |
| Image CVE scan | Trivy | Known CVEs in base image and dependencies |
| SBOM + scan | Syft + Grype | Dependency inventory + vulnerability scan |
| Image signing | Cosign | Proves the image came from your pipeline |
| DAST (manual) | `scripts/dast/smoke.sh` | Quick curl smoke against the **live** ingress (on-demand workflow) |
| DAST (main push) | OWASP ZAP + `dast/fintech-test-payloads.py` | Full API scan + BOLA / JWT / business-logic checks after deploy (see §3.5) |

---

## Prerequisites

- Stage 2 complete — ArgoCD running, GitOps contract established

---

## Steps

### 1. Generate Cosign Keys

```bash
# Install Cosign on your host
# macOS:
brew install cosign

# Linux:
curl -O -L https://github.com/sigstore/cosign/releases/download/v2.2.4/cosign-linux-amd64
chmod +x cosign-linux-amd64 && sudo mv cosign-linux-amd64 /usr/local/bin/cosign

# Generate the keypair
cosign generate-key-pair
# Creates: cosign.key (private) and cosign.pub (public)

# View the public key (you'll need it for Kyverno in Stage 4)
cat cosign.pub
```

### 2. Add Secrets to GitHub

Go to github.com/YOUR_USERNAME/clearledger → Settings → Secrets and variables → Actions and add:
- `COSIGN_PRIVATE_KEY` — contents of `cosign.key`
- `COSIGN_PASSWORD` — the password you set during key generation

Store `cosign.pub` in your infra repo for Kyverno to use in Stage 4.

### 3. Verify the Pipeline Has Security Gates

The security gates are already in `.github/workflows/ci.yaml`. Push any change to trigger the full pipeline:

```bash
git add .
git commit -m "ci: full DevSecOps pipeline"
git push origin main
```

### 4. Install pre-commit hooks (local security gate)

The CI pipeline is the safety net. Pre-commit hooks are the first line of
defense — they catch issues before they reach the remote.

The config lives at the repo root (`.pre-commit-config.yaml`) and matches the
Stage 3 template in `stages/stage-3-security-gates/pre-commit-config.yaml`.
Keep them in sync when you change hooks.

Install:

```bash
# macOS / Linux
pip install pre-commit
pre-commit install

# Windows (Git Bash or WSL2)
pip install pre-commit
pre-commit install
```

Test it works:

```bash
pre-commit run --all-files
```

Now try to commit a hardcoded secret:

```bash
echo 'AWS_SECRET = "AKIAIOSFODNN7EXAMPLE"' >> app/auth-service/main.py
git add app/auth-service/main.py
git commit -m "test: this should be blocked"
# Gitleaks fires before the commit is created. The secret never enters git history.
```

Revert the test line before continuing.

---

## 3.3 — Renovate Bot: Continuous Dependency Monitoring

Pre-commit hooks catch secrets before commit.
Trivy catches CVEs at build time.
Neither catches a new CVE in a dependency you pinned 3 months ago.

Renovate Bot closes that gap. It runs weekly and raises a PR when any
dependency has an available update. When a CVE is filed against a
pinned package, it raises a PR immediately — before your next push,
before your next pipeline run.

Setup (one-time):
1. Generate a GitHub PAT with repo scope at github.com/settings/tokens
2. Add it as `RENOVATE_TOKEN` in GitHub Secrets (github.com/YOUR_USERNAME/clearledger/settings/secrets/actions)
3. Push `renovate.json` — Renovate runs on next Monday at 6am

To run immediately:
Go to github.com/YOUR_USERNAME/clearledger/actions
Select "Renovate" → Run workflow

What you will see:
Renovate raises PRs with titles like:
- `chore(deps): update fastapi to 0.112.0`
- `fix(security): update cryptography 42.0.5 (CVE-2024-xxxx)`

Security updates are labelled URGENT and scheduled "at any time."
Dependency drift updates are batched to Monday mornings.

Each PR triggers the full security pipeline — the PR is blocked until
Trivy, Semgrep, and Gitleaks pass. You review the PR, the pipeline
validates it, you merge. No manual dependency audit needed.

`automerge` is disabled in `renovate.json` — human review is required
even for patch updates, because dependency changes can break builds.

---

### 5. DAST — smoke test the live API (runtime gate)

SAST (Semgrep) analyzes source code. It cannot prove that `/auth/verify` rejects
bad tokens at runtime, or that routing through ingress is correct. A minimal
**DAST** smoke script hits your running cluster:

```bash
chmod +x scripts/dast/smoke.sh
BASE_URL=http://clearledger.local ./scripts/dast/smoke.sh
```

Details: [scripts/dast/README.md](../../scripts/dast/README.md).

To run from GitHub Actions on demand: go to github.com/YOUR_USERNAME/clearledger/actions → select the DAST job → **Run workflow** and set `base_url` to your ingress (for Stage 8, the ALB DNS name).

---

## 3.5 — DAST: Testing the Running Application

**SAST** (Semgrep) reads your code and finds problems *statically* — unsafe patterns, injection sinks, missing validation in source.

**DAST** runs your *deployed* application and attacks it like an adversary: real HTTP requests, real auth headers, real responses. It finds classes of bugs SAST cannot see: misconfigured auth at runtime, routing mistakes, and **BOLA** (Broken Object Level Authorization).

### BOLA and fintech APIs

Every endpoint that returns or mutates user-owned data must answer: *not only* “Is the caller authenticated?” but **“Does this user own *this* resource?”** Omitting the second check is the most common serious flaw in fintech-style APIs: user B reads user A’s transaction by ID, or changes another customer’s balance. ZAP’s API scan plus the custom script `dast/fintech-test-payloads.py` target that behavior explicitly.

### Why DAST runs after deployment (in CI)

DAST needs a **live** application. It cannot run against source code or a container image alone. In `.github/workflows/ci.yaml`, the **dast** job runs **after** `update-manifests` so ArgoCD can sync the new images; the gate validates what is actually running, not only what passed build-time checks.

**Requirements:** the self-hosted runner inside the VM resolves `http://clearledger.local` and can reach the live ingress. Add repository secret **`JWT_SECRET`** (same value as auth-service) so JWT tampering tests can sign forged tokens and assert **401**.

### Run the fintech DAST script locally

```bash
pip install requests
export BASE_URL=http://clearledger.local
export JWT_SECRET='your-auth-service-jwt-secret'
python3 stages/stage-3-security-gates/dast/fintech-test-payloads.py
```

Expected output when everything passes (labels may include function names in the summary table):

```
[PASS] BOLA transaction access control (test_bola_transaction_access)
[PASS] Negative amount rejected (test_negative_amount_transaction)
[PASS] JWT none algorithm rejected (test_jwt_none_algorithm)
[PASS] JWT expiry enforced (test_jwt_expired_token)
[PASS] Large transaction alert threshold correct (test_large_transaction_bypass)
[PASS] Mass assignment blocked (test_mass_assignment)
```

### Run OWASP ZAP (automation framework) locally

From the repo root, register `zap-dast@clearledger.local` once (or rely on 409 on repeat), then replace the placeholder and run ZAP in Docker (mount the `dast/` directory to `/zap/wrk`):

```bash
TOKEN=$(curl -fsS -X POST http://clearledger.local/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"zap-dast@clearledger.local","password":"ZapDastPass123!"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
sed -i.bak "s|ZAP_ACCESS_TOKEN_PLACEHOLDER|${TOKEN}|g" \
  stages/stage-3-security-gates/dast/zap-config.yaml
docker run --rm -v "$(pwd)/stages/stage-3-security-gates/dast:/zap/wrk:rw" \
  zaproxy/zap-stable zap.sh -cmd -autorun /zap/wrk/zap-config.yaml
# Report: stages/stage-3-security-gates/dast/zap-report.json
```

### Prove DAST catches a BOLA regression

1. Temporarily remove or bypass the `user_id` ownership check on `GET /transactions/{transaction_id}` in `app/ledger-service/main.py`.
2. Run `python3 stages/stage-3-security-gates/dast/fintech-test-payloads.py` with `BASE_URL` pointing at your cluster.
3. Watch **`test_bola_transaction_access`** fail and print the exact **request** and **response** that exposed the issue.
4. Revert the change, redeploy, run again — tests pass. That is DAST doing its job.

---

## Break Each Gate On Purpose

This is the most important part of Stage 3. Run each test. Watch it fail.
Then revert and watch it pass. This is the muscle memory that matters.

### Test 1 — Gitleaks (Secrets Scan)

```python
# Temporarily add to app/auth-service/main.py:
AWS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"
```

Push it. Gitleaks fails. The pipeline stops before building any image.
Revert. Push again. Pipeline goes green.

### Test 2 — Trivy (CVE Scan)

```dockerfile
# Temporarily change any Dockerfile's first line to:
FROM python:3.8-slim
```

Push it. Trivy finds CRITICAL CVEs in the old base image. Build fails.
Revert to `python:3.12-slim`. Push. Pipeline goes green.

### Test 3 — Semgrep (SAST)

```python
# Temporarily add to app/ledger-service/main.py:
import subprocess
result = subprocess.run(request.query_params.get("cmd"), shell=True)
```

Push it. Semgrep flags command injection. Pipeline fails at SAST stage.
Revert. Push again. Pipeline goes green.

### Test 4 — Checkov (IaC)

```yaml
# Temporarily remove the securityContext block from any deployment.yaml
# (comment out the entire securityContext section)
```

Push the infra repo change. Checkov reports a HIGH finding (missing securityContext).
Pipeline fails. Restore securityContext. Push. Pipeline goes green.

---

## What Each Failure Looks Like

Save these error outputs — they prove the gates work:

```
# Gitleaks output:
Finding: AWS Access Key
Rule: aws-access-key-id
File: app/auth-service/main.py
Line: X

# Trivy output:
CRITICAL: CVE-2023-XXXXX — python3.8 base image
Fixed version: python:3.12-slim

# Semgrep output:
app/ledger-service/main.py:X — subprocess-shell-true
  Command injection via shell=True with user-controlled input
  OWASP A03:2021 — Injection

# Checkov output:
Check: CKV_K8S_30 — "Ensure that the securityContext is applied to pods"
FAILED for resource: kubernetes_deployment.auth-service
```

---

## 3.6 — SLSA Provenance: Beyond Image Signing

Image signing and provenance attestation answer different questions:

- **Signing:** "this image was signed by the holder of key K"
- **Attestation:** "this image was built from commit X, by pipeline Y,
  at time Z, and all these security gates passed first"

An attacker who compromises the signing key can sign any image. They cannot
easily forge a provenance attestation that points to a legitimate commit in
this repository with the expected `builder.id`.

Verify an attestation manually:

```bash
cosign verify-attestation \
  --key infra/cosign.pub \
  --type slsaprovenance \
  YOUR_USERNAME/clearledger-auth-service:COMMIT_SHA \
  | jq '.payload | @base64d | fromjson | .predicate'
```

Expected output shows the `builder.id`, `buildType`, and source commit.

The Kyverno policy `verify-slsa-provenance` starts in **Audit** mode — it
logs violations without blocking pods. After confirming attestations are
generated correctly on every pipeline run:

```bash
kubectl edit clusterpolicy verify-slsa-provenance
# Change validationFailureAction: Audit → Enforce
```

SLSA Level 3 would require a hermetic build environment (reproducible, isolated
builds). That is not practical with a self-hosted runner homelab. Level 2 —
signed provenance from a known CI pipeline — is the practical target for most
organizations.

---

## What the System Looks Like Now

```
git push
  │
  ▼
[Gitleaks] ── secrets scan ─── FAIL → pipeline stops
  │ PASS
  ▼
[Semgrep] ─── SAST ─────────── FAIL → pipeline stops
  │ PASS
[Checkov] ─── IaC scan ──────── FAIL → pipeline stops
  │ PASS
  ▼
[Docker build]
  │
[Trivy] ────── CVE scan ──────── FAIL → pipeline stops
  │ PASS
[Syft+Grype] ─ SBOM scan ──────── FAIL → pipeline stops
  │ PASS
[Cosign] ───── image signing
  │
  ▼
[Update infra Git] ──► [ArgoCD syncs cluster]
```

---

## What Is Still Broken

The pipeline gates everything that enters the cluster through CI.
But what about:
- A manifest applied directly with `kubectl apply` (bypassing CI)?
- An image from a different registry that was never scanned?
- A pod spec with `runAsRoot: true`?

CI is the gate for code. The cluster needs its own gate for resources.
That is Kyverno. Stage 4.

---

---

## Before You Move On

Run the health check to confirm this stage is working:

```bash
bash scripts/health-check.sh 3
```

Green output = ready for the next stage.
Red output = something needs fixing. The message tells you what.

## → Next: [Stage 4 — Admission Control](../stage-4-admission-control/README.md)
