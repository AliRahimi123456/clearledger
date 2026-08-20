# Stage 5 — Secrets Management (Vault)

**Goal (from the book):** database passwords and JWT secrets currently sit in Kubernetes
`Secret` objects (base64-encoded, not encrypted, readable by anyone with `kubectl` access) and
in `secret.yaml` files committed to `clearledger-infra`. Move them into HashiCorp Vault, have
Vault inject them into pods at startup via a sidecar container, delete the old Kubernetes
Secrets, and prove login/API calls still work — the moment "secrets management clicks."

**Status: ✅ Done.** `make check-5` → 15 passed, 0 warnings, 0 failures. `auth-service`/
`ledger-service` pods run `2/2` (app + Vault agent sidecar); old `auth-service-secret`/
`ledger-service-secret` genuinely gone from the cluster; login confirmed working end-to-end
using credentials read from `/vault/secrets/`.

---

## Readiness check

`make check-4` confirmed passing before starting — Stage 4 solid, no crash-looping pods.

## §5.1 — Created local `.env`

```bash
cp stages/stage-5-secrets-management/.env.example stages/stage-5-secrets-management/.env
```
Read the 3 real values out of the existing Kubernetes Secrets (`kubectl get secret ... -o
jsonpath=... | base64 -d`) and filled them into `.env` alongside a self-chosen `VAULT_TOKEN`
(`my-dev-root-token`) — edited by hand in VS Code (had to use `Ctrl+P` quick-open to find the
dotfile, since it wasn't visible by default in the Explorer sidebar). Verified all 4 lines
filled before continuing. `.env` stays gitignored, never committed, matching the credential
hygiene practice used throughout this whole lab.

## §5.2 — Installed Vault + agent injector

```bash
set -a && source stages/stage-5-secrets-management/.env && set +a
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
helm install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken="${VAULT_TOKEN}" \
  --set ui.enabled=true \
  --set injector.enabled=true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=120s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault-agent-injector -n vault --timeout=120s
kubectl apply -f stages/stage-5-secrets-management/infra/vault-ingress.yaml
```
Clean install, both `vault-0` and `vault-agent-injector-...` confirmed `1/1 Running`. Vault
dev mode — no unsealing ceremony, not production-grade, correctly scoped for this lab per the
book's own caveat.

## §5.3 — Configured Vault + seeded secrets

```bash
bash stages/stage-5-secrets-management/infra/vault/setup.sh
bash stages/stage-5-secrets-management/infra/vault/seed-vault-secrets.sh
```
`setup.sh`: enabled Kubernetes auth, KV-v2 secrets engine, policies, and auth roles (two
harmless warnings about optional JWT "audience" configuration — not required). `seed-vault-
secrets.sh`: wrote the 3 seed values into `clearledger/data/auth-service` and `clearledger/
data/ledger-service`, confirmed via metadata only (`version: 1`) — no secret values ever
printed to the terminal, matching the book's promise.

## §5.4 — GitOps update, and a real bug found and fixed

**§5.4a** — copied Vault-aware `deployment.yaml` for `auth-service`/`ledger-service` from the
stage's template folder into `infra/manifests/`, added `infra/manifests/vault/rotation-
cronjob.yaml`, deleted both `secret.yaml` files.

**§5.4b** — edited `infra/manifests/kustomization.yaml` with `sed` (removed the two secret
resource lines, added the rotation cronjob line). All 4 of the book's own verification checks
passed, including a real `kustomize build` render check, not just a text match.

**§5.4c** — cloned `clearledger-infra` to `/tmp/clearledger-infra` (fresh PAT needed —
`clearledger-infra-stage5`, Contents: Read/write), copied the same 6 changes over, committed,
pushed. Independently re-verified against a **second, completely fresh clone**
(`/tmp/verify-s5`) rather than trusting the push — all 3 checks passed.

**Real bug found during the ArgoCD sync that followed:** copying `infra/manifests/
kustomization.yaml` from the app repo into `clearledger-infra` also copied its `images:`
section — which in the **app repo's copy** still has the original template placeholder
(`YOUR_DOCKERHUB_USERNAME`) and a fake `v0.1.0` tag, because that section was never the one CI
actually kept current; only `clearledger-infra`'s own copy was, via CI's `update-manifests`
job. This silently overwrote the real, CI-maintained values with stale placeholders.

Kyverno caught it immediately and correctly: `argocd app sync` failed on all 4 app deployments
with `admission webhook "mutate.kyverno.svc-fail" denied the request: ... repository name must
be lowercase` (Kyverno couldn't even parse `YOUR_DOCKERHUB_USERNAME` as a valid image
reference). Root-caused precisely rather than guessed at — found the real currently-running,
correct image references via `kubectl get deployment ... -o jsonpath=...` for all 4 services
(all sharing tag `a2eedd94086214b2db9b9408be2a9a86bbd3e83b`, the last real CI-triggered build),
manually restored `clearledger-infra`'s `kustomization.yaml` `images:` block to the real
username (`rahimi123`) and that real tag, committed, pushed, re-synced — succeeded cleanly.
Also added a permanent warning comment to the **app repo's** copy of the file so this can't
happen again by accident:
> "this file's `images:` section is a template only — CI's update-manifests job keeps the
> real, current newTag in clearledger-infra's copy. Never overwrite that copy with this one."

## §5.5 / §5.5b — Pods rolled out, secrets auto-pruned, ArgoCD synced

The corrected sync succeeded end-to-end in one pass: `Phase: Succeeded`, `Sync Status: Synced`,
`Health Status: Healthy`. Notably, **ArgoCD automatically pruned the old `auth-service-secret`
and `ledger-service-secret` objects itself** — no manual `kubectl delete secret` needed, since
`syncPolicy.automated.prune: true` (set back in Stage 2) means anything no longer defined in
Git gets removed automatically once everything else syncs cleanly. Confirmed: both
`auth-service` and `ledger-service` pods `2/2 Running` (app + `vault-agent` sidecar), and
`kubectl get secret -n clearledger` shows only `postgres-secret` remaining.

## §5.6 — Proved the full chain works

```bash
kubectl exec -n clearledger $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- ls /vault/secrets/
# → database_url, jwt_secret
```
Confirmed the sidecar's fetched files are genuinely present inside the running container.

Login test — the book's example account (`test@clearledger.io`) doesn't exist in this
deployment; used the actual seeded test account instead (`student@example.com` /
`LearningDevSecOps1`, established back in Stage 0):
```bash
curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"LearningDevSecOps1"}' | jq .
# → real access_token returned
```
Full chain proven: Vault → sidecar → `/vault/secrets/` file → app reads it → database
connection succeeds → login succeeds — with zero Kubernetes Secrets involved for these two
services anymore.

## §5.7 — Final health check

```
make check-5
✓ Passed: 15
All checks passed. Ready for the next stage.
```
0 warnings, 0 failures — the cleanest stage-close result yet.

## What I can now claim (per the book)

> Replaced Kubernetes Secrets with HashiCorp Vault agent injection, removed app credentials
> from Git and Kubernetes Secrets, and verified the app still worked after Vault injected the
> credentials at runtime.

Concretely demonstrated: watched the old Secrets get auto-pruned by ArgoCD the moment Git
stopped referencing them, confirmed the injected files inside a live pod, and got a real login
token back — plus, as with every stage so far, caught and properly root-caused a genuine
mistake (the `kustomization.yaml` template overwrite) instead of guessing at a fix, using the
same evidence-first debugging discipline as Stages 3 and 4's incidents.

## Full command reference — every terminal command run today, in order

```bash
# Readiness
make check-4

# §5.1
cp stages/stage-5-secrets-management/.env.example stages/stage-5-secrets-management/.env
kubectl get secret auth-service-secret -n clearledger -o jsonpath='{.data.database_url}' | base64 -d; echo
kubectl get secret auth-service-secret -n clearledger -o jsonpath='{.data.jwt_secret}' | base64 -d; echo
kubectl get secret ledger-service-secret -n clearledger -o jsonpath='{.data.database_url}' | base64 -d; echo
# (.env filled in by hand in editor: VAULT_TOKEN, SEED_AUTH_DATABASE_URL, SEED_AUTH_JWT_SECRET, SEED_LEDGER_DATABASE_URL)

# §5.2
set -a && source stages/stage-5-secrets-management/.env && set +a
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
helm install vault hashicorp/vault --namespace vault --create-namespace \
  --set server.dev.enabled=true --set server.dev.devRootToken="${VAULT_TOKEN}" \
  --set ui.enabled=true --set injector.enabled=true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=120s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault-agent-injector -n vault --timeout=120s
kubectl apply -f stages/stage-5-secrets-management/infra/vault-ingress.yaml
kubectl get pods -n vault

# §5.3
bash stages/stage-5-secrets-management/infra/vault/setup.sh
bash stages/stage-5-secrets-management/infra/vault/seed-vault-secrets.sh
kubectl exec -n vault vault-0 -- vault kv metadata get clearledger/auth-service

# §5.4a
cp stages/stage-5-secrets-management/infra/manifests/auth-service/deployment.yaml infra/manifests/auth-service/deployment.yaml
cp stages/stage-5-secrets-management/infra/manifests/ledger-service/deployment.yaml infra/manifests/ledger-service/deployment.yaml
mkdir -p infra/manifests/vault
cp infra/deferred-by-stage/stage-5-secrets-management/vault/rotation-cronjob.yaml infra/manifests/vault/rotation-cronjob.yaml
rm -f infra/manifests/auth-service/secret.yaml infra/manifests/ledger-service/secret.yaml
ls infra/manifests/auth-service/ infra/manifests/ledger-service/ infra/manifests/vault/

# §5.4b
sed -i '/- auth-service\/secret.yaml/d' infra/manifests/kustomization.yaml
sed -i '/- ledger-service\/secret.yaml/d' infra/manifests/kustomization.yaml
sed -i '/- rbac\/rbac.yaml/a\  - vault/rotation-cronjob.yaml' infra/manifests/kustomization.yaml
grep -E '^[[:space:]]*-[[:space:]]+(auth-service|ledger-service)/secret\.yaml' infra/manifests/kustomization.yaml && echo STOP || echo OK
grep vault/rotation-cronjob.yaml infra/manifests/kustomization.yaml
grep vault.hashicorp infra/manifests/auth-service/deployment.yaml | head -1
kustomize build infra/manifests >/dev/null && echo "OK: kustomize build"
git add infra/manifests && git commit -m "feat(stage-5): Vault deployments in canonical manifests"

# §5.4c
git clone https://github.com/AliRahimi123456/clearledger-infra.git /tmp/clearledger-infra
cp infra/manifests/auth-service/deployment.yaml /tmp/clearledger-infra/manifests/auth-service/
cp infra/manifests/ledger-service/deployment.yaml /tmp/clearledger-infra/manifests/ledger-service/
mkdir -p /tmp/clearledger-infra/manifests/vault
cp infra/manifests/vault/rotation-cronjob.yaml /tmp/clearledger-infra/manifests/vault/
cp infra/manifests/kustomization.yaml /tmp/clearledger-infra/manifests/kustomization.yaml   # <- this line caused the images: overwrite bug
rm -f /tmp/clearledger-infra/manifests/auth-service/secret.yaml
rm -f /tmp/clearledger-infra/manifests/ledger-service/secret.yaml
cd /tmp/clearledger-infra
git add -A && git status
git commit -m "feat(stage-5): Vault injection; remove app secrets from GitOps"
git push
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"
git clone --depth 1 https://github.com/AliRahimi123456/clearledger-infra.git /tmp/verify-s5
test ! -f /tmp/verify-s5/manifests/auth-service/secret.yaml && echo "OK: app secret removed from Git"
grep vault.hashicorp /tmp/verify-s5/manifests/auth-service/deployment.yaml | head -1
grep vault/rotation-cronjob.yaml /tmp/verify-s5/manifests/kustomization.yaml
rm -rf /tmp/verify-s5

# §5.5 attempt 1 — hit the kustomization.yaml images: bug
kubectl get pods -n clearledger -l app=auth-service
kubectl get pods -n clearledger -l app=ledger-service
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web   # failed: Kyverno rejected YOUR_DOCKERHUB_USERNAME placeholder image
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo
read -s -p "ArgoCD password: " ARGOCD_PW && echo
argocd login argocd.local --username admin --password "$ARGOCD_PW" --insecure --grpc-web

# Root-cause + fix for the images: bug
kubectl get deployment auth-service -n clearledger -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment ledger-service -n clearledger -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment notification-service -n clearledger -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment frontend -n clearledger -o jsonpath='{.spec.template.spec.containers[0].image}'
```
```bash
[assistant, direct fix — precise sed on the images: block in /tmp/clearledger-infra]
sed -i 's/YOUR_DOCKERHUB_USERNAME/rahimi123/g; s/newTag: v0.1.0/newTag: a2eedd94086214b2db9b9408be2a9a86bbd3e83b/g' \
  /tmp/clearledger-infra/manifests/kustomization.yaml
sed -i 's/replace rahimi123 below.../the real Docker Hub username is already set below.../' \
  /tmp/clearledger-infra/manifests/kustomization.yaml
# (also added a permanent warning comment to the app repo's own copy, infra/manifests/kustomization.yaml)
```
```bash
cd /tmp/clearledger-infra
git add manifests/kustomization.yaml
git commit -m "fix: restore real Docker Hub username and current SHA tag (accidentally overwritten by stage-5 copy)"
git push
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web   # succeeded this time; auto-pruned both old Secrets

# §5.5 / §5.5b verify
kubectl get pods -n clearledger -l app=auth-service
kubectl get pods -n clearledger -l app=ledger-service
kubectl get secret -n clearledger

# §5.6
kubectl exec -n clearledger $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) -c auth-service -- ls /vault/secrets/
curl -s -X POST http://clearledger.local/auth/login -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"LearningDevSecOps1"}' | jq .

# §5.7
make check-5
```
