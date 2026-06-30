# Troubleshooting Reference

Common problems encountered during the lab, with exact diagnostic commands and fixes.

---

## Where am I stuck? (manual decision tree — no scripts)

Answer one question, run the commands, fix **before** advancing.

| Symptom | You are probably at | Run this yourself | Fix |
|---|---|---|---|
| `your-username` / push denied | Stage 0 §0.3 | `echo "$DOCKER_USERNAME"` | `export DOCKER_USERNAME=real-name` and rebuild |
| Workflow “Waiting for a runner” | Stage 1 §1.2 | GitHub → Runners → check label `clearledger` | Add label; empty commit + `git push` |
| Pipeline green but Stage 2 red pods | Stage 2 pre-sync | Clone infra repo; `grep secretKeyRef manifests/auth-service/deployment.yaml` | Re-push §1.3 manifests; confirm `secret.yaml` on GitHub |
| `DATABASE_URL is not set` after ArgoCD | Stage 2 | `grep vault.hashicorp clearledger-infra/manifests/auth-service/deployment.yaml` | Infra repo must use `secretKeyRef` until Stage 5 |
| Scenario 3 does not deny unsigned image | Stage 4 §4.2 | `grep PASTE_YOUR infra/policies/require-signed-images.yaml` | Paste `cosign.pub` into policy by hand |
| Auth `1/2` not `2/2` after Vault | Stage 5 §5.4 | `kubectl logs deploy/auth-service -c vault-agent-init` | Complete §5.3 seed before GitOps push |
| ArgoCD OutOfSync on `vault-secret-rotation` | Stage 5 §5.5b | `argocd app get clearledger --grpc-web` | [Rotation CronJob sync](#argocd-sync-failed-on-vault-secret-rotation-stage-5) |
| `make check-2` fails on health | Stage 2 | `kubectl get pods -n clearledger` + logs | [ArgoCD red pods](#argocd-synced-but-red-pods--health-progressing-stage-2) |

---

## Cluster / VM Issues

### VM not starting

```bash
multipass list
# Check the state column — should show "Running"

multipass start clearledger

# If that fails, delete and recreate:
multipass delete clearledger
multipass purge
./scripts/setup-cluster.sh
```

### kubectl cannot connect

```bash
# Re-export the kubeconfig
multipass exec clearledger -- microk8s config > ~/.kube/clearledger-config
export KUBECONFIG=~/.kube/clearledger-config

kubectl get nodes
# Should show: clearledger   Ready
```

### VM disk full or nearly full

<a id="vm-disk-full-or-nearly-full"></a>

Symptoms: pods `Evicted`, `FailedScheduling` with disk-pressure taints, Helm installs timing out, or `No space left on device` in logs.

**Diagnose first (read-only):**

```bash
make doctor
```

Expected output includes VM disk %, top namespaces by PVC **requested** storage, Prometheus TSDB size (if Stage 7 installed), and **PASS / WARN / FAIL**.

| Verdict | Meaning | Next step |
|---|---|---|
| PASS | Under 75% used | No reclaim needed — look elsewhere (image pull, memory) |
| WARN | 75–89% used | `make reclaim` |
| FAIL | 90%+ used | `make reclaim` immediately; if still FAIL → `make teardown && make setup` |

**Reclaim (safe — does not delete PVCs or running workload data):**

```bash
make reclaim
make doctor    # confirm improvement
```

What reclaim does inside the VM:

- `microk8s ctr` image prune — **unused** images only; images referenced by running pods are kept
- `journalctl --vacuum-size=200M`
- Before/after `df -h /`

What reclaim **does not** do:

- Delete PVCs, Postgres data, or Prometheus TSDB
- Replace resizing the VM or tearing down when the disk is genuinely exhausted

**Preventive caps (new VMs via `make setup`):** kubelet log rotation (`10Mi` × 3 files), image GC at 80%/60%, journald `SystemMaxUse=300M`. Existing VMs: re-run the disk-safety block in `scripts/setup-cluster.sh` or recreate the VM.

**When not to run reclaim:** doctor shows PASS; you need a clean lab reset (use `make teardown` instead); you expect Prometheus or database size to shrink (reclaim will not touch those — reduce retention or tear down).

---

<a id="stage-1-ci-troubleshooting"></a>

## Stage 1 CI / GitHub Actions Issues

Stage 1 is the first time the lab depends on GitHub Actions, a self-hosted
runner, Docker Hub, security scanners, and the separate `clearledger-infra`
repo at the same time. Most failures are configuration or scanner findings,
not broken application code.

### Job stays queued waiting for a runner

Symptom: the workflow shows "Waiting for a runner to pick up this job" even
though the self-hosted runner is online.

Cause: `runs-on` matches runner **labels**, not just the runner name. If the
workflow says:

```yaml
runs-on: [self-hosted, clearledger]
```

then the runner must have a custom label named `clearledger`.

Fix: open GitHub repo -> Settings -> Actions -> Runners -> your runner, then
add the `clearledger` label. After that, re-run the queued job.

### Runner cannot use Docker

Symptom:

```text
permission denied while trying to connect to the Docker API at unix:///var/run/docker.sock
```

Cause: the runner process started before the `ubuntu` user picked up Docker
group membership. The VM uses Docker inside Ubuntu, not Docker Desktop on your
Mac.

Fix inside the VM:

```bash
multipass shell clearledger
groups
docker ps

cd ~/actions-runner
pkill -f "Runner.Listener|Runner.Worker|./run.sh" || true
nohup ./run.sh > _diag/manual-runner.log 2>&1 &
docker ps
```

`docker ps` must work without `sudo`.

### CI build fails: DNS `server misbehaving` or `Could not resolve host`

**You see errors like:**

```text
lookup registry-1.docker.io on 127.0.0.53:53: server misbehaving
Could not resolve host: github.com
```

**Fix — run once on the machine that runs Docker and the GitHub runner:**

| Platform | Command (from repo root) |
|---|---|
| Mac | `bash scripts/configure-vm-network.sh` |
| Linux or WSL2 | `bash scripts/configure-vm-network.sh --inside-vm` |

Then re-run the failed GitHub Actions job.

**Still failing?** Open the build job log → step **Network diagnostic (on build failure)**. Look for `host_dns=` and `container_dns=`. If you see `1 0`, DNS is fixed but Docker networking is not — see the lab guide §7.8.

**Different error** (`[2600:...]: network is unreachable` on Docker Hub push)? That is IPv6 — see [Docker Hub IPv6](#docker-hub-login-or-push-fails-with-ipv6-network-is-unreachable).

### Docker Hub login or push fails with IPv6 `network is unreachable`

Symptom: one or more build-and-scan jobs fail during Docker Hub login, image
push, or blob upload:

```text
dial tcp [2600:1f18:...]:443: connect: network is unreachable
failed to do request: Head "https://registry-1.docker.io/v2/..."
```

Cause: Docker Hub resolves both IPv4 and IPv6 addresses. The Multipass VM can
receive an IPv6 address from DNS, but it does not have a working IPv6 route to
Docker Hub. Docker then tries the unreachable IPv6 path and the job fails even
though IPv4 works.

Verify from the VM:

```bash
multipass shell clearledger
curl -4 -sS --connect-timeout 10 https://registry-1.docker.io/v2/ -o /dev/null -w "%{http_code}\n"
curl -6 -sS --connect-timeout 10 https://registry-1.docker.io/v2/ -o /dev/null -w "%{http_code}\n" || true
```

Expected: IPv4 returns `401` (normal unauthenticated registry response). IPv6
fails or times out.

Fix: prefer IPv4 and disable unusable IPv6 in the VM:

```bash
sudo cp /etc/gai.conf /etc/gai.conf.clearledger.bak 2>/dev/null || true
printf '\n# ClearLedger lab: prefer IPv4 because Docker Hub IPv6 is unreachable from this VM\nprecedence ::ffff:0:0/96  100\n' \
  | sudo tee -a /etc/gai.conf

sudo tee /etc/sysctl.d/99-clearledger-ipv4.conf >/dev/null <<'EOF'
# ClearLedger lab: disable IPv6 on this VM because Docker Hub AAAA routes are unreachable
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sudo sysctl -w \
  net.ipv6.conf.all.disable_ipv6=1 \
  net.ipv6.conf.default.disable_ipv6=1 \
  net.ipv6.conf.lo.disable_ipv6=1

sudo systemctl restart docker
```

Then restart the GitHub runner:

```bash
cd ~/actions-runner
pkill -f "[R]unner.Listener" 2>/dev/null || true
pkill -f "[R]unner.Worker" 2>/dev/null || true
nohup ./run.sh > _diag/manual-runner.log 2>&1 &
```

Test the Docker daemon path:

```bash
docker pull hello-world:latest
```

If that pull works, re-run the failed GitHub Actions jobs.

### `pip: command not found`

Symptom:

```text
/home/ubuntu/actions-runner/_work/_temp/...sh: line 1: pip: command not found
```

Cause: the self-hosted runner VM may not have a `pip` executable on `PATH`.

Fix in workflow steps that install Python tools:

```yaml
run: |
  sudo apt-get update
  sudo apt-get install -y python3-pip
  python3 -m pip install --user checkov
  echo "$HOME/.local/bin" >> "$GITHUB_PATH"
```

Use `python3 -m pip install --user ...`, not plain `pip install ...`.

### Gitleaks finds demo secrets

Symptom: `secrets-scan` fails with findings like:

```text
RuleID: generic-api-key
RuleID: jwt
RuleID: aws-access-token
leaks found
```

Cause: the lab intentionally contains example secrets in docs and demo files so
learners can see security tools catch them. Because the workflow scans git
history, those known examples can fail the first run.

Fix: keep `.gitleaksignore` with only confirmed lab-demo fingerprints. Do not
add new findings blindly. If a new secret appears, treat it as real until you
prove it is test data.

### IaC scan fails on Kubernetes manifests

Symptom: Checkov reports many Kubernetes failures such as missing resource
limits, missing seccomp, or containers not using strict security contexts.

Cause: those are real hardening gaps, but Stage 1 is about proving the
build-scan-push-manifest-update flow. Kubernetes policy is tightened later.

Fix: Stage 1 keeps the Kubernetes Checkov scan evidence-only:

```bash
checkov --directory infra/manifests --framework kubernetes --soft-fail
```

Dockerfile checks can still block HIGH/CRITICAL issues because the Dockerfiles
are part of the artifact built in Stage 1.

### Dockerfile scan fails on `Dockerfile.dev`

Symptom: Checkov fails because `app/frontend/Dockerfile.dev` does not have a
production-style `HEALTHCHECK`.

Cause: `Dockerfile.dev` is for local development, not the production image
built by the pipeline.

Fix: skip that dev-only file in the Dockerfile scan:

```bash
checkov --directory . --framework dockerfile --skip-path app/frontend/Dockerfile.dev
```

### Trivy install fails (`trivy: command not found` or apt Release errors)

Symptom:

```text
E: The repository 'http://archive.ubuntu.com/ubuntu jammy Release' no longer has a Release file.
...
trivy: command not found
Error: Process completed with exit code 127.
```

Cause: an older workflow installed Trivy via `apt`. That requires a healthy Ubuntu
mirror on the runner VM. When `apt-get update` fails, Trivy never installs even
though Syft and Grype (installed from GitHub release binaries) succeed.

Fix: the workflow installs Trivy from the official GitHub release tarball into
`$HOME/.local/bin` — same pattern as Syft, Grype, and Cosign. Pull the latest
`clearledger` repo so `.github/workflows/ci.yaml` includes that install step, then
re-run the pipeline.

To verify on the runner VM:

```bash
multipass shell clearledger
export PATH="$HOME/.local/bin:$PATH"
trivy --version
```

If missing, install once manually (optional — the next CI run installs it):

```bash
mkdir -p ~/.local/bin
curl -sL "https://github.com/aquasecurity/trivy/releases/download/v0.70.0/trivy_0.70.0_Linux-64bit.tar.gz" \
  | tar -xzC "$HOME/.local/bin" trivy
trivy --version
```

### Trivy "Version X is now available" notice (not a scan failure)

Symptom — at the **bottom** of a failed **Scan images** log:

```text
📣 Notices:
  - Version 0.71.2 of Trivy is now available, current version is 0.70.0
...
Error: Process completed with exit code 1.
```

**This notice is informational.** Trivy does **not** exit 1 because a newer scanner release exists. The failure is a fixable HIGH/CRITICAL CVE under `--exit-code 1`. Do **not** add `--skip-version-check` to "fix" the gate — it only hides the notice; the CVE still fails the scan.

**What to do:** scroll up for the CVE table (Package | CVE | Severity | Installed | Fixed Version), or download the `image-scan-results` artifact (`trivy-auth-results.json`). Fix the package or base image per [LAB-GUIDE §3.5](LAB-GUIDE.md#35--when-a-scan-fails-on-a-cve-you-didnt-inject).

**Maintainers:** `TRIVY_VERSION` is pinned in `.github/workflows/ci.yaml` — bump it periodically for scanner hygiene. That is unrelated to scan gate failures; those are always real CVEs.

### Trivy install fails after "found version"

Symptom:

```text
aquasecurity/trivy info checking GitHub for tag 'v0.52.1'
aquasecurity/trivy info found version: 0.52.1 for v0.52.1/Linux/64bit
Error: Process completed with exit code 1.
```

Cause: the install script/version download can fail on the self-hosted runner.
The fix is to avoid reinstalling tools on every run when they are already
present.

Fix: install Trivy once on the VM runner and make the workflow idempotent:

```bash
multipass shell clearledger
mkdir -p ~/.local/bin
curl -sL "https://github.com/aquasecurity/trivy/releases/download/v0.70.0/trivy_0.70.0_Linux-64bit.tar.gz" \
  | tar -xzC "$HOME/.local/bin" trivy
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
trivy --version
```

Workflow steps should check for the tool before downloading it:

```bash
export PATH="$HOME/.local/bin:$PATH"
if ! command -v trivy &>/dev/null && ! [ -f "$HOME/.local/bin/trivy" ]; then
  # install trivy
fi
```

### Trivy blocks Python service images

Symptom: the Docker build finishes, but the build-and-scan job still fails
during the image scan.

Cause: Trivy is doing its job. It found HIGH/CRITICAL vulnerabilities in Python
dependencies.

Fixes applied in this lab:

| Package | Old version | Fixed version | Why |
|---|---:|---:|---|
| `fastapi` | `0.111.0` | `0.115.12` | Pulls a fixed `starlette` version |
| `protobuf` | transitive `4.25.9` | `>=5.29.6` | Fixes protobuf HIGH CVE |
| `setuptools` | `>=69.0.0,<82.0.0` | `>=78.1.1` | Fixes setuptools HIGH CVEs |
| `python-jose` | `3.3.0` | `3.4.0` | Fixes auth-service CRITICAL CVE |
| `python-multipart` | `0.0.9` | `0.0.30` | Fixes auth-service HIGH CVEs (e.g. CVE-2026-53539) |

After changing requirements, rebuild the images and scan again:

```bash
docker build -t clearledger-ledger-service:test ./app/ledger-service
trivy image --severity CRITICAL,HIGH --ignore-unfixed clearledger-ledger-service:test
```

### Trivy blocks the frontend image

Symptom: the frontend image scan reports many OS package CVEs in
`nginx:1.27-alpine`, including OpenSSL CRITICAL findings.

Cause: the base image includes Alpine packages that need security updates.

Fix: upgrade Alpine packages during the image build:

```dockerfile
FROM nginx:1.27-alpine

RUN apk update && apk upgrade --no-cache
```

This pulls patched versions of packages such as `openssl`, `libexpat`, and
`libpng` when the image is built.

### Cosign download or signing slows/fails Stage 1

Symptom: Cosign download hangs, the binary is incomplete, or signing fails even
after the image was built and pushed.

Cause: Cosign is fetched from GitHub release assets, which can be slow from the
Multipass VM. Signing is important, but Stage 1's main goal is CI build, scan,
push, and GitOps handoff. Stage 4 enforces signature verification at admission.

Fix for Stage 1:

1. Pre-install Cosign once on the runner.
2. Make the workflow skip download when `cosign` already exists.
3. Mark Stage 1 signing/attestation steps non-blocking.

```bash
multipass shell clearledger
mkdir -p ~/.local/bin
curl -sSfL https://github.com/sigstore/cosign/releases/download/v2.2.4/cosign-linux-amd64 \
  -o "$HOME/.local/bin/cosign"
chmod +x "$HOME/.local/bin/cosign"
cosign --version
```

If the download is interrupted, delete the partial file and download again:

```bash
rm -f ~/.local/bin/cosign ~/.local/bin/cosign.tmp
```

### Syft or Grype install is slow

Symptom: SBOM or vulnerability scan steps spend a long time installing Syft or
Grype.

Cause: the runner downloads those binaries during the job.

Fix: pre-install them once on the runner and keep workflow installs
idempotent:

```bash
multipass shell clearledger
mkdir -p ~/.local/bin
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
  | sh -s -- -b "$HOME/.local/bin"
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh \
  | sh -s -- -b "$HOME/.local/bin"
syft --version
grype --version
```

### Manifest update points to the wrong image path

Symptom: the pipeline pushes images, but `clearledger-infra` references
`docker.io/library/...` or an image path without your Docker Hub username.

Cause: local Docker image names do not include the registry username. The
manifest update must use the pushed image path, not the local build tag.

Fix: update manifests with the full registry path:

```bash
image: docker.io/YOUR_DOCKER_USERNAME/clearledger-auth-service:GIT_SHA
```

In the workflow this should come from:

```bash
REGISTRY=docker.io/${{ secrets.DOCKER_USERNAME }}
```

### DAST fails in Stage 1

Symptom: OWASP ZAP or API smoke tests fail because the app is not reachable.

Cause: Stage 1 updates `clearledger-infra`, but it does not deploy to the
cluster. ArgoCD is installed in Stage 2.

Fix: keep DAST opt-in for Stage 1:

```yaml
if: github.ref == 'refs/heads/main' && github.event_name == 'push' && vars.ENABLE_DAST == 'true'
```

Enable it later by adding a repository variable named `ENABLE_DAST` with value
`true`.

### Argo CD install fails: `applicationsets.argoproj.io` annotation too long

Symptom (near the end of `kubectl apply`):

```text
The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
metadata.annotations: Too long: must have at most 262144 bytes
```

Cause: plain `kubectl apply` stores the full CRD in a `last-applied-configuration`
annotation. The ApplicationSet CRD exceeds Kubernetes' 256 KiB limit.

Fix: server-side apply (required by upstream Argo CD). If plain `apply` already
created most resources, re-run with these flags — it finishes idempotently:

```bash
kubectl apply -n argocd --server-side --force-conflicts -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s
```

### ArgoCD refresh fails in Stage 1

Symptom: `update-manifests` fails on **Trigger ArgoCD refresh** — errors like
`namespaces "argocd" not found` or `application clearledger not found`.

Cause: That step is for **Stage 2+** when ArgoCD is installed. Stage 1 should
only update `clearledger-infra`, not touch the cluster.

Fix: leave repository variable `ENABLE_ARGOCD_SYNC` **unset** during Stage 1.
The step is skipped automatically when the variable is missing or not `true`.
Enable it after ArgoCD's first healthy sync (Stage 2): set `ENABLE_ARGOCD_SYNC`
to `true` under **Settings → Secrets and variables → Actions → Variables**.

---

## Pod Issues

### Pod stuck in Pending

```bash
kubectl describe pod POD_NAME -n clearledger
# Look for: "Insufficient memory" or "Insufficient cpu"
# Fix: reduce resource requests in the deployment

# Look for: "0/1 nodes are available"
kubectl get nodes
kubectl describe node clearledger
# Check conditions at the bottom — is memory pressure indicated?
```

### Pod stuck in CrashLoopBackOff

```bash
kubectl logs POD_NAME -n clearledger
kubectl logs POD_NAME -n clearledger --previous

# Common causes:
# - Database not ready yet (wait for postgres readiness probe)
# - Wrong DATABASE_URL (check secret values)
# - Vault not configured yet (check vault-agent-init logs)
kubectl logs POD_NAME -n clearledger -c vault-agent-init
```

### readOnlyRootFilesystem causing failures

```bash
# If the app writes temp files, add an emptyDir volume:
# In deployment.yaml, add to volumes:
volumes:
  - name: tmp
    emptyDir: {}
# And to the container's volumeMounts:
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

### Image pull failures from Docker Hub

```bash
# Confirm the Deployment references Docker Hub images
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

# Verify the image tag exists in Docker Hub (web UI)
#   hub.docker.com → repositories → clearledger-auth-service → tags

# If you're hitting Docker Hub rate limits, try again later or authenticate pulls.
```

---

---

<a id="stage-4-admission-control-troubleshooting"></a>

## Stage 4 — Admission Control (Kyverno)

Stage 4 installs Kyverno, applies five ClusterPolicies, and runs break-it scenarios to prove enforcement. The failures below were hit during lab setup on MicroK8s — they are the same class of issues you see rolling admission control into a real cluster.

### Quick reference

| Problem | Symptom | Root cause | Fix |
|---|---|---|---|
| Kyverno cleanup pods | `ImagePullBackOff` on `bitnami/kubectl:1.28.5` | Bitnami removed public images from Docker Hub | Lab values file (see below) |
| Helm upgrade stuck | `pending-upgrade`, duplicate pods, `ErrImagePull` | Slow `ghcr.io` pulls + partial upgrade | Full teardown, reinstall chart 3.2.8 |
| Helm upgrade to 3.6.4 | CRD patch error (`selectableFields`) | Kyverno 1.16 needs Kubernetes ≥1.30 | Stay on chart 3.2.8 / Kyverno 1.12.x |
| Signature policy silent | Unsigned pod admitted with `docker.io/...` | `verifyImages` matches `index.docker.io/*` reliably | Use full registry URL + `failurePolicy: Fail` |
| Scenario 3 false negative | Pod created, then `ImagePullBackOff` | Tag never pushed to Docker Hub | Push `unsigned-test` tag; verify with `cosign verify` |
| `make check-4` kube-bench fail | Script exits immediately on macOS | Empty baseline; `grep` + `pipefail` | Run baseline scan; script compares regressions only |
| Health check false negative | “Kyverno not running” | Wrong pod label selector | Use `app.kubernetes.io/component=admission-controller` |
| Kyverno RESTARTS climbing (50+) | `kubectl` TLS timeouts; API sluggish | Default liveness probe (`timeoutSeconds: 5`) on loaded single-node VM → restart storm hammers MicroK8s dqlite | Reinstall with `stages/stage-4-admission-control/infra/kyverno/values.yaml`; run `bash scripts/health-check.sh 4`; scale down Litmus (LAB-GUIDE §7.0); teardown only if cluster was patched off-guide |

---

### Kyverno cleanup pods in ImagePullBackOff

**Symptom:**

```bash
kubectl get pods -n kyverno
# kyverno-cleanup-admission-reports-...   ImagePullBackOff
# ... pulling bitnami/kubectl:1.28.5
```

**Cause:** Kyverno Helm chart ≤3.5 uses `bitnami/kubectl` for cleanup CronJobs and uninstall hooks. Bitnami removed those images from `docker.io/bitnami`.

**Fix:** Install with the lab values file — it disables cleanup CronJobs (they only prune old PolicyReports) and points Helm hooks at `bitnamilegacy/kubectl`:

```bash
helm upgrade --install kyverno kyverno/kyverno \
  --version 3.2.8 \
  --namespace kyverno --create-namespace \
  -f stages/stage-4-admission-control/infra/kyverno/values.yaml \
  --wait --timeout=600s
```

If Helm uninstall hangs on a scale-to-zero hook, force-delete stuck jobs/pods in `kyverno` namespace, then delete the namespace.

---

### Helm upgrade stuck or duplicate Kyverno pods

**Symptom:** `helm list -n kyverno` shows `failed` or `pending-upgrade`; old and new admission-controller pods coexist; some in `ErrImagePull`.

**Cause:** Upgrading to chart 3.5.3+ on a slow connection while images pull from `ghcr.io/kyverno`; or layering upgrades without cleaning up a failed release.

**Fix — clean reinstall (MicroK8s / Kubernetes 1.29):**

```bash
helm uninstall kyverno -n kyverno || true
kubectl delete jobs -n kyverno --all --force --grace-period=0 2>/dev/null || true
kubectl delete namespace kyverno --force --grace-period=0
kubectl delete clusterpolicy --all
kubectl get crd | grep kyverno | awk '{print $1}' | xargs kubectl delete crd

helm upgrade --install kyverno kyverno/kyverno \
  --version 3.2.8 \
  --namespace kyverno --create-namespace \
  -f stages/stage-4-admission-control/infra/kyverno/values.yaml \
  --wait --timeout=600s
```

**Do not** upgrade to chart 3.6.4 on Kubernetes 1.29 — CRD patch fails with `selectableFields: field not declared in schema`.

---

### Signature policy does not block unsigned images

**Symptom:** Scenario 3 pod is **created** (Running or ImagePullBackOff) instead of admission denial naming `require-signed-images`.

**Causes and fixes:**

1. **Image URL format** — use `index.docker.io/${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test`, not `docker.io/...` alone. Kyverno 1.12 `verifyImages` matching is reliable on the canonical form.

2. **Tag does not exist** — if the tag was never pushed, the pod may be admitted then fail at pull (`ImagePullBackOff`). That is not signature enforcement. Push the unsigned test image first:

```bash
docker pull nginx:alpine
docker tag nginx:alpine ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
docker push ${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
cosign verify --key infra/cosign.pub \
  index.docker.io/${DOCKER_USERNAME}/clearledger-auth-service:unsigned-test
# Expected: Error: no signatures found
```

3. **Policy missing fail-closed settings** — `infra/policies/require-signed-images.yaml` must include:

```yaml
spec:
  webhookTimeoutSeconds: 30
  failurePolicy: Fail
```

Re-apply: `kubectl apply -f infra/policies/require-signed-images.yaml`

**Expected denial:**

```text
admission webhook "mutate.kyverno.svc-fail" denied the request:
require-signed-images:
  verify-cosign-signature: 'failed to verify image ... no signatures found'
```

---

### `make check-4` fails on kube-bench

**Symptom:** Health check reports `kube-bench regressions detected` or the script exits with no summary.

**Cause:** Baseline file was empty on first run; on macOS, `run-kube-bench.sh` used `grep` with `set -o pipefail` and exited when no `INFO` statuses existed.

**Fix:**

```bash
kubectl delete job -n kube-system kube-bench --ignore-not-found
bash stages/stage-4-admission-control/scripts/run-kube-bench.sh
make check-4
```

The script compares against `kube-bench-baseline.json` and only fails on **new** regressions (PASS/WARN → FAIL). Known MicroK8s FAILs documented in the baseline are acceptable.

---

### Health check says Kyverno not running

**Symptom:** `make check-4` fails “Kyverno not running” but `kubectl get pods -n kyverno` shows controllers Running.

**Cause:** Health check looked for label `app=kyverno`; Kyverno pods use `app.kubernetes.io/component=admission-controller`.

**Fix:** Verify manually:

```bash
kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller
```

Ensure you are on a current `scripts/health-check.sh` (Stage 4 check uses the correct label).

---

### Policies not READY

```bash
kubectl get clusterpolicy
# READY column empty or False
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=50
```

Common causes: admission controller not Running; typo in policy YAML; applying `verify-slsa-provenance.yaml` before it is configured (skip it for Stage 4 — apply only the five core policies listed in LAB-GUIDE §4.3).

---

## Kyverno Issues

### Kyverno blocking a deployment you expect to pass

```bash
# See the exact policy that blocked it
kubectl get events -n clearledger --sort-by='.lastTimestamp' | tail -20

# Check which policies are active and in what mode
kubectl get clusterpolicy

# Temporarily switch a policy to Audit to diagnose:
kubectl patch clusterpolicy disallow-root-containers \
  --type merge \
  -p '{"spec":{"validationFailureAction":"Audit"}}'
# Remember to switch back to Enforce after diagnosing
```

### PolicyReport showing violations

```bash
kubectl get policyreport -n clearledger
kubectl describe policyreport -n clearledger

# Each violation shows: resource, policy, rule, message
# Fix the resource or create a PolicyException if the exemption is legitimate
```

---

## Stage 6 — Runtime Security (Falco)

> Full walkthrough: [LAB-GUIDE.md § Stage 6](../docs/LAB-GUIDE.md#stage-6--runtime-security-falco)

### Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| UI flooded with Critical **Sensitive File Read** on **postgres-0** | Postgres reads `/etc/passwd` on a schedule — not your demo | Ignore; find **Shell Spawned** on **auth-service** ([LAB-GUIDE — plain English](../docs/LAB-GUIDE.md#stage-6-in-plain-english-read-this-if-you-feel-lost)) or `grep 'Shell Spawned'` in Falco logs |
| Cannot find demo alert in UI | Hundreds of postgres rows bury it | **Cmd+F → `Shell Spawned`** or terminal: `kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=500 \| grep 'Shell Spawned'` |
| `make check-6` fails on NetworkPolicy | Netpol not applied yet (§6.4) | `kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml` then re-run |
| `make fix-65-prereqs` → ArgoCD ComparisonError | Ran without `GITHUB_OWNER` — reset repoURL to placeholder | `export GITHUB_OWNER=your-user` then `kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml` |
| Auth `Init:0/1` Vault `permission denied` after snapshot | VM restart wiped Vault dev config | Re-run `setup.sh` + `seed-vault-secrets.sh`, delete auth/ledger pods — see LAB-GUIDE [Path D](#saving-your-progress) |
| Auth `Init:0/1` Vault `permission denied` after Mac reboot | Same — K8s auth binding lost | Same Path D steps; `make restore` only if pods stay broken |
| Scenario 4 `kubectl exec` hangs forever | `head -1` picked a **Terminating** pod | Use the `awk '$2=="2/2"'` pod picker in LAB-GUIDE §6.4 |
| Scenario 4 `wget: not found` | Ledger image has no wget/curl | Use the **python3** command in LAB-GUIDE §6.4 |
| Scenario 4 shows timeout / refused / BLOCKED | **Expected** — ledger → notification is blocked | Success; optional demo only |
| `helm install` times out on Falco DaemonSet | Init container pulling plugins from ghcr.io (slow VM) | Wait; re-run `install-falco.sh`; check `kubectl get pods -n falco` until **2/2 Running** |
| Falco pod CrashLoopBackOff | Invalid rule field in custom rules | Check `kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco`; use `k8smeta.ns.name = clearledger` (requires `collectors.kubernetes.enabled: true` in Helm values) |
| `helm install` “cannot re-use a name” | Falco already installed | Re-run `bash stages/stage-6-runtime-security/scripts/install-falco.sh` |
| No alerts after `kubectl exec` | Rules not loaded or wrong namespace | Confirm `clearledger_rules.yaml \| schema validation: ok` in Falco logs |
| Auth/notification health fails after netpol | Ingress namespace label or missing allow rule | Confirm `ingress` namespace has `kubernetes.io/metadata.name=ingress` |
| Falco UI unreachable | Ingress not applied | `kubectl apply -f stages/stage-6-runtime-security/infra/falco-ingress.yaml` |
| **`http://falco.local` → 503** | Ingress points at `falco-falcosidekick-ui` but `falcosidekick.enabled: false` | Set `falcosidekick.enabled: true` and `falcosidekick.webui.enabled: true` in `stages/stage-6-runtime-security/infra/falco/helm-values.yaml`, then `bash stages/stage-6-runtime-security/scripts/install-falco.sh`; confirm `kubectl get endpoints falco-falcosidekick-ui -n falco` is not `<none>` |
| Falco UI shows login form / "can't be empty" | UI has basic auth enabled (default) | Login **admin**, password **admin** — or `kubectl get secret falco-falcosidekick-ui -n falco -o jsonpath='{.data.FALCOSIDEKICK_UI_USER}' \| base64 -d` |

## Stage 6.5 — Chaos Engineering (LitmusChaos)

> Full walkthrough: [LAB-GUIDE.md § Stage 6.5](../docs/LAB-GUIDE.md#stage-65--chaos-engineering-optional)

### Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `no matches for kind "ChaosEngine"` | Operator not installed | `bash stages/stage-6.5-chaos-engineering/scripts/install-litmus.sh` (needs **litmus-core**, not ChaosCenter UI alone) |
| `Unable to get chaos resources` | Experiments not in `litmus` namespace | Re-run install script; `kubectl get chaosexperiment pod-delete -n litmus` |
| Kyverno denies `*-runner` pod in clearledger | Stage 4 policies block non-compliant pods | **Expected** — keep `ChaosEngine` in `litmus` namespace (see LAB-GUIDE §6.5.2) |
| `serviceaccount "litmus-admin" not found` | RBAC applied to wrong namespace | `kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/litmus-rbac.yaml` (SA in **litmus**) |
| ChaosResult verdict **Error** but health stayed 200 | Litmus targeted pod in Vault Init | Pass criteria = health during chaos + 2 replicas recovered (see LAB-GUIDE §6.5.4) |
| `/auth/health` fails during chaos | Only 1 replica or probe misconfigured | `kubectl get deploy auth-service -n clearledger` — need `replicas: 2` |
| New auth pod stuck `Init:0/1` | Vault agent init after recreate | Wait 1–2 min; normal after pod delete in Stage 5 |
| Litmus UI not reachable | Ingress not applied | `kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/litmus-ingress.yaml`; add `litmus.local` to `/etc/hosts` |
| Litmus UI **blank** / empty Overview (**0** infrastructures) | Cluster not connected — no subscriber agent | `export LITMUS_PASSWORD='your-password'` then `make connect-litmus`; open **http://litmus.local** (not `/account/.../settings` URLs) |
| Infrastructure stuck **PENDING** | Subscriber waiting for unhealthy `event-tracker` pod | `make connect-litmus` (disables event-tracker + patches subscriber); confirm `IS_INFRA_CONFIRMED=true` in `subscriber-config` |
| Litmus wizard labels differ from LAB-GUIDE | ChaosCenter UI changes between 3.x versions | Match fields by **meaning** (namespace, label, 50%, 30s) — see LAB-GUIDE §6.5.2 Step 3 concept table |
| Litmus UI loads but API errors | Ingress missing `/backend/` route | Re-apply `litmus-ingress.yaml`; `kubectl set env deployment/chaos-litmus-server -n litmus --containers=graphql-server INGRESS=true INGRESS_NAME=litmus-ingress` |
| Litmus UI login fails | Wrong credentials | Default **admin** / **litmus** (see `litmus-values.yaml`) |
| ArgoCD **Progressing**, many `auth-service` ReplicaSets | Auth pods 1/2 or OOM; repeated failed rollouts | `make fix-argocd` — applies startupProbe + 384Mi + postgres netpol; prunes old ReplicaSets |

## Stage 7 — Observability (Grafana + Prometheus + Loki)

> Full walkthrough: [LAB-GUIDE.md § Stage 7](../docs/LAB-GUIDE.md#stage-7--security-observability)

### Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `http://grafana.local` doesn’t load | Hostname not in `/etc/hosts` or ingress not ready | Re-run `bash scripts/setup-hosts.sh`; check `kubectl get ingress -n monitoring` |
| Health check: “Grafana not reachable” | NGINX ingress controller down | `kubectl get pods -n ingress`; re-run cluster setup if needed |
| Grafana sidecar CrashLoopBackOff | MicroK8s API CA fails SSL verify in k8s-sidecar | Re-run installer — it sets `grafana.sidecar.skipTlsVerify=true` |
| Grafana pod not 3/3 Ready | Sidecar TLS or datasource conflict | Confirm Loki helm uses `loki.isDefault=false`; check `kubectl logs -n monitoring POD -c grafana-sc-dashboard` |
| Browser console: `not correct url` / `skipping rendering` | Old dashboard slug cached in Grafana | Re-run installer (purges stale UIDs + restarts Grafana); open **UID-only** links from LAB-GUIDE §7.3 |
| Browser console: `404 userstorage.grafana.app` | Harmless Grafana UI feature | Ignore — does not affect dashboards |
| WebSocket `api/live/ws` failed | Grafana Live disabled intentionally | Ignore after re-install — `[live] enabled = false` |
| Loki `connection refused` / all log panels empty | Loki restarting under load or still starting | `kubectl get pods -n monitoring loki-0`; test `http://loki:3100/ready` from Grafana pod (LAB-GUIDE §7.1); `FORCE=1 bash stages/stage-7-observability/scripts/install-observability.sh` |
| Panels empty but Loki/Prometheus healthy | No events in time range yet | Run hands-on lab LAB-GUIDE §7.4 or `generate-dashboard-data.sh` |
| Falco dashboard empty, Kyverno/Auth partial | Wrong LogQL labels, stat `$__range`, missing Falco metrics | Re-apply dashboards: `bash stages/stage-7-observability/scripts/install-observability.sh`; set **Last 15 minutes** |
| Failed Login stat shows count but log stream **No data** after refresh | Grafana time range > Loki `max_query_length` (was 1h) or auto-refresh hammering Loki | Re-run `FORCE=1 bash stages/stage-7-observability/scripts/install-observability.sh` (sets `max_query_length: 24h`, disables dashboard auto-refresh) |
| Failed Login **stat** empty but log stream shows lines | Loki stat panels used instant query + `$__range` (Grafana does not substitute it for Loki instant) | Re-run `bash stages/stage-7-observability/scripts/install-observability.sh` — stats now use range query + `$__interval` + sum |
| Failed Login stat empty, log stream works | Wrong Loki label (`app`) or stale logs | Use `container="auth-service"` + `Failed login attempt`; re-run failed-login curl loop; hard-refresh Grafana |
| Pod Status / Request Rate empty | PromQL used labels metrics do not have | Pod: `sum(kube_pod_status_ready{namespace="clearledger"} == 1)`; HTTP: `rate(http_requests_total[5m])` (no `namespace` on app counter) |
| Runtime Threat Trend empty (Compliance) | LogQL on Prometheus datasource | Panel must use **Loki** — re-run `install-observability.sh` after pulling dashboard JSON |
| Falco sidekick pods Error | WebUI enabled on small clusters | `falcosidekick.enabled: false` in stage-6 falco helm-values; `helm upgrade falco …` |
| Argo CD `503` / `ERR_TOO_MANY_REDIRECTS` on `/api/v1/stream` | Incomplete server params | `kubectl apply -f stages/stage-2-gitops/infra/argocd-cmd-params.yaml` + restart `argocd-server` (LAB-GUIDE §2) |
| Grafana refresh stuck on **Cancel all queries** | Too many Loki panels + wide time range (24h Falco logs) + query queue | Set **Last 1 hour**; re-run `bash stages/stage-7-observability/scripts/install-observability.sh`; close tab and reopen dashboard |
| Loki **RESTARTS** keeps climbing | Too many heavy log queries at once | Open one dashboard; use **Last 1 hour**; wait for Loki stable, then reload |
| Loki `too many outstanding requests` | Loki busy or recovering | Wait 1–2 min; shorten time range; re-run installer if it persists |
| Helm `stream error` / `INTERNAL_ERROR` | Transient API server disconnect | Wait 30s; `FORCE=1 bash stages/stage-7-observability/scripts/install-observability.sh` (retries 3×) |
| Installer skips Helm | Already healthy — by design | Use `FORCE=1` only when you need to change Helm values |
| Request Rate panel empty | Stock images lack `/metrics` | **Rebuild required:** `bash stages/stage-7-observability/scripts/build-metrics-images.sh` |
| Loki pods Pending | No default StorageClass (common on MicroK8s) | Re-run installer (auto-disables persistence): `bash stages/stage-7-observability/scripts/install-observability.sh` |
| No dashboards in Grafana | Sidecar not loaded ConfigMaps yet | Wait 30–60s; `kubectl get cm -n monitoring \| grep grafana-dashboard` (expect 6) |
| Only one ClearLedger dashboard appears | All ConfigMaps used key `dashboard.json` | Re-run installer — each dashboard now has a unique file key |
| Falco panels empty | No runtime event yet, or Falco logs not in Loki | Run `bash stages/stage-7-observability/scripts/generate-dashboard-data.sh` (Step 2) |
| Kyverno panels empty | No blocked admission yet, or wrong PromQL metric name | Run demo script Step 1; dashboards use `kyverno_admission_requests_total{request_allowed="false"}` (Kyverno 1.12+) |
| Request Rate panel empty | App images lack `/metrics` exporter | Run `bash stages/stage-7-observability/scripts/build-metrics-images.sh` |
| Failed Login panel empty | No login attempts in logs | Demo script Step 3; confirm auth-service logs contain `Failed login attempt` |
| Audit Log dashboard empty | Kubernetes audit logs not shipped to Loki yet | Expected on MicroK8s until audit logging is configured — see [kubernetes-audit-logging.md](kubernetes-audit-logging.md) |
| Alerting rules missing | PrometheusRule not applied | `kubectl apply -f stages/stage-7-observability/infra/monitoring/alerting-rules.yaml` |

### Quick recovery (re-provision everything)

```bash
bash stages/stage-7-observability/scripts/install-observability.sh
bash stages/stage-7-observability/scripts/build-metrics-images.sh   # optional — HTTP metrics
bash stages/stage-7-observability/scripts/generate-dashboard-data.sh
make check-7
```

## Vault Issues

> Full Stage 5 walkthrough: [LAB-GUIDE.md § Stage 5](../docs/LAB-GUIDE.md#stage-5--secrets-management-vault)

### Stage 5 — common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `auth-service-secret` not found when building `.env` | Secret deleted too early | Use §5.1 fallback (postgres-secret) or read from Vault KV |
| `helm install` “cannot re-use a name” | Vault already installed | `helm upgrade --install vault ...` (see LAB-GUIDE §5.2) |
| `kubectl delete secret` → `NotFound` | Secrets already deleted | OK — continue to §5.6 |
| Auth pods stuck `1/1` | Injector off or no Vault annotations | `injector.enabled=true`; check deployment annotations |
| Auth pods `FailedCreate` duplicate `vault-secrets` | Manual volume + injector volume | Remove `vault-secrets` from deployment.yaml |
| Kyverno denies new auth pods | Missing container `runAsNonRoot` | Add on app container; Vault agent excluded by name |
| Login fails after migration | `SEED_*` mismatch with Postgres | Re-run `seed-vault-secrets.sh` with correct `.env` |
| ArgoCD OutOfSync on deleted secrets | Infra repo still has `secret.yaml` | Remove from `clearledger-infra` and push |
| ArgoCD sync fails on `vault-secret-rotation` | Kyverno blocks the CronJob | Copy hardened `rotation-cronjob.yaml` from this repo — [details](#argocd-sync-failed-on-vault-secret-rotation-stage-5) |

### Vault agent not injecting secrets

```bash
# Check init container logs (runs at pod startup before the main container)
kubectl logs POD_NAME -n clearledger -c vault-agent-init

# Common errors:
# "permission denied" → service account not bound to a Vault role
# "connection refused" → Vault is not running or not reachable

# Verify the Vault role is configured correctly
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/auth-service

# Verify the service account exists (created with infra/manifests/rbac/rbac.yaml)
kubectl get serviceaccount auth-service -n clearledger
```

### Vault pod not starting

```bash
kubectl logs vault-0 -n vault
kubectl describe pod vault-0 -n vault

# In dev mode, Vault should start immediately
# If sealed, unseal manually:
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-0 -- vault operator unseal
```

### Secrets not appearing in /vault/secrets

```bash
# Verify Vault has the secret at the expected path (use VAULT_TOKEN from .env — not from Git)
kubectl exec -n vault vault-0 -- vault login "$VAULT_TOKEN"
kubectl exec -n vault vault-0 -- vault kv metadata get clearledger/auth-service

# Verify the annotation path matches the actual Vault path
# deployment.yaml annotation:
#   vault.hashicorp.com/agent-inject-secret-database_url: "clearledger/data/auth-service"
# This must match the kv-v2 path format: clearledger/data/<path>
```

---

## AWS / EKS (Stage 8)

<a id="irsa-not-working-runbook"></a>

### IRSA not working — pod using node role instead of service role

Symptom: `aws sts get-caller-identity` (from `kubectl run ... --image=amazon/aws-cli`
with your workload ServiceAccount) shows the **EC2 instance profile** ARN for the
node, not `assumed-role/<your-irsa-role>/...`.

**1. Verify the ServiceAccount has the correct IRSA annotation**

```bash
kubectl get sa auth-service -n clearledger -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
```

**Expected:** non-empty ARN matching `terraform output -raw auth_service_irsa_role_arn`.

**If empty:** apply `stages/stage-8-aws-migration/manifests/clearledger-serviceaccounts.yaml`
after substituting ARNs (see file header). If you use GitOps, commit the resolved YAML.

**2. Verify the IAM role trust policy lists the correct OIDC provider ARN**

```bash
aws iam get-role --role-name clearledger-auth-service \
  --query 'Role.AssumeRolePolicyDocument' --output json | jq .
```

**Expected:** `Principal.Federated` equals `arn:aws:iam::<account-id>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<cluster-oidc-id>`.

**If wrong:** re-run `terraform apply` for `stages/stage-8-aws-migration/terraform` — the
provider is created with the EKS cluster.

**3. Verify `StringEquals` on `:sub` matches the exact namespace + ServiceAccount**

In the same trust JSON, find `oidc.eks...:sub` → must be exactly:

`system:serviceaccount:clearledger:auth-service`

**If it says `ledger-service` or another namespace:** Terraform `iam.tf` trust
`values` do not match this SA — fix the role or the Kubernetes SA name.

**4. Confirm the OIDC provider exists in IAM**

```bash
aws iam list-open-id-connect-providers --output text
```

**Expected:** an ARN containing your EKS cluster OIDC issuer ID.

**If missing:** EKS control plane was not wired for IRSA — `terraform apply` must
complete successfully (see `aws_iam_openid_connect_provider.eks` in Terraform).

**5. Confirm the Pod uses the annotated ServiceAccount (not `default`)**

```bash
kubectl get pod -n clearledger -l app=auth-service \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.serviceAccountName}{"\n"}{end}'
```

**Expected:** second column is `auth-service`.

**If `default`:** patch the Deployment `serviceAccountName` and restart.

---

## Stage 8 — GitHub Actions OIDC / ECR publish fails

### `Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Symptom:** CI — AWS workflow fails at **Publish images → ECR** on `aws-actions/configure-aws-credentials@v4`.

**Cause:** The IAM role `clearledger-github-actions-ecr` trust policy `:sub` claim does not match your repo. Common when `terraform apply` ran before `github_owner` was set in `terraform.tfvars` — AWS still has `repo:YOUR_GITHUB_USERNAME/clearledger:environment:production`.

**Fix:**

```bash
# 1. Set github_owner in terraform.tfvars (copy from terraform.tfvars.example)
grep github_owner stages/stage-8-aws-migration/terraform/terraform.tfvars

# 2. Re-apply
terraform -chdir=stages/stage-8-aws-migration/terraform apply

# 3. Verify (must show YOUR username, not YOUR_GITHUB_USERNAME)
aws iam get-role --role-name clearledger-github-actions-ecr \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals."token.actions.githubusercontent.com:sub"' \
  --output text
```

**Expected:** `repo:YOUR_GITHUB_USERNAME/clearledger:environment:production`

**Re-run CI:** GitHub → Actions → failed run → **Re-run failed jobs** (not “Re-run all jobs” unless you need a full rebuild).

**`ecr:InitiateLayerUpload` denied on `clearledger/frontend`:** Stage 8 Terraform creates only three ECR repos. `ci-aws.yaml` must not push `frontend` — update from the repo if your workflow still references it.

Also confirm:

- GitHub **production** environment exists
- Environment secret **`AWS_ACTIONS_ROLE_ARN`** (not `GITHUB_ACTIONS_ROLE_ARN`) = `terraform output github_actions_ecr_role_arn`
- `publish-images` job has `environment: production` in `ci-aws.yaml`

---

## ArgoCD Issues

### ComparisonError: `authentication required` / `Repository not found`

**Symptom:** Argo CD UI → **Application conditions** shows:

```text
ComparisonError: Failed to load target state: ... failed to list refs:
authentication required: Repository not found
```

**This is not fixed by editing YAML in `clearledger` or pushing to `clearledger-infra`.** Argo CD cannot *read* the infra repo at all.

**Cause:** Usually one of two things:

1. **`clearledger-infra` is private** (or the PAT expired/was revoked), and Argo CD has no valid credentials. GitHub returns "Repository not found" for unauthenticated access to private repos — even when the repo exists.

2. **The Application still points at the lab placeholder** `YOUR_GITHUB_USERNAME/clearledger-infra` instead of your real GitHub username. `argocd repo list` can show **Successful** for the correct URL while the Application uses a different URL:

```bash
argocd app get clearledger --grpc-web | grep -i repo
# Bad:  YOUR_GITHUB_USERNAME/clearledger-infra
# Good: Osomudeya/clearledger-infra  (your username)

# Fix: edit repoURL in stages/stage-2-gitops/argocd/clearledger-app.yaml, then:
kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
argocd app sync clearledger --grpc-web
```

**Fix (credentials):**

```bash
# 1. Confirm the repo exists in your browser
#    https://github.com/YOUR_USERNAME/clearledger-infra

# 2. Log in to Argo CD CLI
argocd login argocd.local --username admin --password YOUR_PASSWORD --insecure --grpc-web

# 3. Re-register credentials (same PAT as INFRA_REPO_TOKEN from Stage 1 §1.4)
export INFRA_REPO_TOKEN='ghp_...'
argocd repo add https://github.com/YOUR_USERNAME/clearledger-infra.git \
  --username git --password "$INFRA_REPO_TOKEN" --grpc-web

# 4. Verify connection
argocd repo list --grpc-web
# REPO STATUS must be Successful for clearledger-infra

# 5. Hard-refresh the app
argocd app get clearledger --hard-refresh --grpc-web
argocd app sync clearledger --grpc-web
```

**Prevention for new learners:** create `clearledger-infra` as **Public** in §1.3, or register the PAT in Stage 2 before expecting a green sync. Credentials live in the cluster — after `make restore` or reinstalling Argo CD, run `argocd repo add` again.

**What repo to edit for what:**

| Problem | Which repo / action |
|---|---|
| Argo CD cannot clone infra repo (this error) | Re-run `argocd repo add` — no Git push fixes it |
| Deployment image tags / manifests wrong | `clearledger-infra` — let CI update it, or `make push-infra-manifests` |
| Kyverno policies (Stage 4) | `clearledger` → `kubectl apply -f infra/policies/` (never the infra repo) |
| App repo is private | **OK** — ArgoCD does not read `clearledger`; only CI/runner needs access |

### CLI warning: "Failed to invoke grpc call. Use flag --grpc-web"

When the ArgoCD CLI talks to the server through the nginx Ingress (`argocd.local`),
native gRPC often fails; the CLI falls back and login may still succeed, but you will
see a warning.

**Fix:** pass `--grpc-web` on login and other CLI commands:

```bash
argocd login argocd.local --username admin --password YOUR_PASSWORD --insecure --grpc-web
```

<a id="argocd-sync-failed-on-vault-secret-rotation-stage-5"></a>

### ArgoCD sync failed on `vault-secret-rotation` (Stage 5)

After you push Stage 5 manifests, Argo CD may stay **OutOfSync** on `CronJob/vault-secret-rotation`. Kyverno from Stage 4 requires every pod — including CronJobs — to have hardened `securityContext` and resource limits. The rotation CronJob in `clearledger-infra` needs the version from this repo: `infra/manifests/vault/rotation-cronjob.yaml`.

Copy that file into your infra repo, commit, push, then sync:

```bash
argocd app sync clearledger --grpc-web --prune
```

If sync says **another operation is already in progress**, Argo CD is already retrying. Wait a minute and check again. If it stays stuck:

```bash
argocd app terminate-op clearledger --grpc-web
argocd app sync clearledger --grpc-web --prune
```

OutOfSync on deleted app secrets *before* you run `kubectl delete secret` in §5.5 is normal. After deletion, only `postgres-secret` should remain.

### Application stuck in OutOfSync (CI updated infra hours ago)

**Symptom:** `clearledger-infra` has new `image: docker.io/.../clearledger-auth-service:<sha>` from CI, but ArgoCD shows **OutOfSync** for hours.

**Common causes:**

1. **Pre-Kustomize drift** — old CI used `sed` on `image:` only; probes/limits in `clearledger-infra` fell behind `infra/manifests/`. Current CI copies the full tree + Kustomize tags — drift should not recur.
2. **Rollout never became Healthy** — sync ran but pods crash (probes, OOM, ImagePullBackOff, Vault init).
3. **ArgoCD poll delay** — default ~3 min; CI annotates `refresh=hard` and re-applies the Application after manifest push.

**Prod fix (GitOps-native):**

```bash
make fix-argocd
```

Syncs canonical `infra/manifests/` (Kustomize SHAs preserved) to `clearledger-infra`, re-applies the Application, triggers sync — **without** `kubectl apply` on deployments.

**Manual fallback:**

```bash
argocd app sync clearledger --force --grpc-web
argocd app get clearledger --grpc-web
kubectl get events -n clearledger --sort-by='.lastTimestamp'
argocd repo list
```

### Drift demo: kubectl set image does nothing / ArgoCD stays Synced

**Symptom:** You change a deployment image with `kubectl set image`, but ArgoCD UI stays **Synced** and the image is not reverted after a few minutes.

**Cause:** ArgoCD is only watching top-level manifests (`namespace.yaml`, `ingress.yaml`), not files under `manifests/auth-service/`, etc. Without `manifests/kustomization.yaml` listing all resources, deployments you applied in Stage 0 are invisible to ArgoCD.

**Fix:**

```bash
# Application spec must include:
#   directory:
#     recurse: true
kubectl apply -f stages/stage-2-gitops/argocd/clearledger-app.yaml
argocd app sync clearledger --grpc-web
argocd app resources clearledger --grpc-web | grep Deployment
```

**Expected:** `auth-service`, `ledger-service`, and other Deployments appear in the list. Then re-run the drift demo.

**Note:** Git (`clearledger-infra`) should not change during the demo — only the live cluster drifts, then ArgoCD corrects it.

### ArgoCD Synced but red pods / Health "Progressing" (Stage 2)

**Symptom:** After the first full sync, `auth-service` / `ledger-service` show red in the ArgoCD tree, new pods are `0/1`, app health is **Progressing** while sync is **Synced**.

**Common causes:**

| Cause | Fix |
|---|---|
| `manifests/netpol/` still in `clearledger-infra` | Delete folder on GitHub, sync ArgoCD, restart auth/ledger (see LAB-GUIDE §2) |
| Vault deployments synced before Stage 5 | Re-push `secretKeyRef` manifests from this repo (`make push-infra-manifests`) |
| CI deleted app secrets from `clearledger-infra` | Ensure `auth-service/secret.yaml` and `ledger-service/secret.yaml` are in infra repo and listed in `kustomization.yaml`; re-push and sync |
| Wrong Docker Hub user in `kustomization.yaml` | `sed` `YOUR_DOCKERHUB_USERNAME` → your user before Stage 1.3 push |

See [LAB-GUIDE.md — Stage 2 red pods section](../docs/LAB-GUIDE.md#if-the-ui-shows-red-pods-or-progressing-read-this-before-the-screenshot).

### selfHeal reverting your manual changes

This is working as designed. To make a legitimate change:
1. Edit the manifest in the infra Git repo
2. Commit and push
3. ArgoCD syncs automatically

To temporarily pause selfHeal for incident response:
```bash
argocd app set clearledger --self-heal=false
# Make your emergency changes
# Then re-enable:
argocd app set clearledger --self-heal=true
```

---

## Falco Issues

### Falco not detecting events

```bash
kubectl logs -n falco daemonset/falco | grep -i error

# Check if the eBPF driver is loaded
kubectl exec -n falco \
  $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- falco --version

# Verify custom rules are loaded
kubectl exec -n falco \
  $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- cat /etc/falco/clearledger_rules.yaml
```

### Falco UI showing no alerts

```bash
# Verify Falcosidekick is running
kubectl get pods -n falco | grep sidekick

# Check Falcosidekick logs
kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick

# Manually trigger a test alert
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- /bin/sh
# This should appear in the Falco UI within seconds
```

---

## Networking Issues

### Services not reachable via domain name

**Mac or Linux with Multipass**

```bash
cat /etc/hosts | grep clearledger
sudo bash scripts/setup-hosts.sh
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/auth/health
```

If the VM IP changed after a restart, remove old lines and run the script again:

```bash
sudo sed -i.bak '/\.local/d' /etc/hosts
rm -f /etc/hosts.bak
sudo bash scripts/setup-hosts.sh
```

**WSL2**

Do **not** use `multipass info`. Follow the three steps in [Domain Names — WSL2](LAB-GUIDE.md#wsl2-microk8s-runs-inside-wsl) in the lab guide.

### Network policies blocking legitimate traffic

```bash
# Temporarily remove the default-deny policy to test
kubectl delete networkpolicy default-deny-all -n clearledger

# Test connectivity
curl -s http://clearledger.local/auth/health

# Re-apply when done testing
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
```

---

## General Debugging Workflow

When something is broken:

1. **Check pod status:** `kubectl get pods -n clearledger`
2. **Check events:** `kubectl get events -n clearledger --sort-by='.lastTimestamp'`
3. **Check logs:** `kubectl logs POD_NAME -n clearledger`
4. **Check description:** `kubectl describe pod POD_NAME -n clearledger`
5. **Check the stage README** — the current stage's README describes exactly what should be running
