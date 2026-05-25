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

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=1

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=kyverno \
  -n kyverno --timeout=120s
```

### 2. Add Your Cosign Public Key

```bash
# Edit the require-signed-images policy and replace the placeholder
# with your actual cosign.pub content from Stage 3:
cat cosign.pub
# Paste the output into infra/policies/require-signed-images.yaml
```

### 3. Apply All Policies

```bash
kubectl apply -f infra/policies/

kubectl get clusterpolicy
# NAME                          BACKGROUND   VALIDATE ACTION   READY
# disallow-privilege-escalation  true         Enforce           true
# disallow-root-containers        true         Enforce           true
# drop-all-capabilities          true         Enforce           true
# require-resource-limits        true         Enforce           true
# require-signed-images          false        Enforce           true
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

# Expected output:
# Error from server: admission webhook "validate.kyverno.svc" denied the request:
# Root containers are blocked in the clearledger namespace.
# Set securityContext.runAsNonRoot: true
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
# admission webhook denied: Resource requests and limits are required for all containers.
```

### Scenario 3 — Unsigned Image

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: unsigned-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: DOCKER_USERNAME/clearledger-auth-service:untagged
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
# admission webhook denied: image signature verification failed
```

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
