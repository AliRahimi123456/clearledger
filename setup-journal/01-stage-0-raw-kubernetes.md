# Stage 0 — Raw Kubernetes

**Goal (from the book):** ClearLedger runs on Kubernetes — deployed entirely by hand, no CI
or GitOps yet. The point of doing it manually first is to feel *why* manual deploys don't
scale (no audit trail, no rollback, no consistency) before automating it away in later stages.

**Status: ✅ Done and fully verified.** `make check-0` → **28 passed, 0 warnings, 0
failures** — "All checks passed. Ready for the next stage." App reachable in a browser.
Prerequisites for Stage 1 (Docker Hub repos, GitHub PAT, CI secrets) are also already in
place — see the end of this file.

---

## What "done" actually means here

Per the Stage 0 README's checklist:
- `$DOCKER_USERNAME` set; four images on Docker Hub tagged `v0.1.0` ✓
- All app pods `Running` in the `clearledger` namespace; Postgres + Redis healthy ✓
- `curl` auth/ledger/notification health endpoints return 200; UI loads at
  `http://clearledger.local` ✓
- `make check-0` green ✓ (27/0, one cosmetic warning — see below)

---

## What I actually did, step by step

### 1. Docker Hub — created 4 repos
`clearledger-auth-service`, `clearledger-ledger-service`, `clearledger-notification-service`,
`clearledger-frontend` under account `rahimi123`. Public visibility (simpler — no
imagePullSecrets needed in the cluster).

### 2. Built and pushed the 4 images
From inside WSL2, at the repo root:
```bash
cd clearledger
docker build -t rahimi123/clearledger-auth-service:v0.1.0 ./app/auth-service
docker build -t rahimi123/clearledger-ledger-service:v0.1.0 ./app/ledger-service
docker build -t rahimi123/clearledger-notification-service:v0.1.0 ./app/notification-service
docker build -t rahimi123/clearledger-frontend:v0.1.0 ./app/frontend

docker push rahimi123/clearledger-auth-service:v0.1.0
docker push rahimi123/clearledger-ledger-service:v0.1.0
docker push rahimi123/clearledger-notification-service:v0.1.0
docker push rahimi123/clearledger-frontend:v0.1.0
```

**Gotcha hit:** first build attempt failed with `401 Unauthorized` pulling even public base
images (`python:3.13-slim`, `nginx:1.27-alpine`). Cause: `docker login` locally still had a
**stale/revoked** Docker Hub token cached from earlier token rotation. Fix: `docker logout`,
then `docker login -u rahimi123` again with the current valid token (pasted at the interactive
`Password:` prompt, never as a CLI argument or into any file — see credential-hygiene notes).

### 3. Replaced the `DOCKER_USERNAME` placeholder
The four Stage 0 deployment manifests
(`stages/stage-0-raw-kubernetes/infra/manifests/*/deployment.yaml`) ship with a literal
placeholder string, not an env var:
```yaml
image: DOCKER_USERNAME/clearledger-auth-service:v0.1.0
```
Replaced with the real username:
```bash
sed -i 's/DOCKER_USERNAME/rahimi123/' stages/stage-0-raw-kubernetes/infra/manifests/*/deployment.yaml
```

### 4. Applied manifests in order — namespace → RBAC → secrets → stateful infra → apps → ingress
```bash
kubectl apply -f infra/manifests/namespace.yaml
kubectl apply -f infra/manifests/rbac/rbac.yaml
kubectl apply -f infra/manifests/postgres/postgres-secret.yaml
kubectl apply -f infra/manifests/auth-service/secret.yaml
kubectl apply -f infra/manifests/ledger-service/secret.yaml
kubectl apply -f infra/manifests/postgres/postgres.yaml
kubectl apply -f infra/manifests/redis/redis.yaml

kubectl apply -f stages/stage-0-raw-kubernetes/infra/manifests/auth-service/deployment.yaml
kubectl apply -f infra/manifests/auth-service/service.yaml
kubectl apply -f stages/stage-0-raw-kubernetes/infra/manifests/ledger-service/deployment.yaml
kubectl apply -f infra/manifests/ledger-service/service.yaml
kubectl apply -f stages/stage-0-raw-kubernetes/infra/manifests/notification-service/deployment.yaml
kubectl apply -f infra/manifests/notification-service/service.yaml
kubectl apply -f stages/stage-0-raw-kubernetes/infra/manifests/frontend/deployment.yaml
kubectl apply -f infra/manifests/ingress.yaml
```

**Gotcha hit:** unlike auth/ledger/notification (which each have a separate `service.yaml`),
**frontend's Service is bundled inside its `deployment.yaml`**. Applying the shared
`infra/manifests/frontend/deployment.yaml` right after the correct Stage-0 one overwrote the
image back to the wrong placeholder (`clearledger/frontend:gitops`, the Stage-2+ GitOps
version). Fix: re-applied `stages/stage-0-raw-kubernetes/infra/manifests/frontend/deployment.yaml`
last. **Lesson:** always check whether a per-service folder has its own `service.yaml` before
assuming the pattern is uniform across all four services.

### 5. The RBAC failures — the big one
First `make check-0` run: 25 passed, **2 failed**:
```
✗ RBAC: auth-service should not get Secrets (got: yes)
✗ RBAC: clearledger-viewer must not get Secrets (got: yes)
```
The manifest (`infra/manifests/rbac/rbac.yaml`) never grants secrets access to either — so
why could they get it? Root cause: **MicroK8s' own `rbac` addon was disabled**, which means
the API server was running in `AlwaysAllow` authorization mode — every ServiceAccount could
do *everything*, regardless of any Role/RoleBinding. The manifest was correct all along; RBAC
enforcement itself just wasn't switched on at the cluster level.

Fix: `microk8s enable rbac`. This flips the apiserver's `--authorization-mode` flag to
`RBAC,Node` and restarts the apiserver.

**Gotcha hit (again — same pattern as the original MicroK8s install):** `microk8s enable rbac`
internally shells out to `sudo sed -i ...` to edit the apiserver args file. Running it as a
normal user hung forever — no TTY attached in a non-interactive session means `sudo`'s
password prompt just hangs with nothing able to answer it. Killed the hung process and reran
**as root directly** (`wsl -d Ubuntu-20.04 -u root -- microk8s enable rbac`), bypassing `sudo`
entirely — completed in seconds. Same fix documented in `00-machine-setup.md` §9 for the
original `snap install microk8s` hang; this is apparently a recurring theme for any command
this MicroK8s install shells out to `sudo` for in a non-interactive WSL2 session.

After enabling RBAC: **27 passed, 0 failed.**

### 6. `kubectl` needed to be a real command, not just a `.bashrc` alias
`~/.bashrc` has `alias kubectl='microk8s kubectl'`, which only works in *interactive* shells.
`scripts/health-check.sh` (what `make check-0` runs) calls `kubectl` directly as a script —
aliases don't propagate into non-interactive script execution, so it failed with
`kubectl: command not found` until a real wrapper existed. Fixed with:
```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/kubectl <<'EOF'
#!/bin/bash
exec microk8s kubectl "$@"
EOF
chmod +x ~/.local/bin/kubectl
```
`~/.local/bin` is already on `PATH` for login shells by default on Ubuntu, so this just works.
**`helm` has the exact same problem and is NOT fixed yet** — still alias-only. Not needed
until Stage 5 (Vault), so deliberately deferred; same wrapper trick when I get there.

---

## The `/etc/hosts` warning — fixed

`make check-0` originally showed one non-blocking warning:
```
⚠ /etc/hosts entry missing — run scripts/setup-hosts.sh
```
This checks WSL2's *own* internal `/etc/hosts` (separate from the Windows one used for the
browser). `scripts/setup-hosts.sh` itself assumes Multipass (`multipass info clearledger`),
so it doesn't work here — added the entries manually instead, as root to avoid the sudo/TTY
hang:
```bash
wsl -d Ubuntu-20.04 -u root -- bash -lc 'cat >> /etc/hosts <<EOF
127.0.0.1  clearledger.local
127.0.0.1  argocd.local
127.0.0.1  grafana.local
127.0.0.1  vault.local
127.0.0.1  falco.local
127.0.0.1  litmus.local
EOF'
```
`127.0.0.1` is correct here specifically because this is WSL2's *own* loopback (used by
`curl`/`kubectl`/`make check-N` running inside WSL) — it's only the Windows→WSL2 forwarding of
port 80 that's broken (see the browser known-issue section in `00-machine-setup.md`), not
WSL2's internal loopback. After adding these, `make check-0` → **28/28, 0 warnings.**

**Follow-up — it came back, then got fixed permanently (2026-08-10).** The warning
reappeared on a later session: WSL2 **auto-regenerates** `/etc/hosts` on every restart by
default (stated in the file's own auto-generated header comment), silently wiping the manual
entries above each time. Fixed for good by disabling that behavior:
```bash
sudo nano /etc/wsl.conf
```
Added a second section to the existing `[boot]` block:
```ini
[boot]
systemd=true

[network]
generateHosts = false
```
Then a full WSL restart for the config to take effect (`exit` → `wsl --shutdown` from Windows
→ `wsl -d Ubuntu-20.04` back in), followed by re-adding the six hostnames **one more time**
(the same `cat >> /etc/hosts` command above, as root). Verified permanent with a second full
restart cycle — entries survived. Should never need to be re-added again.

---

## Browser access — separate known issue, see `00-machine-setup.md`

Getting `http://clearledger.local` to load in an actual Windows browser (not just `curl` from
WSL) required extra troubleshooting unrelated to the Kubernetes deploy itself — a WSL2/McAfee
networking conflict on port 80 specifically. Full diagnosis and the IP-based workaround (which
needs re-running after every WSL/machine restart) is documented in `00-machine-setup.md`,
under "Known issue: browser can't reach *.local via 127.0.0.1."

---

## Testing the running app

See `00-machine-setup.md` → "Testing the API from the terminal" for the full
login/token/authenticated-request pattern. Test account: `student@example.com` /
`LearningDevSecOps1`.

---

## Incident: alerts silently stop firing after a cluster restart (2026-08-10)

**Symptom:** made a ≥$10,000 transaction (should trigger a compliance alert per the
`amount >= threshold` logic in `ledger-service`), then checked
`curl http://clearledger.local/notifications/alerts` — got back `{"total": 0, "alerts": []}`.
Not just missing the new alert — the *old* alert from days earlier (`ALT-0001`) was gone too.

**First (partially wrong) theory:** old alerts vanishing made immediate sense —
`notification-service` stores alerts **in memory only** (see `docs/architecture.md`:
"replace with a database in production"), and all 8 pods had restarted 58 minutes earlier
(the cluster waking up after being idle across days, a recurring pattern on this machine).
A pod restart wiping in-memory state is expected behavior, not a bug.

**But that didn't explain the brand-new transaction also not alerting.** Checked
`ledger-service` logs first — it *had* correctly published the event:
```
INFO:main:Published large_transaction event for tx 71a9f63e-...
INFO:main:Transaction created: ... | credit 10000.0
```
So the publish side was fine. The problem was `notification-service` not receiving it.

**Root cause, found in its logs** (had to filter out constant `/health` check noise to see it):
```python
redis.exceptions.ConnectionError: Error -3 connecting to redis.clearledger.svc.cluster.local:6379.
Temporary failure in name resolution.
```
`notification-service` subscribes to Redis's `ledger-events` channel **once**, in a background
thread, at startup (`start_subscriber()` in `main.py`). When all pods restarted together after
the idle period, CoreDNS (the cluster's internal DNS) wasn't fully ready yet at the exact
moment this pod tried to resolve `redis.clearledger.svc.cluster.local`. The one-shot subscribe
attempt failed, the background thread died silently, and — critically — **there is no retry
loop in this code.** The web server (and `/health`) kept responding normally the entire time,
which is exactly why this is easy to miss: the pod looks perfectly healthy while its actual
job (listening for alerts) is permanently dead until the next full restart.

**Fix:** force a fresh restart, once Redis/CoreDNS are already stable (so the startup race is
unlikely to repeat):
```bash
kubectl delete pod -n clearledger -l app=notification-service
```
The Deployment controller recreates the pod automatically; this time the subscribe succeeded
on the first try. Re-tested with a new $25,000 transaction → alert `ALT-0001` appeared
correctly in `/notifications/alerts`.

**Why this matters / how to apply going forward:** this demo app has a genuine reliability gap
— a subscriber with no reconnect logic — that's realistic of real production incidents, not
specific to this lab setup. On *this* machine specifically, it's more likely to surface than
it would on a machine that's rarely idle, because MicroK8s here keeps going to sleep and
waking up across multi-day gaps between sessions. **Rule of thumb:** any time alerts seem to
have silently stopped working (especially after a multi-day gap or a cluster restart), check
`notification-service` logs for a `redis.exceptions.ConnectionError` /
`Temporary failure in name resolution` traceback before assuming something else is wrong —
the fix is always the same one-line pod restart above.

**Confirmed recurrence (2026-08-12, during Stage 1 work):** hit the exact same symptom again —
made a `$150,000` credit transaction, `/notifications/alerts` returned `{"total": 0, "alerts":
[]}`. Applied the documented fix directly, no re-diagnosis needed this time (rule of thumb
worked as intended):
```bash
kubectl delete pod -n clearledger -l app=notification-service

# wait ~15s for the new pod to become ready, then confirm:
kubectl get pods -n clearledger -l app=notification-service
```
**Gotcha on the retest:** immediately re-checked alerts and still saw `total: 0` — this is
*not* a fix failure, it's expected: restarting the pod wipes its in-memory alert history too,
including the transaction that had just fired before the restart. The only valid test is a
**new** transaction made *after* the restart:
```bash
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login -H "Content-Type: application/json" -d '{"email":"student@example.com","password":"LearningDevSecOps1"}' | jq -r .access_token)
curl -s -X POST http://clearledger.local/ledger/transactions -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '{"direction":"credit","amount":20000}' | jq
curl -s http://clearledger.local/notifications/alerts | jq
```
Result: `ALT-0001`, `$20,000`, matched exactly. Confirms the rule of thumb from the original
incident is solid and repeatable — this will keep happening on this machine specifically
(idle-prone WSL2/MicroK8s), and the fix is always these same few commands.

---

## §0.7 — Why manual deploys can't be trusted (from the official book, initially missed)

`docs/LAB-GUIDE.md` isn't shipped in the public repo clone (book-exclusive content), so this
exercise was skipped originally. The user later pasted the actual book text from
freeCodeCamp, which revealed it — went back and did it properly before moving to Stage 1.

**Point of the exercise:** deploy a change by hand, watch it work, then deliberately notice
everything I *don't* get from doing it that way — no audit trail, no rollback safety, no
protection against two people clobbering each other's deploys. This is the motivating problem
Stage 1 (CI) and Stage 2 (GitOps) solve.

**Step 1 — make a visible code change.** Edited `app/auth-service/main.py`, line 290 (the
`/health` endpoint), adding a `version` field. Edited via `sed` rather than an editor —
nano's `Ctrl+_` "Go To Line" shortcut didn't register reliably through
Windows Terminal → WSL2 → nano (control character didn't pass through cleanly), and an
earlier attempt to open the file accidentally happened from **Git Bash (MINGW64)** instead of
WSL2, using a Windows-style path in a WSL-style command — nano silently created a new empty
buffer instead of opening the real file, and the subsequent `Ctrl+W` search for "health"
correctly reported "not found" against that empty buffer. Lesson: always confirm which shell
I'm in (`MINGW64` in the prompt = Git Bash, `rahimighaznawi@...` = WSL2) before trusting a
relative path.
```bash
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"
sed -n '290p' app/auth-service/main.py   # confirm the target line first
sed -i '290s/.*/    return {"status": "ok", "service": settings.service_name, "version": "0.2.0"}/' app/auth-service/main.py
sed -n '290p' app/auth-service/main.py   # verify the edit
```

**Step 2 — build, push, and manually deploy the new version:**
```bash
docker build -t rahimi123/clearledger-auth-service:v0.2.0 ./app/auth-service
docker push rahimi123/clearledger-auth-service:v0.2.0
kubectl set image deployment/auth-service auth-service=rahimi123/clearledger-auth-service:v0.2.0 -n clearledger
kubectl rollout status deployment/auth-service -n clearledger
```

**Step 3 — verify the change is actually live:**
```bash
curl -s http://clearledger.local/auth/health | jq
```
Result:
```json
{
  "status": "ok",
  "service": "auth-service",
  "version": "0.2.0"
}
```
Confirmed — the manual deploy genuinely worked.

**Step 4 — the actual lesson (reflection, no commands).** A real deploy just succeeded, and
none of the following exist:
- **Who deployed this?** No record — just whoever ran `kubectl` from their own terminal.
- **What changed?** Only evidence is the Docker tag `v0.2.0`; nothing ties it to a commit or
  code review.
- **What if `v0.2.0` were broken?** Rollback means manually remembering the exact previous
  tag (`v0.1.0`) and re-running `kubectl set image` — if I forget it, or the old image got
  deleted from Docker Hub, I'm stuck.
- **What if someone else `kubectl apply`'d the old version while this deploy was in flight?**
  The cluster would silently revert with no error and no notification.

**Step 5 — revert the code, leave the cluster on v0.2.0** (deliberate — the book says not to
rebuild; Stage 1's CI takes over image management from here):
```bash
sed -i '290s/.*/    return {"status": "ok", "service": settings.service_name}/' app/auth-service/main.py
sed -n '290p' app/auth-service/main.py   # confirm reverted
```

**Status: cluster is currently running `auth-service:v0.2.0`, source code is back to
original.** This mismatch between deployed-version and source-code-version is intentional and
expected — it's exactly the kind of drift Stage 2 (GitOps/ArgoCD) exists to prevent.

---

## Also already done during this stretch (technically Stage 1 prep, noted here for continuity)

- `clearledger-infra` GitHub repo created (empty, per Stage 1/2 requirement)
- GitHub fine-grained PAT generated, scoped to `clearledger-infra`, Contents: Read and write
- Docker Hub access token generated, Read & Write scope
- GitHub Actions repository secrets set on `clearledger` — **verified against the actual
  workflow file** (`.github/workflows/ci.yaml`), not guessed:
  - `DOCKER_USERNAME`
  - `DOCKER_PASSWORD`
  - `INFRA_REPO_TOKEN`

  (First attempt used wrong names — `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN`/`INFRA_REPO_PAT` —
  caught by grepping the workflow file for the actual `secrets.X` references it reads, then
  corrected.)

**Full Stage 1 work will get its own file: `02-stage-1-ci-pipeline.md`, started when that
stage actually begins.**

---

## What I can now claim (per the book)

> You provisioned MicroK8s, built and pushed container images, and deployed a multi-service
> app manually — and can explain **why manual deploys do not scale** (no audit trail, no
> rollback, no consistency).

Concretely demonstrated tonight: registered a user, logged in, created a $15,000 credit and a
$10,000 debit transaction via the live API, and watched `ledger-service` publish to Redis and
`notification-service` pick it up as a real-time compliance alert — fully decoupled, three
independent services, one Postgres database, zero manual wiring between the alert and the
transaction beyond the Redis pub/sub channel itself.
