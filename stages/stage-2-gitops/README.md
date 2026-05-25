# Stage 2 — GitOps with ArgoCD

> **The problem you felt in Stage 1:** CI builds the image and updates the
> manifest in Git. But you still run `kubectl apply` manually to deploy.
> The cluster and Git drift apart the moment anyone touches kubectl directly.
>
> **What changes here:** Git becomes the single source of truth. ArgoCD
> continuously reconciles the cluster to match Git. The pipeline never
> touches kubectl again. Ever.

---

## What You Will Learn

- What GitOps actually means mechanically — not the marketing, the mechanism
- How ArgoCD watches a Git repo and syncs the cluster
- What `selfHeal: true` does and why it matters for compliance
- The exact handoff point between CI and CD
- How to prove that Git and the cluster are always equivalent

---

## What You Are Installing

| Tool | Purpose |
|---|---|
| ArgoCD | GitOps controller — syncs cluster to Git |
| ArgoCD CLI | Manage applications from the terminal |

---

## Prerequisites

- Stage 1 complete — CI pipeline running, infra repo on GitHub (clearledger-infra)

---

## Steps

### 1. Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=180s

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### 2. Add ArgoCD Ingress

```bash
kubectl apply -f stages/stage-2-gitops/infra/argocd-ingress.yaml
```

Access ArgoCD at `https://argocd.local` — login: `admin` / (password from above)

### 3. Install ArgoCD CLI

```bash
# macOS:
brew install argocd

# Linux:
curl -sSL -o argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# Windows: winget install ArgoProj.ArgoCD

argocd login argocd.local --username admin --password YOUR_PASSWORD --insecure
```

### 4. Connect the Infra Repo

ArgoCD needs access to `clearledger-infra` on GitHub. If the repo is public, no credentials are needed. If private, use your PAT:

```bash
# Public repo (no credentials needed):
argocd repo add https://github.com/YOUR_USERNAME/clearledger-infra.git

# Private repo (use the same INFRA_REPO_TOKEN PAT from Stage 1):
argocd repo add https://github.com/YOUR_USERNAME/clearledger-infra.git \
  --username YOUR_USERNAME \
  --password YOUR_INFRA_REPO_TOKEN
```

### 5. Create the ArgoCD Application

```bash
kubectl apply -f infra/argocd/clearledger-app.yaml

# Watch ArgoCD sync the cluster
argocd app sync clearledger
argocd app get clearledger
```

The ArgoCD UI at `https://argocd.local` shows the full resource graph:
which pods, services, and deployments are in sync vs out of sync.

---

## Prove the GitOps Contract

This is the most important step in Stage 2. Run it.

```bash
# Manually change something in the cluster — bypass Git entirely
kubectl set image deployment/auth-service \
  auth-service=DOCKER_USERNAME/clearledger-auth-service:fake-tag \
  -n clearledger

# Check what the cluster thinks it's running
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Output: DOCKER_USERNAME/clearledger-auth-service:fake-tag

# Wait 3 minutes. ArgoCD's sync interval is 3 minutes by default.
# Then check again:
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Output: DOCKER_USERNAME/clearledger-auth-service:ORIGINAL_SHA
```

ArgoCD reverted your change. Nobody can drift the cluster from Git.
That revert is the GitOps contract enforced automatically.

---

## The CI/CD Handoff

```yaml
# CI pipeline ends here (from Stage 1):
- name: Commit and push manifest update
  run: |
    git commit -m "ci: update images to $IMAGE_TAG"
    git push

# ArgoCD takes it from here.
# CI and CD are now fully separated.
# CI never touches kubectl.
```

The two responsibilities are:
- **CI:** Build, test, scan, sign → update Git
- **CD (ArgoCD):** Watch Git → reconcile cluster

---

## What the System Looks Like Now

```
git push
  │
  ▼
[GitHub Actions] builds → scans → pushes images → updates Git manifest
                                                         │
                                                         ▼
                                                    [ArgoCD] detects change
                                                         │
                                                         ▼
                                                    Cluster reconciled
                                                    (selfHeal: true)
```

---

## What Is Still Broken

Every commit goes straight to the cluster. No security scanning.
A developer accidentally commits `AWS_SECRET_KEY = "AKIA..."` and that code
gets deployed before anyone notices.

The next stage adds gates that catch security problems before the manifest
ever reaches Git.

---

## Before You Move On

Run the health check to confirm this stage is working:

```bash
bash scripts/health-check.sh 2
```

Green output = ready for the next stage.
Red output = something needs fixing. The message tells you what.

## → Next: [Stage 3 — Security Gates](../stage-3-security-gates/README.md)
