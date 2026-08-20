# Stage 4 — Admission Control (Kyverno)

**Goal (from the book):** CI (Stage 3) scans code and images *before* they reach the cluster,
but can't stop someone with `kubectl` access from applying an unsafe manifest directly, or a
Helm chart from creating non-compliant pods. Stage 4 adds a second layer: Kyverno, a
Kubernetes-native policy engine that intercepts every resource creation/update via admission
webhooks and can reject it outright — "the bad resource never exists," not "I noticed it
after the fact."

**Status: ✅ Done.** `make check-4` → 17 passed, 1 warning (pre-existing, unrelated Hadolint
note), 0 failures. All 5 policies installed in `Enforce` mode; all 3 break-it scenarios proven
to deny non-compliant pods for real.

---

## Readiness check — and a real recurring issue caught early

Before starting, ran `make check-3` as the book requires. It failed — **the same ArgoCD
`repoURL` placeholder regression from Stage 3, a third time.** This time root-caused properly
instead of just re-fixed blindly: `uptime` showed the WSL2 VM had only been up 13 minutes, and
every single ArgoCD pod's restart counter had ticked up by exactly 1 simultaneously — proof the
whole node had restarted, not that ArgoCD crashed on its own. Working theory, tied to the
already-documented Stage 0 finding (a genuinely unreadable region on this WSL2 distro's virtual
disk): MicroK8s's cluster datastore doesn't reliably persist very recent writes across a VM
restart here, so live `kubectl apply` changes made outside of Git can revert after a restart,
even though the identical fix stays permanently safe in Git history. Same category of issue as
the `/etc/hosts` browser workaround needing to be redone after every WSL restart — now
documented as an expected, low-effort fix rather than a mystery:
```bash
kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web
```
Re-ran `make check-3` → clean (15 passed originally, now consistently reproducible after this
fix). Confirmed `infra/cosign.pub` exists (from Stage 3) and ArgoCD is syncing before
continuing.

## §4.1 — Installed Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm upgrade --install kyverno kyverno/kyverno \
  --version 3.2.8 \
  --namespace kyverno \
  --create-namespace \
  -f stages/stage-4-admission-control/infra/kyverno/values.yaml \
  --wait --timeout=600s
```
Clean install, `STATUS: deployed`, `Kyverno version: v1.12.6`. The repo's custom
`values.yaml` (already in the repo, not something I wrote) disables cleanup CronJobs that
would otherwise fail pulling a since-removed `bitnami/kubectl` image, and loosens the liveness
probe timeout so a loaded single-node VM doesn't trigger a restart-cascade under CPU pressure.

Stability gate: `kubectl get pods -n kyverno` → all 4 controllers (`admission-controller`,
`background-controller`, `cleanup-controller`, `reports-controller`) `1/1 Running`, `0`
restarts.

## §4.2 — Confirmed the Cosign key (already embedded in Stage 3)

Rather than redo the paste, ran the book's three verification checks against the work already
done in Stage 3:
- Check A (placeholder gone): `✓ OK`
- Check B (`grep -c "BEGIN PUBLIC KEY"` → exactly 1 occurrence): confirmed
- Check C (byte-for-byte `diff` between `cosign.pub` and the embedded block): no output, i.e.
  identical

## §4.3 — Applied the five core policies

Applied one at a time (user preference, for clarity) rather than the book's single multi-`-f`
command:
```bash
kubectl apply -f infra/policies/disallow-root.yaml
kubectl apply -f infra/policies/disallow-privilege-escalation.yaml
kubectl apply -f infra/policies/drop-all-capabilities.yaml
kubectl apply -f infra/policies/require-resource-limits.yaml
kubectl apply -f infra/policies/require-signed-images.yaml
```
**Minor hiccup, quickly diagnosed:** `drop-all-capabilities.yaml` got applied twice by mistake
(copy-paste slip), which meant `require-resource-limits.yaml` was skipped initially — caught
immediately via `kubectl get clusterpolicy` showing only 4 policies instead of 5, applied the
missing one, re-verified. All 5 policies confirmed: `READY: True`, `VALIDATE ACTION: Enforce`.

## §4.4 — Broke it on purpose, all 3 scenarios

**Scenario 1 — bare root pod, no `securityContext` at all.** All 4 policies fired at once
(`disallow-root-containers`, `disallow-privilege-escalation`, `drop-all-capabilities`,
`require-resource-limits`), each with a specific rule name and JSON path pointing at exactly
what's missing. `kubectl get pod root-test -n clearledger` → `NotFound`, confirming the pod
never actually existed.

**Scenario 2 — `securityContext` fixed, resource limits forgotten.** Only **one** policy fired
this time (`require-resource-limits`) — clean proof Kyverno evaluates every rule independently;
fixing 3 out of 4 problems doesn't earn a pass on the 4th. `NotFound` confirmed again.

**Scenario 3 — unsigned image, supply-chain attack simulation.** Pushed a real (deliberately
unsigned) test image to Docker Hub under the real repo name:
```bash
docker pull nginx:alpine
docker tag nginx:alpine rahimi123/clearledger-auth-service:unsigned-test
docker push rahimi123/clearledger-auth-service:unsigned-test
cosign verify --key infra/cosign.pub index.docker.io/rahimi123/clearledger-auth-service:unsigned-test
# → Error: no signatures found (sanity check before testing Kyverno)
```
Deployed a pod using that image with an otherwise fully-compliant `securityContext` and
`resources` block (isolating the test to only the signature check), using `index.docker.io/`
per the book's Kyverno-1.12 note. **Blocked** — `require-signed-images` denied it, citing the
same "no signatures found." Noticed the webhook name was `mutate.kyverno.svc-fail`, not
`validate` like the first two scenarios — signature/digest verification runs in Kyverno's
mutate pass, earlier in the pipeline than the security-context checks. `NotFound` confirmed.

Contrast check: `kubectl get deployment auth-service -n clearledger -o jsonpath=...` showed the
real deployment running a proper CI-built, SHA-tagged image — untouched by any of this, since
it predates Kyverno's install (existing pods aren't re-validated, only new pod creation is
checked).

## §4.5 — Confirmed the real app still works

`kubectl get pods -n clearledger` → all 6 app pods `1/1 Running`. `curl
http://clearledger.local/auth/health | jq` → `{"status": "ok", "service": "auth-service"}`.
Kyverno's new rules didn't break anything already running.

(Noted: `postgres-0` and `redis`'s restart counts jumped again "105m ago" — consistent with the
same VM-restart event from earlier in the session, not new crashes.)

## §4.6 — Policy exceptions: skipped, correctly

The book says apply the Postgres `runAsNonRoot` exception *only if* Kyverno actually blocks the
Postgres pod. Since `postgres-0` predates Kyverno's install and hasn't been rescheduled, it was
never re-validated — nothing to fix yet. Worth revisiting if Postgres's pod ever gets
recreated (a crash, another VM restart) while Kyverno is active.

## §4.7 — kube-bench (CIS node-level evidence)

```bash
bash stages/stage-4-admission-control/scripts/run-kube-bench.sh
```
Result: `1 FAIL control(s) present (documented in baseline — no regressions)`, final line
`kube-bench: no regressions vs baseline.` — the pass condition. Plenty of `FAIL`/`WARN` lines
in the raw output (kubelet file permissions, anonymous-auth, etc.) are pre-documented, expected
MicroK8s quirks per the book, not something to chase down in this homelab.

## §4.8 — Final health check

```
make check-4
✓ Passed: 17
⚠ Warnings: 1   (pre-existing Hadolint style note, unrelated to Stage 4)
```
No failures. `make snapshot STAGE=4` expected to fail with the same permanent, known
Multipass-only limitation documented at every prior stage — not attempted again, not a real
problem.

## What I can now claim (per the book)

> Enforced admission control with Kyverno: blocking root containers, privilege escalation,
> unsigned images, and missing resource limits at deploy time — mapped to CIS Kubernetes
> benchmarks.

Concretely demonstrated: watched Kyverno deny three distinct real attack/mistake scenarios
before the pods ever existed, with `NotFound` confirmation each time — plus, as a bonus, caught
and permanently documented a genuine, recurring infrastructure quirk (the post-VM-restart
ArgoCD state reversion) using the same evidence-first, no-guessing approach as every stage
before this one.

## Full command reference — every terminal command run today, in order

```bash
# Readiness (after catching the ArgoCD regression)
make check-3
```
```bash
[assistant, read-only diagnostic — root-causing the regression before just re-fixing it]
kubectl get events -n argocd --sort-by=".lastTimestamp"   # empty — events had already expired
uptime                                                      # "up 13 min" — the key clue
crontab -l                                                  # no crontab, ruled out a scheduled job
systemctl list-timers --all                                 # only routine OS timers (apt, logrotate, etc.), nothing cluster-related
```
```bash
kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
kubectl annotate application clearledger -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync clearledger --grpc-web
make check-3

# §4.1 Install Kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm upgrade --install kyverno kyverno/kyverno --version 3.2.8 --namespace kyverno \
  --create-namespace -f stages/stage-4-admission-control/infra/kyverno/values.yaml \
  --wait --timeout=600s
kubectl get pods -n kyverno

# §4.2 Verify Cosign key already embedded
grep PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE infra/policies/require-signed-images.yaml && echo FAIL || echo OK
grep -c "BEGIN PUBLIC KEY" infra/policies/require-signed-images.yaml
diff infra/cosign.pub <(sed -n '/-----BEGIN PUBLIC KEY-----/,/-----END PUBLIC KEY-----/p' \
  infra/policies/require-signed-images.yaml | sed 's/^[[:space:]]*//')

# §4.3 Apply policies (one at a time)
kubectl apply -f infra/policies/disallow-root.yaml
kubectl apply -f infra/policies/disallow-privilege-escalation.yaml
kubectl apply -f infra/policies/drop-all-capabilities.yaml
kubectl apply -f infra/policies/require-resource-limits.yaml   # initially skipped, applied after catching the gap
kubectl apply -f infra/policies/require-signed-images.yaml
kubectl get clusterpolicy

# §4.4 Scenario 1 — bare root pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
EOF
kubectl get pod root-test -n clearledger

# Scenario 2 — securityContext fixed, limits missing
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nolimits-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
EOF
kubectl get pod nolimits-test -n clearledger

# Scenario 3 — unsigned image
export DOCKER_USERNAME=rahimi123
docker pull nginx:alpine
docker tag nginx:alpine ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
docker push ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
cosign verify --key infra/cosign.pub index.docker.io/${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: unsigned-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: index.docker.io/${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
      resources:
        requests:
          memory: "64Mi"
          cpu: "50m"
        limits:
          memory: "128Mi"
          cpu: "200m"
EOF
kubectl get pod unsigned-test -n clearledger
kubectl get deployment auth-service -n clearledger -o jsonpath='{.spec.template.spec.containers[0].image}'

# §4.5 Verify app still healthy
kubectl get pods -n clearledger
curl -s http://clearledger.local/auth/health | jq .

# §4.7 kube-bench
bash stages/stage-4-admission-control/scripts/run-kube-bench.sh

# §4.8 Final check
make check-4
```
