# Stage 2 — GitOps with ArgoCD

**Goal (from the book):** Git becomes the single source of truth for the cluster. ArgoCD
watches `clearledger-infra` and continuously reconciles the cluster to match it — including
reverting unauthorized manual changes (`kubectl`) and providing a clean rollback path via
`git revert`. CI (Stage 1) only ever updates Git; it never touches the cluster directly.

**Status: ✅ Done.** `make check-2` → 7/7 real checks passed (the 1 failure shown is the
same known Multipass-only limitation carried over from `check-1`, not a real problem).

---

## Readiness — confirmed before starting

```bash
make check-1                                                                    # 28/0, known Multipass limitation only
grep secretKeyRef infra/manifests/auth-service/deployment.yaml                  # present
grep vault.hashicorp infra/manifests/auth-service/deployment.yaml && echo STOP || echo OK   # OK
```
Also confirmed manually: `clearledger-infra` has both `auth-service/secret.yaml` and
`ledger-service/secret.yaml` (browsed on GitHub); self-hosted runner still `Idle` with the
`clearledger` label; `ENABLE_ARGOCD_SYNC` correctly still unset at this point.

## Pre-sync checklist — one real fix needed

```bash
grep repoURL stages/stage-2-gitops/argocd/clearledger-app.yaml
```
Found the literal placeholder `YOUR_GITHUB_USERNAME` still in the file — confirmed by
navigating there in a browser and getting a 404. Fixed:
```bash
sed -i 's/YOUR_GITHUB_USERNAME/AliRahimi123456/' stages/stage-2-gitops/argocd/clearledger-app.yaml
```
Confirmed pods healthy and `curl .../auth/health` → `200` before proceeding.

## Installing ArgoCD

```bash
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd --server-side --force-conflicts -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s
```
Went cleanly — every resource `serverside-applied`, server pod ready. (`--server-side
--force-conflicts` matters because one ArgoCD CRD is too large for a normal `kubectl apply`,
which would hit a 256KiB annotation limit.)

Retrieved the auto-generated admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

## Configuring for the NGINX ingress

```bash
kubectl apply -f stages/stage-2-gitops/infra/argocd-cmd-params.yaml
kubectl apply -f stages/stage-2-gitops/infra/argocd-ingress.yaml
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
```
Needed so the browser (HTTPS) ↔ ingress (HTTP internally to ArgoCD) handshake doesn't break
with 503s or redirect loops. Opened `https://argocd.local` — self-signed cert warning
(expected, clicked through Advanced → Proceed), logged in with `admin` + the retrieved
password.

## Connecting the ArgoCD CLI

Book only gives a macOS `brew install argocd` command — installed the Linux binary instead,
same pattern as `trivy`/`syft`/`grype` before it (into `~/.local/bin`, no `sudo`):
```bash
curl -sSL -o ~/.local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x ~/.local/bin/argocd
argocd version --client
```
Logged in via CLI (works fine against `argocd.local` from inside WSL2 — this hits WSL2's own
`/etc/hosts`, unrelated to the Windows-browser-forwarding issue documented in
`00-machine-setup.md`):
```bash
argocd login argocd.local --username admin --password '<password>' --insecure --grpc-web
```

## Connecting ArgoCD to `clearledger-infra` — credential exposure incident

Since `clearledger-infra` is Private, ArgoCD needs a token to read it. This step had **two
separate live-token exposures in chat**, same pattern as earlier sessions — worth recording
plainly rather than glossing over:

1. First exposure: pasted a regenerated `clearledger-ci` PAT directly into chat instead of
   only into the terminal. Revoked/regenerated immediately.
2. Second exposure: pasted the *newly regenerated* token into chat again, and separately typed
   it as a bare line in the terminal (which just triggered `command not found`, since a token
   is a value, not a command). Root cause of the terminal error: the `export
   INFRA_REPO_TOKEN='paste-new-token-here'` instruction used a placeholder that wasn't
   actually replaced with the real value before running — so `$INFRA_REPO_TOKEN` literally
   equaled the text `paste-new-token-here`, hence "Invalid username or token" on the first
   real attempt. Regenerated the token a second time, this time typing the real `export
   INFRA_REPO_TOKEN='github_pat_...'` line directly in the terminal only.

**Lesson reinforced (already known, worth restating):** never type or paste a live credential
into chat, even "just to show the error" — the terminal's own prompts (`export VAR=...`, or a
tool's own `--password` flag) are the only place a secret should ever be typed.

Once done correctly:
```bash
export INFRA_REPO_TOKEN='<token, typed directly in terminal only>'
argocd repo add https://github.com/AliRahimi123456/clearledger-infra.git \
  --username git --password "$INFRA_REPO_TOKEN" --grpc-web
argocd repo list --grpc-web   # confirmed: TYPE git, STATUS Successful
```

## First sync

```bash
kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
argocd app sync clearledger --grpc-web
```
Every resource `Synced`/`Healthy` on the first attempt — no netpol-from-old-copy gotcha (the
book warns about stale `manifests/netpol/` content from older lab copies causing red pods;
this repo never had that, since it was seeded fresh by Stage 1's CI, not copied from an old
version of the lab).

**Official checkpoint, all four passed:**
```bash
kubectl get pods -n clearledger                                                   # all 1/1 Running
kubectl get application clearledger -n argocd \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'   # sync=Synced health=Healthy
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/auth/health     # 200
kubectl logs -n clearledger deploy/auth-service --tail=5 | head -3                # clean 200 OK lines
```

## Enabled the CI → ArgoCD handoff

GitHub → `clearledger` → Settings → Secrets and variables → Actions → **Variables** tab (not
Secrets) → added `ENABLE_ARGOCD_SYNC` = `true`. From now on a green pipeline run also nudges
ArgoCD to sync immediately, instead of waiting for its own ~3 minute poll.

## Proved self-healing (drift correction)

```bash
argocd app resources clearledger --grpc-web | grep Deployment   # confirmed all 5, none orphaned
kubectl set image deployment/auth-service \
  auth-service=rahimi123/clearledger-auth-service:fake-tag -n clearledger
argocd app get clearledger --grpc-web | grep -E "Sync Status|Health Status"
```
**Result: ArgoCD healed the drift so fast I never even caught the transient `OutOfSync`
state** — checked immediately after the `kubectl set image` and it already showed `Synced` /
`Healthy` again. Confirmed via:
```bash
kubectl get deployment auth-service -n clearledger -o jsonpath='{.spec.template.spec.containers[0].image}'
```
→ showed the correct CI-built SHA tag, not `fake-tag`. Faster than the book's description
(which expects a visible minute-or-two `OutOfSync` window) — same underlying mechanism
(`syncPolicy.automated.selfHeal: true`), just a snappier watch loop than the ~3 min polling
description implies.

**Portfolio screenshot saved:** `setup-journal/screenshots/stage2-argocd-synced.png` — the
ArgoCD UI resource tree, `APP HEALTH: Healthy`, `SYNC STATUS: Synced`, `LAST SYNC: Sync OK`,
33 Synced / 0 OutOfSync in the sidebar.

## Practiced a real rollback (Method 1 — `git revert`)

First cloned `clearledger-infra` locally (never had a local clone before this point — only
ever touched it via GitHub's web UI and via CI/ArgoCD):
```bash
cd .. && git clone https://github.com/AliRahimi123456/clearledger-infra.git
cd clearledger-infra
```

**Important discovery:** editing the placeholder image tag directly in a service's
`deployment.yaml` (e.g. `manifests/notification-service/deployment.yaml`) would have had **no
effect** — Kustomize's `images:` transformer in `manifests/kustomization.yaml` rewrites the
placeholder (`clearledger/notification-service:gitops`) to the real registry+tag at render
time regardless of what's literally written in the deployment file. The actual control point
for a specific service's deployed tag is its `newTag:` entry in `kustomization.yaml`.

Simulated a bad deploy by breaking only `notification-service`'s tag, scoped precisely with a
range-address `sed` so the other three services' tags were untouched:
```bash
sed -i '/name: clearledger\/notification-service/,/newTag:/s/newTag:.*/newTag: broken-tag/' manifests/kustomization.yaml
git add manifests/kustomization.yaml
git commit -m "test: simulate bad deploy with nonexistent image tag"
git push
argocd app sync clearledger --grpc-web
kubectl get pods -n clearledger
```
Confirmed the break: new `notification-service` pod stuck in `ImagePullBackOff`. **Notable
side-lesson:** the *old* `notification-service` pod stayed `1/1 Running` throughout — Kubernetes'
default rolling-update strategy won't kill a working old pod until a new one proves healthy,
so this "bad deploy" caused zero actual downtime.

Fixed it the GitOps-correct way:
```bash
git revert HEAD --no-edit
git push
argocd app sync clearledger --grpc-web
kubectl get pods -n clearledger
```
Result: clean recovery, broken pod entirely replaced, `Sync Status: Synced`, `Health Status:
Healthy`. Git history now permanently shows both the mistake and its fix — the actual audit
trail GitOps is meant to provide.

(Method 2 — emergency `argocd app rollback` with auto-sync temporarily disabled — was read and
understood but not hands-on practiced separately, since Method 1 already exercised the same
underlying recovery path end-to-end. Revisit if a real incident ever calls for the faster
break-glass option specifically.)

---

## Final verified state

`make check-2`: 7/7 real checks green. ArgoCD fully manages `clearledger`; no `kubectl apply`
needed for deploys anymore — `git push` to `clearledger-infra` (directly, or via CI from
`clearledger`) is now the only way the cluster changes. Two live-token exposures happened and
were caught/rotated during this stage (documented above) — worth remembering to slow down
specifically at the "paste a token" step every time, regardless of how many times it's been
done correctly before.

## What I can now claim (per the book)

> Implemented GitOps with ArgoCD so cluster state is driven from Git, with drift detection,
> auto-sync, and a Git-based rollback of a bad deploy.

Concretely demonstrated, not just configured: watched a manual `kubectl` change get silently
reverted, and separately pushed a genuinely broken deploy, watched it fail safely (no
downtime), then fixed it with a real `git revert` — the full incident-response loop, hands-on.
