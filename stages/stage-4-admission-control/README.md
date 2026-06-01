# Stage 4 — Admission Control (Kyverno)

> **The problem you felt in Stage 3:** The pipeline gates everything that goes
> through CI. But a developer with kubectl access can apply any manifest they
> want — bypassing all your pipeline gates entirely. Root container? Applied.
> No resource limits? Applied. Unsigned image? Applied.
>
> **What changes here:** Kyverno sits between the Kubernetes API server and
> every resource creation. It enforces policies at admission time. Nothing that
> violates policy runs — regardless of who applied it or how.

---

## What You Will Learn

- How Kubernetes admission webhooks work mechanically
- Enforce vs Audit mode and when to use each
- How to write Kyverno policies for fintech security requirements
- How to create a policy exception without weakening the policy
- How to read PolicyReports to understand your cluster's compliance posture

---

## What You Are Installing

| Tool | Version | Purpose |
|---|---|---|
| Kyverno | 1.12.x | Admission controller + policy engine |

## Policies You Are Applying

| Policy | Severity | Framework |
|---|---|---|
| Disallow root containers | HIGH | CIS K8s 5.2.6 / PCI-DSS 6.5 |
| Require resource limits | MEDIUM | CIS K8s 5.2.4 |
| Require signed images | CRITICAL | SLSA Level 2 |
| Disallow privilege escalation | HIGH | CIS K8s 5.2.5 |
| Drop all capabilities | HIGH | CIS K8s 5.2.7 |

---

## Prerequisites

- Stage 3 complete — images are signed with Cosign, public key available

---

## Steps

### 1. Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm upgrade --install kyverno kyverno/kyverno \
  --version 3.2.8 \
  --namespace kyverno \
  --create-namespace \
  -f stages/stage-4-admission-control/infra/kyverno/values.yaml \
  --wait --timeout=600s

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=admission-controller \
  -n kyverno --timeout=120s
```

### 2. Add Your Cosign Public Key

```bash
# Edit the require-signed-images policy and replace the placeholder
# with your actual cosign.pub content from Stage 3:
cat cosign.pub
# Paste the output into infra/policies/require-signed-images.yaml
```

### 3. Apply the five core policies

Apply the five policies that map to CIS Kubernetes Benchmark controls. Skip `verify-slsa-provenance.yaml` for now — it is an optional SLSA attestation policy (Audit mode) you can enable after the core policies are working.

```bash
kubectl apply \
  -f infra/policies/disallow-root.yaml \
  -f infra/policies/disallow-privilege-escalation.yaml \
  -f infra/policies/drop-all-capabilities.yaml \
  -f infra/policies/require-resource-limits.yaml \
  -f infra/policies/require-signed-images.yaml

kubectl get clusterpolicy
# NAME                            ADMISSION   BACKGROUND   VALIDATE ACTION   READY   AGE
# disallow-privilege-escalation   true        true         Enforce           True    10s
# disallow-root-containers        true        true         Enforce           True    10s
# drop-all-capabilities           true        true         Enforce           True    10s
# require-resource-limits         true        true         Enforce           True    10s
# require-signed-images           true        false        Enforce           True    10s
```

---

## Break It On Purpose

### Scenario 1 — Root Container

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: root-test
  namespace: clearledger
spec:
  containers:
    - name: root-test
      image: nginx:alpine
EOF

# Expected output (multiple policies fire on a bare nginx pod):
# Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
# resource Pod/clearledger/root-test was blocked due to the following policies
# disallow-root-containers:
#   check-runAsNonRoot: validation error: Root containers are blocked...
```

### Scenario 2 — Missing Resource Limits

```bash
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

# Expected output:
# Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
# resource Pod/clearledger/nolimits-test was blocked due to the following policies
# require-resource-limits:
#   check-resources: 'validation error: Resource requests and limits are required for
#     all containers. rule check-resources failed at path /spec/containers/0/resources/limits/'
```

### Scenario 3 — Unsigned Image

**Prerequisite:** push an unsigned test image that exists on Docker Hub (see LAB-GUIDE §4.4 Scenario 3 Step 1).

```bash
export DOCKER_USERNAME=your-dockerhub-username

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

# Expected output:
# Error from server: admission webhook "mutate.kyverno.svc-fail" denied the request:
# resource Pod/clearledger/unsigned-test was blocked due to the following policies
# require-signed-images:
#   verify-cosign-signature: 'failed to verify image index.docker.io/.../clearledger-auth-service:unsigned-test:
#     .attestors[0].entries[0].keys: no signatures found'
```

Use `index.docker.io/` — not `docker.io/` — so Kyverno's `verifyImages` rule matches reliably.

Save these error messages. They are evidence that the control is working.

---

## View Policy Reports

```bash
# See all violations across the cluster
kubectl get policyreport -A

# Detailed view for your namespace
kubectl describe policyreport -n clearledger
```

---

## Writing a Policy Exception (Without Weakening the Policy)

If a legitimate workload needs an exemption from a specific rule:

```yaml
# infra/policies/exceptions/postgres-root-exception.yaml
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: postgres-root-exception
  namespace: clearledger
spec:
  exceptions:
    - policyName: disallow-root-containers
      ruleNames: [check-runAsNonRoot]
  match:
    any:
      - resources:
          kinds: [Pod]
          namespaces: [clearledger]
          names: [postgres-*]
```

This exception is:
- Scoped to exactly the resource that needs it (postgres pods only)
- Committed to Git — reviewed, tracked, auditable
- Not a policy weakening — the policy still enforces on everything else

A ready-to-use example lives at `infra/policies/exceptions/postgres-root-exception.yaml`.

---

## Verify ClearLedger Still Works

```bash
curl -s http://clearledger.local/auth/health | jq .
# {"status": "ok", "service": "auth-service"}

TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "test@clearledger.io", "password": "SecurePass123"}' \
  | jq -r .access_token)

curl -s http://clearledger.local/ledger/balance \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

## 4.8 — Prove Your Cluster Passes CIS Benchmark

Kyverno enforces *what workloads* are allowed to run in your cluster.
**kube-bench** audits *how the cluster itself is configured* against the CIS
Kubernetes Benchmark. These are two different layers. **Both are required**
for CIS-aligned compliance evidence.

### Run kube-bench

This stage includes a Job manifest and a bash-only parser:

- **Job**: `infra/kube-bench/kube-bench-job.yaml`
- **Runner**: `scripts/run-kube-bench.sh`
- **Baseline**: `scripts/kube-bench-baseline.json` (committed to git; diffs become evidence)

Workflow:

```bash
# 1) Apply the Job + wait + save JSON report + print summary
bash stages/stage-4-admission-control/scripts/run-kube-bench.sh

# 2) Review the output; then pin your baseline by recording expected control statuses
#    in stages/stage-4-admission-control/scripts/kube-bench-baseline.json
```

Expected output shape for a clean install:

- PASS controls: core hardening checks already satisfied
- WARN controls: acceptable with justification (lab constraints), but should be tracked
- FAIL controls: configuration gaps you must fix (or explicitly accept as baseline for the lab)

### Common MicroK8s findings and how to fix them

MicroK8s stores Kubernetes component flags under:
`/var/snap/microk8s/current/args/` (not `/etc/kubernetes/` like kubeadm / EKS).

Common failures you may see on a default MicroK8s install:

- **1.2.1 Ensure anonymous auth is not enabled (API server flag)**
  - **Why it matters**: anonymous requests can access endpoints if RBAC is misconfigured.
  - **Fix**:

```bash
microk8s stop
# edit: /var/snap/microk8s/current/args/kube-apiserver
# ensure: --anonymous-auth=false
microk8s start
```

- **1.2.6 Ensure AlwaysPullImages admission plugin is set**
  - **Why it matters**: prevents nodes from using a stale or tampered cached image tag.
  - **Fix**:

```bash
microk8s stop
# edit: /var/snap/microk8s/current/args/kube-apiserver
# add to --enable-admission-plugins=... list: AlwaysPullImages
microk8s start
```

- **4.2.1 Ensure kubelet anonymous auth is disabled**
  - **Why it matters**: kubelet APIs can leak node/pod details and become lateral-movement primitives.
  - **Fix**:

```bash
microk8s stop
# edit: /var/snap/microk8s/current/args/kubelet
# ensure: --anonymous-auth=false
microk8s start
```

Re-run `run-kube-bench.sh` after each change and commit baseline updates. That’s compliance evidence.

---

## What the Cluster Looks Like Now

```
git push
  │
[Gitleaks → Semgrep → Checkov → Trivy → Cosign] ← security gates
  │ all pass
  ▼
[ArgoCD] syncs cluster
  │
  ▼
[Kyverno] admission control ← NEW
  │ policy checks at pod creation time
  ▼
Pod starts (compliant or rejected)
  │
Secrets still in env vars from K8s Secrets ← next problem
```

---

## What Is Still Broken

Look at `infra/manifests/auth-service/secret.yaml`. The database password is
there. In plaintext. Committed to Git. Stored in etcd. Readable by anyone
with `kubectl get secret` access. Kyverno cannot fix this — it enforces
pod specs, not secret storage.

**Stage 5 fixes this with Vault.**

---

---

## Before You Move On

Run the health check to confirm this stage is working:

```bash
bash scripts/health-check.sh 4
```

Green output = ready for the next stage.
Red output = something needs fixing. The message tells you what.

## → Next: [Stage 5 — Secrets Management](../stage-5-secrets-management/README.md)
