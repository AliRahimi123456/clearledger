# Stage 8 — AWS Migration

> **The question you're asking:** Does this all work in the cloud?
>
> **The answer:** Yes. Swap the endpoints. Everything else is identical.
> ArgoCD, Kyverno, Falco, Prometheus, Vault — all run on EKS exactly as they
> ran on MicroK8s. The architecture survives the migration because you built it
> to be portable.

---

## What You Will Learn

- How to provision an EKS cluster with `eksctl`
- What changes between MicroK8s and EKS (less than you expect)
- How to migrate images to Amazon ECR
- How to replace the local registry and nginx ingress with AWS-native services
- How to migrate secrets from self-hosted Vault to AWS Secrets Manager
- How **IRSA** binds a Kubernetes ServiceAccount to an IAM role (trust chain, JWT claims, CloudTrail)

---

## What Changes vs What Stays the Same

### Stays the Same (Zero Relearning)

| Component | Why It's Identical |
|---|---|
| ArgoCD | Install same Helm chart, point at same Git repo |
| Kyverno | Same ClusterPolicies — no changes |
| Falco | Same Helm chart, same custom rules |
| Prometheus + Grafana | Same Helm chart, same dashboards |
| Application code | Zero changes |
| Kubernetes manifests | Minor annotation changes only |

### What Changes

| Local | AWS | Required Change |
|---|---|---|
| Docker Hub + stored secrets | Amazon ECR + OIDC (no stored AWS keys) | Switch to `.github/workflows/ci-aws.yaml` |
| Self-hosted Vault | AWS Secrets Manager or Vault on EKS | Update secret source |
| MicroK8s nginx ingress | AWS ALB Ingress Controller | Change ingress annotations |
| `/etc/hosts` domains | Route53 + ACM | Update DNS and TLS |
| `clearledger-infra` on GitHub | No change needed — already on GitHub | ArgoCD repo URL stays the same |

---

## Local CI vs AWS CI

There are two workflows on purpose:

| Workflow | Trigger | Registry | Use it for |
|---|---|---|---|
| `.github/workflows/ci.yaml` | Automatic on push to `main` | Docker Hub | Stages 1–7 local MicroK8s lab |
| `.github/workflows/ci-aws.yaml` | Manual only: Actions → CI — AWS (ECR + OIDC) → Run workflow | Amazon ECR | Stage 8 AWS migration |

`ci-aws.yaml` is manual so AWS/ECR work does not run while you are testing the local lab. This avoids surprise cloud changes and surprise cost.

---

## Production Hardening Checklist

The Stage 8 design is production-style: no SSH deploys, no static AWS keys for CI, GitOps deploys through ArgoCD, and pods use IRSA. Before calling it production-ready, add these guardrails:

| Control | What to configure | Why |
|---|---|---|
| Branch protection | Protect `main` in `clearledger` and `clearledger-infra`; require PRs, approvals, and passing checks | Prevent direct pushes to code or deployment state |
| GitHub Environments | Create `production`; require reviewers; restrict deployment branches to `main` | Adds an approval gate before production AWS actions |
| Fine-grained token / GitHub App | Replace broad classic PAT with a fine-grained token limited to `clearledger-infra` with Contents read/write, or use a GitHub App | Reduces blast radius if `INFRA_REPO_TOKEN` leaks |
| OIDC environment lock | `.github/workflows/ci-aws.yaml` uses `environment: production`; Terraform trusts `repo:Osomudeya/clearledger:environment:production` | AWS only issues credentials to approved production jobs |
| Staging to prod promotion | Build once, deploy to staging, test, then promote the same image SHA/digest to prod | Prevents untested direct production deployment |
| Private networking | Private EKS nodes, private RDS, restricted EKS endpoint, least-privilege security groups | Reduces public attack surface |
| Terraform remote state | Encrypted S3 backend + DynamoDB locking + bucket versioning + public access blocked | Protects and coordinates infrastructure state |

Production summary:

```text
CI builds and proves the artifact.
GitHub Environments approve production.
OIDC gives short-lived AWS credentials.
ECR stores immutable images.
clearledger-infra records desired state.
ArgoCD deploys from Git.
No SSH. No static AWS keys. No direct kubectl from CI.
```

---

## Understanding IRSA (Read This Before Anything Else)

**IRSA** (IAM Roles for Service Accounts) is how a **pod** in EKS obtains AWS API
permissions **without** static `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in
EnvVars or ConfigMaps. It is the AWS analogue of **Vault Kubernetes auth**: the
cluster proves *which workload* is calling, and AWS issues **short-lived** STS
credentials scoped to a **single IAM role**.

### Full trust chain (read once, then teach it)

```text
Pod uses a ServiceAccount annotated with eks.amazonaws.com/role-arn
  → kubelet mounts a projected ServiceAccount token (JWT, OIDC shape)
  → AWS SDK / aws-cli calls STS AssumeRoleWithWebIdentity with that JWT
  → EKS OIDC IdP validates signature + issuer + audience (aud)
  → STS returns temporary credentials (typical TTL 15 min–1 hr; configurable)
  → The pod calls AWS APIs as the IAM role — no long-lived keys stored in etcd
```

### Why this matters for fintech

- **No static AWS keys** in Git, Secrets Manager sync objects, or pod env — rotation is continuous by design.
- **Blast radius is time-bounded**: if a pod is compromised, stolen creds expire at STS TTL.
- **Per-workload isolation**: auth-service and ledger-service can assume **different** roles with **different** Secrets Manager ARNs — not one shared node role.
- **Audit**: CloudTrail records `AssumeRoleWithWebIdentity` with the **session context** that ties back to the Kubernetes `sub` claim — you can answer “which SA in which namespace assumed this role?”.

Terraform in `stages/stage-8-aws-migration/terraform/` registers the cluster OIDC
provider and creates the IAM roles. The manifests in
`stages/stage-8-aws-migration/manifests/clearledger-serviceaccounts.yaml` (after
you substitute ARNs from `terraform output`) attach those roles to the Kubernetes
ServiceAccounts.

---

## Prove IRSA Is Working (Step by Step)

Run these **after** `terraform apply` and `kubectl apply` for the workloads. Use
`aws eks update-kubeconfig` so `kubectl` targets the ClearLedger EKS cluster.

### Step 1 — Inspect the projected token (JWT)

Use a **bound** ServiceAccount token (Kubernetes 1.24+). This is the same style
of JWT the AWS SDK exchanges for STS credentials (claims differ slightly from
the legacy volume token, but `iss` / `sub` / `aud` behave the same for IRSA):

```bash
kubectl create token auth-service -n clearledger --duration=15m > /tmp/irsa.jwt
```

> If your cluster rejects `kubectl create token`, exec into any pod that mounts
> the SA token at `/var/run/secrets/kubernetes.io/serviceaccount/token` instead.
> On EKS with IRSA, set `automountServiceAccountToken: true` on the workload (or
> use a debug pod) so a token exists for the SDK.

Decode the **middle** segment (payload) with Python (no extra tools required):

```bash
python3 - <<'PY'
import json, base64, sys
raw = open("/tmp/irsa.jwt").read().strip().split(".")[1]
raw += "=" * (-len(raw) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(raw)), indent=2))
PY
```

What to look for in the payload:

| Field | Meaning |
|-------|---------|
| `iss` | Issuer URL — must match your EKS OIDC provider (`https://oidc.eks.<region>.amazonaws.com/id/<id>`). |
| `sub` | **Binding** — must be exactly `system:serviceaccount:clearledger:auth-service` for the auth role. |
| `aud` | Audience — for IRSA this should include `sts.amazonaws.com`. |
| `kubernetes.io` | Namespace, pod name, and SA name metadata (EKS v1.24+ style claims). |

### Step 2 — Read the IAM trust policy Terraform wrote

In the AWS console: **IAM → Roles →** `clearledger-auth-service` (name prefix follows `project_name`) **→ Trust relationships**.

You should see:

- **Effect**: `Allow`
- **Principal**: Federated — your cluster OIDC provider ARN (`arn:aws:iam::<account>:oidc-provider/oidc.eks...`)
- **Action**: `sts:AssumeRoleWithWebIdentity`
- **Condition**:
  - `StringEquals` on `oidc.eks...:aud` = `sts.amazonaws.com` — only STS web identity clients.
  - `StringEquals` on `oidc.eks...:sub` = `system:serviceaccount:clearledger:auth-service` — **exact** SA binding (**StringLike is avoided** so nobody can widen the match with `*`).

Or from the CLI (replace role name if you changed `project_name`):

```bash
aws iam get-role --role-name clearledger-auth-service \
  --query 'Role.AssumeRolePolicyDocument' --output json | jq .
```

### Step 3 — Misconfigure IRSA on purpose (then revert)

1. **Temporarily** annotate the `auth-service` ServiceAccount with the **ledger**
   role ARN (wrong trust `sub` — Terraform bound ledger to
   `system:serviceaccount:clearledger:ledger-service`):

```bash
# Save the correct annotation first
kubectl get sa auth-service -n clearledger -o yaml | grep role-arn

kubectl annotate sa auth-service -n clearledger \
  eks.amazonaws.com/role-arn="$(terraform output -raw ledger_service_irsa_role_arn)" \
  --overwrite
kubectl rollout restart deployment/auth-service -n clearledger
```

2. Run **Amazon Linux AWS CLI** as the `auth-service` SA (app images usually lack
   `aws`). The wrong role trust rejects `AssumeRoleWithWebIdentity` or the role
   policy denies the API — either way you should **not** see a successful read:

```bash
kubectl run irsa-smoke --rm -it --restart=Never \
  --image=amazon/aws-cli:latest \
  --namespace=clearledger \
  --serviceaccount=auth-service \
  --command -- aws secretsmanager get-secret-value \
  --secret-id clearledger/auth-service \
  --region "${AWS_REGION:-eu-west-1}"
# Expect: AccessDenied / not authorized — exact wording varies by SDK version
```

3. **Revert** the annotation to the auth IRSA ARN from `terraform output -raw auth_service_irsa_role_arn`, restart again, and confirm the same `get-secret-value` succeeds **only** if your pod identity policy allows it (the lab role allows **only** the `clearledger/auth-service` secret ARN).

### Step 4 — `aws sts get-caller-identity` as the ServiceAccount

```bash
kubectl run irsa-whoami --rm -it --restart=Never \
  --image=amazon/aws-cli:latest \
  --namespace=clearledger \
  --serviceaccount=auth-service \
  --command -- aws sts get-caller-identity
```

**Healthy IRSA:** `Arn` contains `assumed-role/clearledger-auth-service/...` (or your `project_name` prefix).

**Broken (falling back to node identity):** you would see the **EC2 instance
profile** role for the worker node — if that happens, work through
[IRSA runbook](../../docs/troubleshooting.md#irsa-not-working-runbook) in `docs/troubleshooting.md`.

### Step 5 — CloudTrail: see `AssumeRoleWithWebIdentity`

1. Open **AWS CloudTrail → Event history** in the account where EKS runs.
2. Filter event name: **`AssumeRoleWithWebIdentity`**.
3. Open a recent event — **User name** / `userIdentity` shows the role being
   assumed; **Request parameters** include the web identity token context.

You should see repeated **successful** authentication events when the workload or
sidecars refresh credentials — evidence for SOC2 / operational reviews that
**pod-level** AWS access is logged, not silent node credential reuse.

---

## Prerequisites

- Stage 7.5 complete — OpenTelemetry tracing deployed
- AWS account with appropriate permissions (EKS, ECR, Secrets Manager, IAM)
- AWS CLI configured: `aws configure`
- eksctl installed (see below)
- kubectl already installed from Stage 0

---

## Steps

### 1. Install eksctl

```bash
# macOS:
brew install eksctl

# Linux:
curl --silent --location \
  "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
  | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin/

# Windows: winget install eksctl
```

### 2. Provision EKS

```bash
eksctl create cluster \
  --name clearledger-prod \
  --region eu-west-1 \
  --nodegroup-name standard \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed

# Update your kubeconfig
aws eks update-kubeconfig \
  --name clearledger-prod \
  --region eu-west-1

kubectl get nodes
# Three nodes. Ready.
```

### 3. Install the Same Tools

```bash
# ArgoCD — identical to Stage 2
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Kyverno — identical to Stage 4
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Apply same policies (update image reference prefix first)
kubectl apply -f infra/policies/

# Falco — identical to Stage 6
helm install falco falcosecurity/falco -n falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set falcosidekick.enabled=true

kubectl apply -f infra/falco/clearledger-rules.yaml

# Prometheus + Grafana — identical to Stage 7
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### 4. Create ECR Repositories

```bash
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="eu-west-1"

for service in auth-service ledger-service notification-service; do
  aws ecr create-repository \
    --repository-name clearledger/$service \
    --region $AWS_REGION
done

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS \
    --password-stdin $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com
```

### 5. Push Images to ECR

```bash
for service in auth-service ledger-service notification-service; do
  docker tag DOCKER_USERNAME/clearledger-$service:latest \
    $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/clearledger/$service:latest
  docker push $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/clearledger/$service:latest
done
```

### 6. Update Manifests for ECR

In each deployment.yaml, update the image field:

```yaml
# Before (local):
image: DOCKER_USERNAME/clearledger-auth-service:abc123

# After (AWS):
image: 123456789.dkr.ecr.eu-west-1.amazonaws.com/clearledger/auth-service:abc123
```

Then update the CI pipeline's `REGISTRY` env var:
```yaml
env:
  REGISTRY: 123456789.dkr.ecr.eu-west-1.amazonaws.com
```

Commit to the infra repo. ArgoCD detects the change. Syncs. Done.

### 7. Migrate Secrets to AWS Secrets Manager

```bash
# Store secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name clearledger/auth-service \
  --region $AWS_REGION \
  --secret-string '{
    "database_url": "postgresql://clearledger:prod-pass@rds-endpoint:5432/clearledger",
    "jwt_secret": "your-production-jwt-secret"
  }'

# Install External Secrets Operator (bridges K8s and AWS Secrets Manager)
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

Create a ClusterSecretStore pointing to AWS:

```yaml
# infra/manifests/auth-service/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: auth-service-secret
  namespace: clearledger
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: auth-service-secret
    creationPolicy: Owner
  data:
    - secretKey: database_url
      remoteRef:
        key: clearledger/auth-service
        property: database_url
    - secretKey: jwt_secret
      remoteRef:
        key: clearledger/auth-service
        property: jwt_secret
```

### 8. Switch to ALB Ingress

```bash
# Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=clearledger-prod \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Update ingress annotations:

```yaml
# Before (nginx):
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx

# After (ALB):
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-west-1:ACCOUNT:certificate/YOUR-CERT-ID
spec:
  rules:
    - host: api.clearledger.io  # Route53 record pointing at the ALB
```

---

## Running the Infrastructure

> **This section covers the Terraform-based approach** introduced alongside the
> `eksctl` approach above. Choose one — both produce the same result. Terraform
> is recommended if you want to understand the full IaC picture; eksctl is faster
> if you just want a running cluster.

### Prerequisites Checklist

Tick each item before running the spinup script:

- [ ] AWS account created and billed to your payment method
- [ ] IAM user or role with: `AdministratorAccess` (or EKS/ECR/RDS/IAM/VPC permissions)
- [ ] `aws configure` completed — verify with `aws sts get-caller-identity`
- [ ] Terraform >= 1.6 installed — verify with `terraform -version`
- [ ] kubectl installed — verify with `kubectl version --client`
- [ ] Docker running — verify with `docker info`
- [ ] Helm installed — verify with `helm version`
- [ ] Git installed — verify with `git --version`
- [ ] `stages/stage-8-aws-migration/terraform/secrets.tf` edited — replaced `CHANGE_ME_BEFORE_APPLY` in both secrets

### Spin Up (full stack in one command)

```bash
# Option A — helper script (recommended for first run)
bash stages/stage-8-aws-migration/scripts/aws-spinup.sh
```

```bash
# Option B — manual step-by-step
cd stages/stage-8-aws-migration/terraform

# Edit secrets.tf first — change CHANGE_ME_BEFORE_APPLY in both secret_string blocks
# Generate a strong JWT secret: openssl rand -base64 64

terraform init
terraform apply   # Review the plan, then type 'yes'

# Update kubeconfig
aws eks update-kubeconfig --name clearledger --region eu-west-1

# Apply application manifests
kubectl apply -f infra/manifests/namespace.yaml
kubectl apply -f infra/manifests/ --recursive
kubectl apply -f stages/stage-8-aws-migration/manifests/ingress-aws.yaml

# Get the ALB DNS name (available ~60-90s after ingress is applied)
kubectl get ingress clearledger-ingress -n clearledger
```

### What Terraform Creates

| Resource | Why it exists | Local equivalent |
|---|---|---|
| VPC + public/private/db subnets | Network isolation — nodes, ALB, and RDS in separate tiers | Multipass VM network |
| EKS cluster | Managed Kubernetes control plane | MicroK8s |
| Managed node group (3 × t3.medium) | Worker nodes for all pods | Multipass VM |
| ECR repositories (3) | Container registry — immutable tags, scan on push | Docker Hub |
| RDS PostgreSQL 16 | Managed database with automated backups | In-cluster StatefulSet |
| Secrets Manager (3 secrets: postgres, auth-service, ledger-service) | Credentials consumed by ESO / future app-side reads | HashiCorp Vault |
| ALB + ALB controller (Helm) | Public internet-facing ingress | nginx ingress controller |
| IRSA (ESO, Falco, **auth/ledger/notification** app roles, developer read-only) | Pod-level AWS auth + permission boundary | N/A (cloud-specific) |
| NAT Gateway | Outbound internet for private EKS nodes | VM NAT |
| Internet Gateway | Inbound traffic to ALB in public subnets | VM bridge |
| GuardDuty + CloudTrail + VPC Flow Logs + AWS Config | AWS-native threat detection + audit trail + network forensics + compliance evidence | N/A (cloud-specific) |

## AWS-Native Security Services

Real fintech AWS environments enable GuardDuty, CloudTrail, and VPC Flow Logs on day one.
Without them, the AWS account has no threat detection and no audit trail.

### GuardDuty — Account-Level Threat Detection

What it does that Falco cannot:
Falco sees inside pods. GuardDuty sees the entire AWS account.
GuardDuty uses ML models trained on petabytes of AWS telemetry.

How to verify it's working:

```bash
aws guardduty list-detectors
aws guardduty get-detector --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
```

Generate a test finding:

```bash
aws guardduty create-sample-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \
  --finding-types "UnauthorizedAccess:EC2/SSHBruteForce"
```

View in console: GuardDuty → Findings.
Key fields: finding type, severity, affected resource, remediation.

### CloudTrail — Every AWS API Call

CloudTrail captures every call to every AWS service: who called it, from where, with what parameters.
If credentials are stolen, CloudTrail tells you exactly what the attacker did with them.

How to verify it's working:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2) \
  --max-results 5
```

### VPC Flow Logs — Every Network Connection

VPC Flow Logs capture: source IP, dest IP, port, protocol, bytes, accepted/rejected.
They do not capture packet payloads (that requires a different tool).

How to query them via CloudWatch Insights:

```text
fields @timestamp, srcAddr, dstAddr, dstPort, protocol, action, bytes
| filter action = "REJECT"
| sort @timestamp desc
| limit 20
```

### Security Hub — Single Pane of Glass

Enable Security Hub to aggregate GuardDuty findings:

```bash
aws securityhub enable-security-hub --enable-default-standards
```

Security Hub provides a security score and maps controls to the CIS AWS Foundations Benchmark.

### IRSA lab pointers

The full teaching sequence lives in **Understanding IRSA** and **Prove IRSA Is Working** near the top of this README. Terraform outputs for workload roles:

```bash
cd stages/stage-8-aws-migration/terraform
terraform output -raw auth_service_irsa_role_arn
terraform output -raw ledger_service_irsa_role_arn
terraform output -raw notification_service_irsa_role_arn
terraform output -raw developer_readonly_role_arn
```

Apply annotated ServiceAccounts from `manifests/clearledger-serviceaccounts.yaml` after substituting ARNs (see comments in that file).

### Access ClearLedger in Your Browser

After `aws-spinup.sh` (or `terraform apply` + `kubectl apply`) completes:

```
http://[alb-dns-name]/auth/health          ←  auth-service health check
http://[alb-dns-name]/ledger/health        ←  ledger-service health check
http://[alb-dns-name]/notifications/health ←  notification-service health check
```

The ALB DNS name is printed in green at the end of `aws-spinup.sh`
and is available anytime via:

```bash
# Via kubectl (most reliable after ingress is applied):
kubectl get ingress clearledger-ingress -n clearledger \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Via Terraform output (shows the kubectl command):
cd stages/stage-8-aws-migration/terraform && terraform output alb_dns_name
```

> **Path routing note:** The ALB forwards the full path to the backend without
> stripping the prefix (unlike nginx's `rewrite-target`). The services respond
> at `/health` — access them via the path-prefixed URLs above. Full Swagger UI
> access requires adding a `root_path` to the FastAPI app (Stage 8 extension
> exercise).

### Estimated AWS Cost

| Resource | Hourly | Monthly (730h) | Notes |
|---|---|---|---|
| EKS control plane | $0.10 | ~$73 | Flat rate regardless of node count |
| 3 × t3.medium nodes | $0.042 each | ~$92 | EC2 On-Demand, eu-west-1 |
| NAT Gateway | $0.045 + data | ~$33+ | Data processing adds to this |
| RDS db.t3.micro | $0.018 | ~$13 | Free tier: 750h/month for 12 months |
| ECR storage | $0.10/GB | < $1 | 10-image lifecycle policy limits storage |
| ALB | $0.008/h + LCU | ~$6 | Minimal LCUs for lab traffic |
| Secrets Manager | $0.40/secret | ~$1.20 | 3 secrets (postgres, auth-service, ledger-service) |
| **Total estimate** | **~$0.35–0.45/h** | **~$220** | Destroy when not in use |

> **Cost habit:** Run `bash stages/stage-8-aws-migration/scripts/aws-destroy.sh` at the end of each session.
> The cluster takes ~15 minutes to provision — it is faster to rebuild than to
> leave running overnight. This is the right habit for any lab environment.

### Tear Down

```bash
bash stages/stage-8-aws-migration/scripts/aws-destroy.sh
# Type 'destroy' when prompted
# All resources removed in ~10 minutes. No further charges.
```

---

## What You Just Proved

```
Stage 0 → You know what you are protecting.
Stage 1 → Builds happen automatically.
Stage 2 → Git is truth. The cluster proves it by reverting manual changes.
Stage 3 → Every commit is scanned. A failure stops the pipeline at the right gate.
Stage 4 → The cluster refuses policy violations. You watched the error message.
Stage 5 → No secrets in Git, no secrets in manifests. Vault is the source.
Stage 6 → You exec'd into a pod and Falco caught you. That is the moment.
Stage 6.5 → You killed a pod and the service stayed up. That is resilience.
Stage 7 → You can see your security posture. You can prove it to anyone.
Stage 7.5 → You traced one request across three services in Tempo.
Stage 8 → You swapped endpoints. The architecture survived.
```

The progression — feel the pain, understand the tool, apply it, verify it
breaks correctly — is what separates engineers who configure DevSecOps from
engineers who understand it.

---

## ← Previous: [Stage 7.5 — OpenTelemetry](../stage-7.5-opentelemetry/README.md)

## Next Steps

- See [docs/compliance-mapping.md](../../docs/compliance-mapping.md) for the
  full mapping of every control to PCI-DSS, SOC2, CIS Kubernetes, and NIST 800-53

- See the interview prep guide for questions you will be asked about this project
  and the answers that close offers
