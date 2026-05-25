#!/usr/bin/env bash
# chmod +x stages/stage-8-aws-migration/scripts/aws-spinup.sh
#
# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: Orchestrate the full ClearLedger AWS deployment in one command.
#          Provisions infrastructure, builds images, deploys to EKS, and
#          prints the live URL when done.
#
# Usage: bash stages/stage-8-aws-migration/scripts/aws-spinup.sh
# Run from the repository root.

set -euo pipefail

trap 'echo "" && echo "❌  Setup failed at line $LINENO." && echo "    Run stages/stage-8-aws-migration/scripts/aws-destroy.sh to clean up any partially created resources." && exit 1' ERR

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() { echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${NC}"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TF_DIR="${REPO_ROOT}/stages/stage-8-aws-migration/terraform"
MANIFESTS_DIR="${REPO_ROOT}/infra/manifests"

# ── 1. Prerequisite checks ────────────────────────────────────────────────────
banner "Step 1 of 12 — Checking prerequisites"

check_cmd() {
  local cmd=$1 install_hint=$2
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}✗  $cmd not found.${NC}  Install: $install_hint"
    exit 1
  fi
  echo -e "${GREEN}✓  $cmd${NC}"
}

check_cmd aws      "https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
check_cmd terraform "https://developer.hashicorp.com/terraform/install"
check_cmd kubectl  "https://kubernetes.io/docs/tasks/tools/"
check_cmd docker   "https://docs.docker.com/get-docker/"
check_cmd helm     "https://helm.sh/docs/intro/install/"
check_cmd git      "https://git-scm.com/downloads"

# Verify AWS credentials are configured
if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}✗  AWS credentials not configured or expired.${NC}"
  echo "   Run: aws configure   (or set AWS_PROFILE / AWS_ACCESS_KEY_ID)"
  exit 1
fi
echo -e "${GREEN}✓  AWS credentials valid${NC}"

aws_account=$(aws sts get-caller-identity --query Account --output text)
aws_region=$(aws configure get region || echo "eu-west-1")
echo -e "   Account: ${BOLD}${aws_account}${NC}  Region: ${BOLD}${aws_region}${NC}"

# ── 2. Terraform init and apply ───────────────────────────────────────────────
banner "Step 2 of 12 — Terraform init & apply"

echo -e "${YELLOW}⚠  This will create real AWS resources and incur costs.${NC}"
echo -e "${YELLOW}   Estimated: ~\$0.30–0.45/hour for the default configuration.${NC}"
echo ""
read -rp "Continue? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }

echo ""
echo "Reminder: did you update CHANGE_ME_BEFORE_APPLY in infra/terraform/secrets.tf?"
read -rp "Secrets updated? (yes/skip): " secrets_updated
if [[ "$secrets_updated" != "yes" ]]; then
  echo -e "${YELLOW}→  Edit infra/terraform/secrets.tf then re-run this script.${NC}"
  exit 0
fi

cd "$TF_DIR"
echo "→  terraform init..."
terraform init -upgrade

echo "→  terraform apply..."
terraform apply -auto-approve

# Capture outputs into shell variables
echo "→  Reading Terraform outputs..."
ECR_REGISTRY=$(terraform output -raw ecr_registry_url)
AUTH_ECR=$(terraform output -raw auth_service_ecr_url)
LEDGER_ECR=$(terraform output -raw ledger_service_ecr_url)
NOTIFICATION_ECR=$(terraform output -raw notification_service_ecr_url)
CLUSTER_NAME=$(terraform output -raw cluster_name)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
ESO_ROLE_ARN=$(terraform output -raw eso_role_arn)
KUBECONFIG_CMD=$(terraform output -raw kubeconfig_command)

cd "$REPO_ROOT"

# ── 2.5 Verify security services ──────────────────────────────────────────────
banner "Step 2.5 of 12 — Verifying security services"

echo "Verifying security services..."

DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || true)
if [[ -n "$DETECTOR_ID" && "$DETECTOR_ID" != "None" ]]; then
  echo -e "${GREEN}✓  GuardDuty enabled: ${DETECTOR_ID}${NC}"
else
  echo -e "${RED}✗  GuardDuty not enabled — check Terraform output${NC}"
fi

TRAIL_STATUS=$(aws cloudtrail get-trail-status --name "${CLUSTER_NAME}-trail" --query IsLogging --output text 2>/dev/null || true)
if [[ "$TRAIL_STATUS" == "True" ]]; then
  echo -e "${GREEN}✓  CloudTrail logging active${NC}"
else
  # Fallback to default name from var.project_name
  TRAIL_STATUS=$(aws cloudtrail get-trail-status --name "clearledger-trail" --query IsLogging --output text 2>/dev/null || true)
  if [[ "$TRAIL_STATUS" == "True" ]]; then
    echo -e "${GREEN}✓  CloudTrail logging active${NC}"
  else
    echo -e "${RED}✗  CloudTrail not logging${NC}"
  fi
fi

echo -e "${GREEN}✓  Security services active. AWS account is being monitored.${NC}"

# ── 3. Authenticate Docker to ECR ─────────────────────────────────────────────
banner "Step 3 of 12 — ECR Docker authentication"

aws ecr get-login-password --region "$aws_region" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
echo -e "${GREEN}✓  Logged in to ECR: ${ECR_REGISTRY}${NC}"

# ── 4. Build and push images ───────────────────────────────────────────────────
banner "Step 4 of 12 — Build & push images to ECR"

GIT_SHA=$(git rev-parse --short HEAD)
echo "→  Git SHA: ${GIT_SHA}"

build_and_push() {
  local service=$1 ecr_url=$2
  echo ""
  echo "→  Building ${service}..."
  docker build -t "${ecr_url}:latest" -t "${ecr_url}:${GIT_SHA}" \
    "${REPO_ROOT}/app/${service}"
  echo "→  Pushing ${service}..."
  docker push "${ecr_url}:latest"
  docker push "${ecr_url}:${GIT_SHA}"
  echo -e "${GREEN}✓  ${service} pushed${NC}"
}

build_and_push "auth-service"          "$AUTH_ECR"
build_and_push "ledger-service"        "$LEDGER_ECR"
build_and_push "notification-service"  "$NOTIFICATION_ECR"

# ── 5. Update kubeconfig ───────────────────────────────────────────────────────
banner "Step 5 of 12 — Configuring kubectl for EKS"

eval "$KUBECONFIG_CMD"
echo -e "${GREEN}✓  kubectl context set to EKS cluster: ${CLUSTER_NAME}${NC}"
kubectl cluster-info

# ── 6. Update image references in manifests ────────────────────────────────────
banner "Step 6 of 12 — Patching manifest image URLs"

# Replace the Docker Hub placeholder with ECR URLs.
# Uses the git SHA tag for immutability — :latest is pushed but not used for deploy.
sed -i.bak "s|DOCKER_USERNAME/clearledger-auth-service:.*|${AUTH_ECR}:${GIT_SHA}|g" \
  "${MANIFESTS_DIR}/auth-service/deployment.yaml"
sed -i.bak "s|DOCKER_USERNAME/clearledger-ledger-service:.*|${LEDGER_ECR}:${GIT_SHA}|g" \
  "${MANIFESTS_DIR}/ledger-service/deployment.yaml"
sed -i.bak "s|DOCKER_USERNAME/clearledger-notification-service:.*|${NOTIFICATION_ECR}:${GIT_SHA}|g" \
  "${MANIFESTS_DIR}/notification-service/deployment.yaml"

# Clean up sed backup files
find "${MANIFESTS_DIR}" -name "*.bak" -delete

echo -e "${GREEN}✓  Deployment manifests updated with ECR URLs (SHA: ${GIT_SHA})${NC}"

# ── 7. Install ArgoCD ─────────────────────────────────────────────────────────
banner "Step 7 of 12 — Installing ArgoCD"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "→  Waiting for argocd-server deployment (up to 120s)..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=120s
echo -e "${GREEN}✓  ArgoCD ready${NC}"

# ── 8. Install Kyverno ────────────────────────────────────────────────────────
banner "Step 8 of 12 — Installing Kyverno"

helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --set admissionController.replicas=1 \
  --wait --timeout=120s
echo -e "${GREEN}✓  Kyverno ready${NC}"

# ── 9. Install Falco ──────────────────────────────────────────────────────────
banner "Step 9 of 12 — Installing Falco"

helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=ebpf \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${ESO_ROLE_ARN}" \
  --wait --timeout=180s
echo -e "${GREEN}✓  Falco ready${NC}"

# ── 10. Apply Kubernetes manifests ────────────────────────────────────────────
banner "Step 10 of 12 — Applying Kubernetes manifests"

# Install External Secrets Operator first so ESO CRDs exist before ExternalSecret objects
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${ESO_ROLE_ARN}" \
  --wait --timeout=120s
echo -e "${GREEN}✓  External Secrets Operator ready${NC}"

# Apply all manifests (namespace first, then the rest)
kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"
kubectl apply -f "${MANIFESTS_DIR}/" --recursive

# Apply the AWS-specific ingress (ALB, not nginx)
kubectl apply -f "${REPO_ROOT}/stages/stage-8-aws-migration/manifests/ingress-aws.yaml"
echo -e "${GREEN}✓  All manifests applied${NC}"

# ── 11. Wait for ALB provisioning ─────────────────────────────────────────────
banner "Step 11 of 12 — Waiting for ALB provisioning"

echo "→  The ALB controller is provisioning the load balancer..."
echo "   This typically takes 60-90 seconds after the Ingress is created."
for i in $(seq 1 9); do
  sleep 10
  alb_hostname=$(kubectl get ingress clearledger-ingress -n clearledger \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "$alb_hostname" ]]; then
    echo -e "${GREEN}✓  ALB provisioned: ${alb_hostname}${NC}"
    break
  fi
  echo "   Still waiting... (${i}0s elapsed)"
done

# Final check
ALB_DNS=$(kubectl get ingress clearledger-ingress -n clearledger \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

if [[ -z "$ALB_DNS" ]]; then
  echo -e "${YELLOW}⚠  ALB not yet provisioned. Check status with:${NC}"
  echo "   kubectl get ingress clearledger-ingress -n clearledger"
  ALB_DNS="<ALB_DNS — run above command to get hostname>"
fi

# ── 12. Print access details ──────────────────────────────────────────────────
banner "Step 12 of 12 — ClearLedger is live!"

echo ""
echo -e "${GREEN}${BOLD}  ClearLedger is live at: http://${ALB_DNS}${NC}"
echo ""
echo -e "${BOLD}  Service endpoints:${NC}"
echo -e "    Auth service:          http://${ALB_DNS}/auth/health"
echo -e "    Ledger service:        http://${ALB_DNS}/ledger/health"
echo -e "    Notification service:  http://${ALB_DNS}/notifications/health"
echo ""
echo -e "${BOLD}  ArgoCD:${NC}"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo "    Then visit: https://localhost:8080"
argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "<run command above>")
echo "    Initial admin password: ${argocd_password}"
echo ""
echo -e "${BOLD}  Tear down when done:${NC}"
echo "    bash stages/stage-8-aws-migration/scripts/aws-destroy.sh"
echo ""
echo -e "${BOLD}  AWS resources live in region:${NC} ${aws_region}  Account: ${aws_account}"
echo ""
