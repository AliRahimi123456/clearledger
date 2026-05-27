# Troubleshooting Reference

Common problems encountered during the lab, with exact diagnostic commands and fixes.

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
| `python-multipart` | `0.0.9` | `0.0.27` | Fixes auth-service HIGH CVEs |

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

## Vault Issues

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
# Verify Vault has the secret at the expected path
kubectl exec -n vault vault-0 -- vault login root-dev-token
kubectl exec -n vault vault-0 -- vault kv get clearledger/auth-service

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

## ArgoCD Issues

### Application stuck in OutOfSync

```bash
argocd app sync clearledger --force
argocd app get clearledger

# Check for resource conflicts
kubectl get events -n clearledger --sort-by='.lastTimestamp'

# Check if the infra repo is reachable
argocd repo list
```

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

```bash
# Verify /etc/hosts entries exist
cat /etc/hosts | grep clearledger

# Verify the VM IP hasn't changed (it can change after restart)
VMIP=$(multipass info clearledger | grep IPv4 | awk '{print $2}')
echo "Current VM IP: $VMIP"

# If the IP changed, re-run setup-hosts.sh after removing old entries
sudo sed -i '' '/clearledger.local/d' /etc/hosts
./scripts/setup-hosts.sh
```

### Network policies blocking legitimate traffic

```bash
# Temporarily remove the default-deny policy to test
kubectl delete networkpolicy default-deny-all -n clearledger

# Test connectivity
curl -s http://clearledger.local/auth/health

# Re-apply when done testing
kubectl apply -f infra/manifests/netpol/network-policies.yaml
```

---

## General Debugging Workflow

When something is broken:

1. **Check pod status:** `kubectl get pods -n clearledger`
2. **Check events:** `kubectl get events -n clearledger --sort-by='.lastTimestamp'`
3. **Check logs:** `kubectl logs POD_NAME -n clearledger`
4. **Check description:** `kubectl describe pod POD_NAME -n clearledger`
5. **Check the stage README** — the current stage's README describes exactly what should be running
