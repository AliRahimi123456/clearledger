# ClearLedger — Portfolio Showcase Guide

You built a real DevSecOps lab. This guide helps you **show it**, not just complete it.

Use it when updating LinkedIn, polishing your GitHub profile, or preparing for interviews.
Every recommendation below points to something you can screenshot or demo from this repo.

---

## What You Built (in one sentence for LinkedIn)

Pick the level that matches where you are today:

**Junior:**
> Built a production-grade DevSecOps homelab securing a fintech microservices app across 8 stages — from raw Kubernetes to full security automation.

**Mid:**
> Implemented a complete DevSecOps pipeline for a fintech ledger system: GitOps with ArgoCD, policy enforcement with Kyverno, runtime security with Falco, and AWS migration with Terraform.

**Experienced:**
> Designed and built a ClearLedger DevSecOps reference architecture covering the full SDLC security lifecycle, compliant with PCI-DSS, SOC2, and CIS Kubernetes benchmarks.

---

## Screenshots Worth Taking

See [SCREENSHOT-GUIDE.md](./SCREENSHOT-GUIDE.md) for exact setup commands and what each
screen should look like. The guide tells you what to run, what
the output should show, and why each screenshot is impressive.

---

## LinkedIn Post Template

Copy, replace `[your GitHub URL]`, and post when you finish through Stage 4 (minimum) or Stage 7 (strongest story):

---

I just completed ClearLedger — a DevSecOps homelab I built from scratch around a three-service fintech API.

What it includes:
→ Automated CI with security gates (Gitleaks, Semgrep, Trivy, Cosign)
→ GitOps with ArgoCD — Git is the source of truth for the cluster
→ Kyverno admission control blocking unsafe workloads
→ Falco runtime detection with alerts I triggered myself
→ Grafana dashboards mapping controls to compliance frameworks

The app is simple on purpose. The lesson is the security architecture: how code gets scanned, how policy gets enforced, and how you prove it with evidence.

I can walk through any stage live — from a Kyverno rejection to a Falco alert on a running pod.

Repo: [your GitHub URL]

Open to DevOps / DevSecOps / platform engineering conversations.

---

## How to Talk About It in Interviews

Short answers grounded in **your** repo. Expand using `docs/interview-prep.md` when they dig deeper.

### Q: "Tell me about a project you're proud of."

I built ClearLedger — a fintech ledger on Kubernetes with a full DevSecOps pipeline I designed in stages. By Stage 4 I watched Kyverno block a root container at admission; by Stage 6 I triggered my own Falco alert from a deliberate `kubectl exec`. Everything is in the repo with health checks and stage READMEs so I can demo any layer.

### Q: "How do you approach security in a Kubernetes environment?"

Defense in depth, in order: CI gates in `.github/workflows/ci.yaml` stop bad artifacts before deploy; Kyverno policies in `infra/policies/` enforce at admission; Vault injects secrets at runtime in Stage 5; Falco watches syscalls in Stage 6; Grafana dashboards in Stage 7 make it measurable. I verify with `bash scripts/health-check.sh` and policy reports, not assumptions.

### Q: "What is GitOps and how have you used it?"

GitOps means the cluster matches Git — CI updates image tags in the infra repo, ArgoCD syncs `clearledger`, and `selfHeal` reverts manual drift. In ClearLedger the pipeline never runs `kubectl apply` to production; it commits to Git and ArgoCD reconciles. I can show the ArgoCD app as Synced/Healthy after a push.

### Q: "How do you handle secrets in a containerized application?"

Early stages use Kubernetes Secrets deliberately to feel the problem; Stage 5 moves credentials to Vault with agent sidecar injection into `/vault/secrets/`. The app reads the same file paths — no code change, only manifest change. Nothing sensitive belongs in Git; I verify with `kubectl get secrets -n clearledger` after Vault migration.

### Q: "Walk me through your CI/CD pipeline."

Push to main triggers Gitleaks first — any secret stops everything. Then Semgrep and Checkov run in parallel, then each service image is built, scanned with Trivy, signed with Cosign, and pushed to Docker Hub or GHCR. The pipeline updates the infra repo manifest; ArgoCD deploys. On main, DAST runs against the live ingress. I can open the Actions run and point to each gate's artifact.

---

## GitHub README Badges

Add only badges that signal something true. Paste at the top of `README.md` (adjust GitHub username):

```markdown
![CI](https://github.com/YOUR-USERNAME/clearledger/actions/workflows/ci.yaml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-green)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.29+-326CE5?logo=kubernetes&logoColor=white)
![Stages](https://img.shields.io/badge/stages-10-blue)
```

**What each badge means:**
- **CI** — pipeline runs on your fork (replace `YOUR-USERNAME`; enable GitHub Actions on the repo)
- **License** — MIT, safe for employers to browse
- **Kubernetes** — matches MicroK8s 1.29 used in QUICKSTART
- **Stages** — self-contained learning units, not a single demo script

Do **not** add vanity badges (lines of code, "built with love", duplicate license shields). They add noise without signal.

---

## Quick checklist before you share publicly

- [ ] Fork pushed to GitHub with `.github/workflows/ci.yaml` enabled
- [ ] At least 4 screenshots from the list above saved locally
- [ ] README links to `SHOWCASE.md` and `docs/interview-prep.md`
- [ ] No secrets in git (`gitleaks detect` clean)
- [ ] You can run `bash scripts/health-check.sh 4` (or `7`) green in one terminal session

You built the system. These steps help you **own the story**.
