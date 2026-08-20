# Stage 8 — AWS Migration

**Status: ✅ Complete.** ClearLedger runs on real AWS infrastructure (EKS, RDS, Secrets Manager,
ECR, ALB) instead of the WSL2/MicroK8s homelab. Same application code, same GitOps workflow via
ArgoCD, same security policies (Kyverno, Falco) — only the underlying cloud services changed,
exactly as the book frames it: "Stage 8 changes where it runs."

This was the longest and most debugging-heavy stage in the whole lab. The book's own script
(`aws-spinup.sh`) and manual walkthrough (§8.3) got me most of the way, but I hit **eight
separate real bugs/gaps** along the way — none of them fixed by just re-reading the book, all
root-caused with real evidence (logs, `kubectl describe`, AWS CLI output) before fixing.

## What I did, in order

### 1. AWS account setup (before touching Terraform)

- Created a new AWS account, `clearledger-lab` (ID `856986449724`), on the **Free plan** ($100
  credit, 185-day window).
- Set up a **Zero-Spend AWS Budget** first, before any infrastructure — alerts on any spend
  above $0.01, emailed to the account owner. This was the safety net for the rest of the stage.
- Installed AWS CLI v2 and Terraform in WSL2 — neither was pre-installed. AWS CLI via the
  official zip installer (not `apt`'s ancient v1.18, not `snap`). Terraform via the official
  binary download, **not** HashiCorp's apt repo — that repo has fully dropped Ubuntu 20.04
  "focal" support (`apt-cache policy terraform` returns nothing; the repo's own `Packages` file
  has zero entries for focal).
- Created a dedicated IAM user, `terraform-admin` (AdministratorAccess, CLI-only, no console
  login) — never used root account credentials for Terraform.
- Real mistake, self-corrected: first `aws configure` attempt pasted the same Secret Access Key
  into both the Access Key ID and Secret Access Key prompts. Caught via matching key suffixes in
  `aws configure list`, confirmed via an `IncompleteSignature` error, fixed by re-entering
  carefully from the downloaded credentials CSV.

### 2. Terraform — the AWS foundation

- Filled in `secrets.tf`'s 4 `CHANGE_ME_BEFORE_APPLY` placeholders (Postgres password via
  `openssl rand -hex 24`, JWT secret via `openssl rand -base64 64`) using `sed` — generated and
  substituted entirely via shell, never typed or pasted into chat.
- Set `github_owner` in `terraform.tfvars` to the real GitHub username.
- **Bug #1 — missing GitHub OIDC provider.** `terraform plan` failed:
  `Error: finding IAM OIDC Provider by url (...token.actions.githubusercontent.com): not found`.
  `iam.tf` treats this as an account-scoped singleton it only *reads* (`data` source), never
  creates — comment literally says "reference the existing provider." The book never documents
  bootstrapping this for a brand-new AWS account. Fixed with a one-time
  `aws iam create-open-id-connect-provider`, using a thumbprint fetched live via `openssl
  s_client` rather than trusting a memorized value (which turned out to be one character short).
- **Bug #2 — AWS "Free Plan" blocks the lab outright.** `terraform apply` failed two ways at
  once: the EKS node group (`t3.medium` × 4) with `InvalidParameterCombination — not eligible
  for Free Tier`, and GuardDuty with `SubscriptionRequiredException`. Root cause: AWS's newer
  "Free Plan" account tier (distinct from classic Free Tier) hard-blocks non-free-tier EC2
  instance types and several paid-by-default services until the account is upgraded to "Paid
  Plan." This doesn't cost more — the $100 credit and budget alert are unaffected — it's a pure
  capability gate. Fixed by adding a payment method and clicking through the "upgrading your
  plan" link in the account dropdown; AWS auto-approved within minutes (confirmed via email).
  `terraform apply` then succeeded cleanly: 97 resources — VPC, 4-node EKS cluster, RDS Postgres,
  4 ECR repos, Secrets Manager, GuardDuty, CloudTrail, KMS, ALB controller.

### 3. `kubectl`/`helm` pointed at the wrong cluster

Both fell victim to the exact same 3-layer bug, discovered with `kubectl` first and then
pre-emptively fixed for `helm` before it could bite:

1. `~/.local/bin/{kubectl,helm}` were old wrapper scripts from Stages 0/6
   (`exec microk8s kubectl "$@"` / `exec microk8s helm3 "$@"`) — replaced both with real
   binaries (official downloads).
2. Even after that, both still resolved to the old MicroK8s behavior — `.bashrc` had
   `alias kubectl='microk8s kubectl'` and `alias helm='microk8s helm3'`, each **duplicated 3
   times** (accumulated across earlier stages without anyone noticing), and interactive bash
   aliases take priority over PATH lookups. Removed via `sed`.
3. Even after editing `.bashrc` and `source`-ing it, the aliases were still active in the current
   shell — `source` only adds/updates aliases present in the file, it does **not** remove
   aliases already loaded in the session. Needed an explicit `unalias` on top of the file edit.

After all three layers were fixed, `kubectl get nodes` and `helm list -A` both correctly showed
the real EKS cluster.

### 4. Running the platform stack (`aws-spinup.sh`, steps 3-15)

Ran the full script (`GIT_PUSH=1 bash stages/stage-8-aws-migration/scripts/aws-spinup.sh` —
directly, not via `make aws-up`, so the `GIT_PUSH=1` env var reliably propagates). This installs
ArgoCD, Kyverno + policies, Falco, ESO + IRSA ServiceAccounts, the CSI driver, and the full
Stage 7 observability stack, then deploys the app via ArgoCD and waits for the ALB.

Two more real bugs before it would even run:

- **Bug #3 — `clearledger-aws-app.yaml`'s repoURL still had the `YOUR_GITHUB_USERNAME`
  placeholder.** Same bug pattern seen in every earlier GitOps stage. Fixed proactively before
  running the script.
- **Bug #4 — the script's own safety check is too blunt.** `grep -q "CHANGE_ME_BEFORE_APPLY"
  secrets.tf` matches the whole file, including 3 explanatory *comments* that mention the
  placeholder phrase, not just the 4 real values — so it kept refusing to run even after every
  real value was correctly filled in. Fixed by rewording the comments (no functional change to
  any secret).

The script then ran end-to-end through all 15 steps, printed a live ALB URL, and reported
success — but "the script said success" isn't proof, so I verified for real.

### 5. Verifying — and finding what the script's own success message missed

`kubectl get pods -n clearledger` told a different story than the script's happy summary:
`ledger-service` was `CrashLoopBackOff`, `frontend` was `ImagePullBackOff`, and a spare
`auth-service` replica was stuck `Pending`.

- **Bug #5 — `PLACEHOLDER_RDS`, a literal, permanent hostname placeholder nothing ever
  replaces.** `secrets.tf`'s `database_url` fields reference `PLACEHOLDER_RDS:5432` — not
  mentioned by the book's Step A instructions (only the 4 `CHANGE_ME_BEFORE_APPLY` values), not
  patched by `aws-spinup.sh`, not referenced by any other script in the stage (confirmed via
  `grep -r PLACEHOLDER_RDS`). Caused `ledger-service` to crash with `could not translate host
  name "PLACEHOLDER_RDS"`. Critical wrinkle: the `secret_version` resources have
  `lifecycle { ignore_changes = [secret_string] }` (intentional, for out-of-band rotation), so
  fixing `secrets.tf` and re-`apply`-ing does **not** fix a live secret — had to
  `aws secretsmanager put-secret-value` directly, reading the real RDS endpoint from `terraform
  output` and the real Postgres password back out of the already-correct `clearledger/postgres`
  secret (never re-typed or exposed in chat), then `kubectl delete secret ...` to force ESO to
  re-sync immediately (its `refreshInterval` is 1h, too long to wait out).
- **Bug #6 — `aws-spinup.sh` never builds or pushes the `frontend` image.** Step 4
  (`build_and_push`) only handles `auth-service`, `ledger-service`, and `notification-service`,
  even though `kustomization.yaml`'s `images:` block patches all 4. Fixed by manually
  `docker build`/`push`-ing frontend with the same git-SHA tag the other 3 already used.
- **Bug #7 (a corollary of #5) — `auth-service`'s original pods never picked up the secret fix
  at all**, because they never crashed the way `ledger-service` did. Env vars are set once at
  container start, not live-reloaded, and `/health` doesn't touch the database — so the pods
  kept serving healthy pings with a stale `DATABASE_URL` right up until a real register/login
  attempt returned `Internal Server Error`. Fixed with an explicit `kubectl rollout restart`.
  **Lesson: a passing `/health` check is not proof a service picked up a corrected secret.**
- **Bug #8 — EKS pod-count ceiling.** The full platform stack (ArgoCD + Kyverno + Falco
  DaemonSet + ESO + CSI driver + Prometheus/Loki/Grafana, several running one pod per node) plus
  the app pods exceeded the 4-node ceiling of 68 pod slots (`t3.medium`'s ~17-pods/node VPC CNI
  default — `main.tf`'s own comment warned about this, just not accounting for the full platform
  stack on top of the app). Tried the "correct" fix — bumping `eks_node_count` to 5 in
  `terraform.tfvars` — but AWS **declined** the resulting vCPU quota increase request outright
  ("service quotas help you gradually ramp up activity"). Worked around it without any quota
  needed: uninstalled the Secrets Store CSI driver (`helm uninstall secrets-provider-aws -n
  kube-system` — the one release that owns both its DaemonSets as a dependency), which the
  script's own comments already call optional (§8.5 exercise only; default deploy uses ESO).
  Freed exactly enough capacity — every pod went `1/1 Running` immediately.

### 6. Final verification — for real, not just curl

- `kubectl get application clearledger-aws -n argocd` → `Synced` / `Healthy`
- All 3 health endpoints (`/auth/health`, `/ledger/health`, `/notifications/health`) → `200 OK`
  via `curl` against the live ALB
- **Registered a brand-new account in the browser** (this RDS instance starts empty — none of
  the homelab's seeded test accounts exist here), logged in, submitted transactions, and
  confirmed the fraud-detection `LARGE_TRANSACTION` alerts fire correctly on genuine AWS
  infrastructure — real UI proof, not just an API ping.

## What I can now claim

- Migrated a fully-featured DevSecOps platform (GitOps, admission control, secrets management,
  runtime security, observability) from a local homelab to real AWS infrastructure without
  rewriting a line of application code.
- Debugged and permanently root-caused eight distinct real infrastructure bugs across Terraform,
  a first-boot orchestration script, and AWS account-level service quotas — each fixed with
  direct evidence (logs, `describe`, CLI output), not guesswork.
- Understand IRSA (pod-level AWS IAM without long-lived credentials), ESO (AWS Secrets Manager →
  Kubernetes Secrets), and the operational difference between "the script said success" and
  actually verifying a service end-to-end.

## AWS Console checkpoints confirmed

- **EKS** → `clearledger` cluster → Status: Active (region must be **eu-west-1 "Ireland"** —
  console defaults to us-east-1 and shows nothing)
- **ECR** → all 4 repos present with real image tags after the fixes
- **RDS** → `clearledger-postgres` → Available
- **ALB** → live, `http://clearledger-358141189.eu-west-1.elb.amazonaws.com`

## Portfolio screenshot

`setup-journal/screenshots/stage8-aws-alb-dashboard.png` — ClearLedger dashboard, real ALB URL
in the address bar, transaction history and fraud alerts visible.

## Teardown — `terraform destroy` (Bug #9)

Ran `terraform destroy` once everything was verified. It got through the expensive parts cleanly
(EKS cluster, node group, RDS) but then failed with 6 errors, all from the same root cause:

**The AWS Load Balancer Controller creates real AWS resources (an ALB + 2 security groups)
dynamically, in response to Kubernetes objects — Terraform has zero record of them**, even
though the controller itself was installed via Terraform's Helm provider. Destroying the EKS
cluster doesn't clean these up; nothing tells AWS to remove them.

Fixed in order:
1. Found the orphaned ALB: `aws elbv2 describe-load-balancers --query
   '...contains(LoadBalancerName, `clearledger`)...'`, then `aws elbv2 delete-load-balancer`.
2. Force-deleted the 4 ECR repos (Terraform doesn't force-delete non-empty repos by default):
   `aws ecr delete-repository --force` for each.
3. Re-ran `terraform destroy` — the Internet Gateway and 2 public subnets went through this
   time, but the **VPC itself** then failed with another `DependencyViolation`.
4. Traced it to the same controller: `aws ec2 describe-security-groups --filters
   Name=vpc-id,Values=<vpc-id>` showed two extra groups beyond the default
   (`k8s-traffic-clearledger-*`, `k8s-clearled-clearled-*`) — deleted both via
   `aws ec2 delete-security-group`.
5. Final `terraform destroy` succeeded in 2 seconds. Confirmed with `terraform state list` —
   completely empty, no AWS charges accruing anymore.

**Lesson for next time:** if the AWS Load Balancer Controller was ever active in a cluster,
check `aws elbv2 describe-load-balancers` and `aws ec2 describe-security-groups` for that VPC
*before* running `terraform destroy` — clean those up first rather than letting the destroy
fail partway through and cascade.

## Not done (optional only — the lab is complete without these)

- §8.5 (CSI-driver file-mounts exercise) — CSI driver was uninstalled to free pod capacity (see
  Bug #8) and everything is now torn down anyway.
- Enabling ongoing AWS CI (`CLEARLEDGER_CI_TARGET=aws` + GitHub OIDC role secret) — optional,
  not required by the book's "Done when" checkpoint.
- `eks_node_count` is left at `5` in `terraform.tfvars` even though only 4 nodes can actually run
  (the 5th is permanently blocked by the declined quota) — harmless, the ASG just quietly keeps
  retrying in the background. Not worth reverting unless it causes confusion later.

## Full command reference — every terminal command run across this stage, in order

```bash
# --- AWS CLI + Terraform installation ---
aws sts get-caller-identity                      # first attempt: aws not found
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip                                # first attempt: unzip not found
sudo apt install unzip -y
unzip awscliv2.zip
sudo ./aws/install
aws --version

wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install terraform -y                     # failed: package not found (focal dropped)
curl -s https://apt.releases.hashicorp.com/dists/focal/main/binary-amd64/Packages | grep -c "^Package:"   # confirmed: 0
cd /tmp
TF_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | grep -o '"current_version":"[^"]*' | cut -d'"' -f4)
curl -O "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
unzip "terraform_${TF_VERSION}_linux_amd64.zip"
sudo mv terraform /usr/local/bin/
terraform --version

# --- IAM user + credentials ---
# (created terraform-admin IAM user + access key via AWS Console)
aws configure                                     # first attempt: pasted secret key into both fields by mistake
aws configure list                                # caught the mistake via matching key suffixes
aws sts get-caller-identity                        # confirmed: IncompleteSignature error
aws configure                                     # redone correctly from downloaded CSV
aws sts get-caller-identity                        # confirmed working

# --- Terraform config ---
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"
cat stages/stage-8-aws-migration/terraform/secrets.tf
FILE=stages/stage-8-aws-migration/terraform/secrets.tf
PG_PASSWORD=$(openssl rand -hex 24)
JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')
sed -i "s#clearledger:CHANGE_ME_BEFORE_APPLY@#clearledger:${PG_PASSWORD}@#g" "$FILE"
sed -i -E "s#(password[[:space:]]*=[[:space:]]*)\"CHANGE_ME_BEFORE_APPLY\"#\1\"${PG_PASSWORD}\"#" "$FILE"
sed -i -E "s#(jwt_secret[[:space:]]*=[[:space:]]*)\"CHANGE_ME_BEFORE_APPLY\"#\1\"${JWT_SECRET}\"#" "$FILE"
grep -c CHANGE_ME_BEFORE_APPLY "$FILE"             # confirmed 0 in real values (3 remained in comments, fixed later)

cp stages/stage-8-aws-migration/terraform/terraform.tfvars.example stages/stage-8-aws-migration/terraform/terraform.tfvars
# terraform.tfvars edited directly (github_owner = "AliRahimi123456")

cd stages/stage-8-aws-migration/terraform
terraform init -upgrade
terraform validate                                 # failed: missing OIDC provider (Bug #1)
terraform plan                                      # same error surfaced here first

# --- Bug #1 fix: GitHub OIDC provider ---
THUMBPRINT=$(openssl s_client -servername token.actions.githubusercontent.com -showcerts \
  -connect token.actions.githubusercontent.com:443 </dev/null 2>/dev/null | \
  openssl x509 -fingerprint -sha1 -noout | cut -d'=' -f2 | tr -d ':' | tr 'A-F' 'a-f')
echo "Thumbprint: $THUMBPRINT"
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list "$THUMBPRINT"

terraform plan                                       # succeeded: 97 to add
terraform apply                                       # failed: Free Plan blocks (Bug #2)
                                                        # - EKS node group: InvalidParameterCombination (not free-tier eligible)
                                                        # - GuardDuty: SubscriptionRequiredException

# --- Bug #2 fix: AWS Free Plan → Paid Plan (via Console: Billing → Payment preferences → add card,
#     then account dropdown → "upgrading your plan" link) ---
terraform apply                                        # succeeded: Apply complete! Resources: 4 added, 0 changed, 1 destroyed

# --- kubectl / helm wrapper + alias fixes ---
aws configure get region
cat stages/stage-8-aws-migration/terraform/secrets.tf   # (re-check after fixes)
aws eks update-kubeconfig --name clearledger --region eu-west-1
kubectl get nodes                                        # wrong: showed homelab node (wrapper/alias bug)
which kubectl
cat ~/.local/bin/kubectl                                  # confirmed: old microk8s wrapper
cd /tmp
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl ~/.local/bin/kubectl
kubectl version --client
kubectl get nodes                                          # still wrong: alias override
kubectl config get-contexts
kubectl config current-context
ls -la ~/.kube/config
cat ~/.kube/config                                          # confirmed: file itself was correct (EKS-only)
file ~/.local/bin/kubectl
ls -la ~/.local/bin/kubectl
hash -r
kubectl version --client                                     # still stale — alias, not PATH cache
type -a kubectl                                                # confirmed: aliased to microk8s kubectl
alias | grep kubectl
declare -f kubectl
grep -rn "alias kubectl" ~/.bashrc ~/.bash_aliases ~/.profile 2>/dev/null
sed -n '110,130p' ~/.bashrc
sed -i "/^alias kubectl='microk8s kubectl'$/d" ~/.bashrc
grep -n "alias kubectl\|alias helm" ~/.bashrc
source ~/.bashrc
kubectl get nodes                                              # still wrong — source doesn't remove loaded aliases
type -a kubectl
unalias kubectl
type -a kubectl
kubectl get nodes                                               # correct: 4 real EKS nodes

# pre-emptive helm fix
cat ~/.local/bin/helm                                            # confirmed: same old wrapper
cd /tmp
HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name"' | cut -d '"' -f4)
curl -LO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
mv linux-amd64/helm ~/.local/bin/helm
chmod +x ~/.local/bin/helm
rm -rf linux-amd64 "helm-${HELM_VERSION}-linux-amd64.tar.gz"
sed -i "/^alias helm='microk8s helm3'$/d" ~/.bashrc
unalias helm 2>/dev/null
hash -r
helm version
helm list -A                                                       # confirmed: reads EKS kubeconfig correctly

# --- AWS Console verification (region switched to eu-west-1 "Ireland") ---
# EKS → clearledger → Active; ECR → 4 repos; RDS → clearledger-postgres → Available

# --- Bug #3 fix: ArgoCD app repoURL placeholder ---
# stages/stage-8-aws-migration/argocd/clearledger-aws-app.yaml edited directly

docker ps >/dev/null 2>&1 && echo "docker OK"
which docker kustomize

# --- Bug #4 fix: secrets.tf comment wording (grep check too blunt) ---
cat stages/stage-8-aws-migration/terraform/secrets.tf
# 3 comment lines edited directly (removed literal CHANGE_ME_BEFORE_APPLY text)
grep -c CHANGE_ME_BEFORE_APPLY stages/stage-8-aws-migration/terraform/secrets.tf   # confirmed 0

# --- Full spinup script run ---
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"
GIT_PUSH=1 bash stages/stage-8-aws-migration/scripts/aws-spinup.sh
# prompted for GitHub username + PAT (generated fine-grained PAT, Contents: Read/write on clearledger repo)
# completed all 15 steps, printed ALB URL

# --- Post-deploy verification (found real gaps despite script's success message) ---
kubectl get application clearledger-aws -n argocd
kubectl get pods -n clearledger
curl -s http://clearledger-358141189.eu-west-1.elb.amazonaws.com/auth/health
curl -s http://clearledger-358141189.eu-west-1.elb.amazonaws.com/ledger/health          # 503
curl -s http://clearledger-358141189.eu-west-1.elb.amazonaws.com/notifications/health

# --- Bug #5 fix: PLACEHOLDER_RDS ---
kubectl logs -n clearledger deployment/ledger-service --tail=30
cd stages/stage-8-aws-migration/terraform
RDS_HOST=$(terraform output -raw rds_endpoint | cut -d: -f1)
cd ../../..
PG_PASSWORD=$(aws secretsmanager get-secret-value --secret-id clearledger/postgres --region eu-west-1 --query SecretString --output text | python3 -c "import json,sys; print(json.load(sys.stdin)['password'])")
AUTH_JWT=$(aws secretsmanager get-secret-value --secret-id clearledger/auth-service --region eu-west-1 --query SecretString --output text | python3 -c "import json,sys; print(json.load(sys.stdin)['jwt_secret'])")
export RDS_HOST PG_PASSWORD AUTH_JWT
AUTH_JSON=$(python3 -c "
import json, os
print(json.dumps({
    'jwt_secret': os.environ['AUTH_JWT'],
    'database_url': f\"postgresql://clearledger:{os.environ['PG_PASSWORD']}@{os.environ['RDS_HOST']}:5432/clearledger\"
}))
")
aws secretsmanager put-secret-value --secret-id clearledger/auth-service --region eu-west-1 --secret-string "$AUTH_JSON"
LEDGER_JSON=$(python3 -c "
import json, os
print(json.dumps({
    'database_url': f\"postgresql://clearledger:{os.environ['PG_PASSWORD']}@{os.environ['RDS_HOST']}:5432/clearledger\"
}))
")
aws secretsmanager put-secret-value --secret-id clearledger/ledger-service --region eu-west-1 --secret-string "$LEDGER_JSON"
unset RDS_HOST PG_PASSWORD AUTH_JWT AUTH_JSON LEDGER_JSON
kubectl delete secret auth-service-secret ledger-service-secret -n clearledger
kubectl get secret auth-service-secret ledger-service-secret -n clearledger
kubectl rollout restart deployment/auth-service deployment/ledger-service -n clearledger
kubectl rollout status deployment/ledger-service -n clearledger --timeout=120s

# --- cleaning up stuck/redundant pods from the restart, given pod-count pressure ---
kubectl get pods -n clearledger
kubectl logs -n clearledger deployment/ledger-service --tail=20     # confirmed: 200 OK, fixed
kubectl describe pod -n clearledger auth-service-6798dd88fb-tb5sb | tail -15
kubectl top nodes 2>/dev/null || kubectl describe nodes | grep -A5 "Allocated resources"
kubectl get pods -n clearledger auth-service-79597569d8-psclz
kubectl describe pod -n clearledger auth-service-79597569d8-psclz | tail -10
kubectl get pods -A --no-headers | wc -l                             # 69 (over the 68-slot ceiling)
kubectl get pods -A --field-selector spec.nodeName=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') --no-headers | wc -l
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODS:.status.allocatable.pods

# --- attempted node-count bump (Bug #8, part 1 — ultimately blocked) ---
# terraform.tfvars edited: added eks_node_count = 5
cd stages/stage-8-aws-migration/terraform
terraform plan
terraform apply                                                        # succeeded: node group scaled 4→5 (desired)
cd ../../..
kubectl get nodes                                                       # still 4 — new node never joined
sleep 60
kubectl get nodes
aws eks describe-nodegroup --cluster-name clearledger --nodegroup-name clearledger-nodes --region eu-west-1 --query 'nodegroup.{status:status,scaling:scalingConfig,health:health}'
ASG_NAME=$(aws eks describe-nodegroup --cluster-name clearledger --nodegroup-name clearledger-nodes --region eu-west-1 --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)
aws --no-cli-pager autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region eu-west-1 --query 'AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[*].{id:InstanceId,state:LifecycleState,health:HealthStatus}}'
aws --no-cli-pager autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" --region eu-west-1 --max-items 5 --query 'Activities[*].{status:StatusCode,desc:Description,reason:StatusMessage}'
# confirmed: VcpuLimitExceeded — requested quota increase via Service Quotas console
# AWS declined the request via email (manual review — permanent no, not a delay)

# --- Bug #8 fix: uninstall optional CSI driver to free capacity instead ---
kubectl get pods -A -o wide --no-headers | awk '{print $1}' | sort | uniq -c | sort -rn
kubectl get daemonsets -A
helm list -A | grep -i secrets
helm uninstall secrets-provider-aws -n kube-system
kubectl get daemonsets -A                                               # confirmed: both CSI DaemonSets gone
kubectl get pods -n clearledger                                          # all 1/1 Running

# --- Bug #6 fix: frontend image never built by the script ---
GIT_SHA=739d3f5
ECR_REGISTRY=856986449724.dkr.ecr.eu-west-1.amazonaws.com
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY"
docker build -t "${ECR_REGISTRY}/clearledger/frontend:${GIT_SHA}" app/frontend
docker push "${ECR_REGISTRY}/clearledger/frontend:${GIT_SHA}"
kubectl describe pod -n clearledger frontend-6848cbd75-9kjbd | tail -15
kubectl delete pod -n clearledger frontend-6848cbd75-9kjbd
kubectl get pods -n clearledger -l app=frontend
kubectl describe pod -n clearledger frontend-6848cbd75-74d84 | tail -5

# --- Bug #7 fix: auth-service pods never picked up the earlier secret fix ---
kubectl logs -n clearledger deployment/auth-service --tail=30            # confirmed: still PLACEHOLDER_RDS (stale env)
kubectl rollout restart deployment/auth-service -n clearledger
kubectl rollout status deployment/auth-service -n clearledger --timeout=120s

# --- Final verification ---
kubectl get application clearledger-aws -n argocd                        # Synced / Healthy
curl -s http://clearledger-358141189.eu-west-1.elb.amazonaws.com/auth/health
curl -s http://clearledger-358141189.eu-west-1.elb.amazonaws.com/ledger/health
curl -s http://clearledger-358141189.eu-west-1.elb.amazonaws.com/notifications/health
curl -sI http://clearledger-358141189.eu-west-1.elb.amazonaws.com/
# then: registered a new account, logged in, submitted transactions, confirmed fraud
# alerts fired, in an actual browser — screenshot saved as stage8-aws-alb-dashboard.png
```
