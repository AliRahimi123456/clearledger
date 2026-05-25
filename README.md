> **ClearLedger v1.0** — 10-stage DevSecOps homelab.
> Fintech app. Production security. Free to run. Migratable to AWS.

![Stages](https://img.shields.io/badge/stages-10-blue)
![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)
![Cost](https://img.shields.io/badge/local%20cost-free-brightgreen)

# ClearLedger DevSecOps Lab

## What You Are Building

ClearLedger is a three-service fintech transaction ledger:

| Service | Responsibility |
|---|---|
| `auth-service` | Registration, login, JWT issuance |
| `ledger-service` | Create transactions, balance, history |
| `notification-service` | Event-driven alerts on large transactions |
| `frontend` | Web UI — same APIs, visual proof it works |

The app is the vehicle. DevSecOps is the lesson.

## Architecture

```
                      ┌─────────────────────────────────┐
                      │  Multipass VM (clearledger)      │
                      │                                  │
Host machine          │  ┌─────────┐  ┌──────────────┐ │
curl / browser ──────►│  │  nginx  │  │  MicroK8s    │ │
                      │  │ ingress │─►│  Kubernetes  │ │
                      │  └─────────┘  │              │ │
                      │               │ auth-service  │ │
                      │               │ ledger-svc   │─┼──► Postgres
                      │               │ notif-svc    │ │    Redis
                      │               └──────────────┘ │
                      └─────────────────────────────────┘
```

**Security layers added across 10 stages:**

- CI gates: Gitleaks → Semgrep → Checkov → Trivy → Syft/Grype → Cosign
- Runtime + ops: ArgoCD → Kyverno → Vault → Falco → LitmusChaos → Grafana → OpenTelemetry

## The 10 Stages

| Stage | What Changes | The Problem It Solves |
|---|---|---|
| **0 — Raw Kubernetes** | App running, manual deploys | You need to see the system before automating it |
| **1 — CI Pipeline** | Builds automate on push | Manual docker build/push doesn't scale |
| **2 — GitOps (ArgoCD)** | Pipeline stops touching kubectl | Cluster and Git drift apart |
| **3 — Security Gates** | Scans block every commit | Bad code reaches the cluster undetected |
| **4 — Admission Control** | Kyverno enforces policy | Bad manifests reach running pods |
| **5 — Secrets Management** | Vault replaces K8s Secrets | Credentials live in Git and etcd |
| **6 — Runtime Security** | Falco watches live pods | Threats inside running containers go undetected |
| **6.5 — Chaos Engineering** *(Optional)* | LitmusChaos kills pods, injects latency, fills memory | You detect threats but never proved you survive them |
| **7 — Observability** | Security dashboards + DORA metrics | Security you can't measure, you can't prove |
| **7.5 — OpenTelemetry** *(Optional)* | OTel SDK + distributed traces in Grafana Tempo | You see metrics but not the cross-service request journey |
| **8 — AWS Migration** | Swap endpoints | Cloud-ready without relearning everything |

> Stages 6.5 and 7.5 are optional extensions. Complete the numbered stages first.

**Do them in order. Each stage earns the next.**

## What's Inside

| | |
|---|---|
| 3 FastAPI microservices | Auth, ledger, notifications — real fintech domain |
| 10 staged READMEs | Each stage is a self-contained learning unit |
| Full DevSecOps pipeline | Gitleaks → Semgrep → Checkov → Trivy → Cosign |
| 5 Grafana dashboards | Importable JSON — security posture visible immediately |
| Terraform for AWS | VPC, EKS, ECR, RDS, GuardDuty, CloudTrail — one command |
| Stage health check | `bash scripts/health-check.sh [n]` — green or red, fix the red |
| Local integration stack | `make integration-up` → http://localhost:3000 — see `docs/LAB-GUIDE.md` |
| Interview prep guide | Questions interviewers actually ask, answers that close offers |
| Compliance mapping | Every control mapped to PCI-DSS, SOC2, CIS, NIST, SLSA |

## CI/CD

| Platform | Pipeline file | Registry | Runner |
|---|---|---|---|
| GitHub Actions | `.github/workflows/ci.yaml` | Docker Hub | Self-hosted runner inside the Multipass VM |

The pipeline runs on GitHub Actions with a self-hosted runner installed inside your VM. This lets the runner reach your local cluster and Docker Hub. Employers can see your pipeline runs publicly on GitHub.

## Setting Up Your Repository

```bash
# Clone or download this repo
git clone https://github.com/YOUR-USERNAME/clearledger.git
cd clearledger

# See all available commands
make

# Start the lab
make setup
make stage-0
```

Windows users: `make` works in Git Bash. Browser open commands use the URL printed — open it manually in your browser.

```bash
# Create the infra repo (separate — ArgoCD watches this one)
# On GitHub: create a new repo called clearledger-infra (Stage 1 covers this)
```

This repo contains the application code and lab stages.
The infra repo contains only Kubernetes manifests.
Keep them separate — this separation is the GitOps pattern you're learning.

## Prerequisites

See [QUICKSTART.md](./QUICKSTART.md) — up and running in under 10 commands.

Finished the lab? See [SHOWCASE.md](./SHOWCASE.md) — how to screenshot, post on LinkedIn, and talk about it in interviews.

## See It Working in 5 Minutes

After `QUICKSTART.md`:

```bash
# First, register a user
curl -s -X POST http://clearledger.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' | jq .

# Then login
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' \
  | jq -r .access_token)

curl -s http://clearledger.local/ledger/balance \
  -H "Authorization: Bearer $TOKEN" | jq .
# {"user_id":"...","balance":0.0}
```

If you see that JSON, ClearLedger is running. Everything after this is securing it.

Or open the web UI: `make open-ui` (or visit http://clearledger.local).

## Demo

> Screenshots from a completed lab run. Yours will look the same.

**Web UI — Balance and transactions at a glance:**
![ClearLedger Dashboard](./screenshots/01-ui-dashboard.png)

**ArgoCD — Git is the single source of truth:**
![ArgoCD Synced and Healthy](./screenshots/02-argocd-synced.png)

**Kyverno — Policy blocks a root container at admission:**
![Kyverno blocks root container](./screenshots/03-kyverno-block.png)

**Falco — Runtime security catches a shell inside a running pod:**
![Falco CRITICAL alert](./screenshots/04-falco-alert.png)

**Grafana — Every security event is visible and measurable:**
![Grafana Security Dashboard](./screenshots/05-grafana-security.png)

**CI Pipeline — Six security gates, all green:**
![Pipeline all green](./screenshots/06-pipeline-green.png)

> Screenshots are placeholders until you run the lab and take your own.
> See [SCREENSHOT-GUIDE.md](./SCREENSHOT-GUIDE.md) for exact instructions.

## Repository Layout

- `app/` — auth/ledger/notification services + frontend SPA
- `infra/` — cumulative manifests/policies (current state)
- `stages/` — 8 learning units (only what changes per stage)
- `scripts/` — setup + health-check helpers
- `docs/` — compliance + troubleshooting + interview prep

**Rule:** stage folders show what’s new; root `infra/` reflects your current end state.

## Who This Is For

**Junior DevOps (0–2 yrs):** Do every stage in order. Don't skip.
The pain of each stage is why the next one exists.

**Mid-level DevOps (2–4 yrs):** Stages 3–7 are where the value is.
Skim 0–2, focus on the security pipeline and runtime layers.

**Interview prep:** Complete through Stage 4.
Read `docs/interview-prep.md`. The questions and answers are based on
exactly what is in this lab — not generic DevOps questions.

**Portfolio:** Push to GitHub, use `.github/workflows/ci.yaml`.
A working DevSecOps pipeline running against a real fintech app
is visible evidence of capability.

## After You Finish

Start here:
- [docs/compliance-mapping.md](./docs/compliance-mapping.md)
- [docs/interview-prep.md](./docs/interview-prep.md)

## Lab Guide

See [docs/LAB-GUIDE.md](./docs/LAB-GUIDE.md) for the full walkthrough —
what each stage teaches, what to verify, and the exact moment each
concept clicks.

## License

MIT — see [LICENSE](./LICENSE).
