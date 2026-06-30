#!/usr/bin/env bash
# Stage 8 — AWS first-boot orchestrator (demo stack, production-shaped)
#
# What this script does:
#   1. Terraform — VPC, EKS, RDS, ECR, GuardDuty, CloudTrail, IRSA roles
#   2. Build + push images to ECR (optionally Cosign-sign for Kyverno)
#   3. Install platform: ArgoCD, Kyverno, Falco, ESO, observability (Stage 7)
#   4. GitOps deploy via ArgoCD Application clearledger-aws (NOT kubectl apply on app Deployments)
#
# Secrets on AWS: External Secrets Operator (ESO) reads AWS Secrets Manager via IRSA.
# Homelab Stages 5–7 use HashiCorp Vault agent injection instead — same app code, different backend.
#
# Usage: bash stages/stage-8-aws-migration/scripts/aws-spinup.sh
# Tear down: bash stages/stage-8-aws-migration/scripts/aws-destroy.sh

set -euo pipefail

trap 'echo "" && echo "❌  Setup failed at line $LINENO." && echo "    Run stages/stage-8-aws-migration/scripts/aws-destroy.sh to clean up." && exit 1' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
  echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${NC}"
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STAGE_DIR="${REPO_ROOT}/stages/stage-8-aws-migration"
TF_DIR="${STAGE_DIR}/terraform"
KUSTOMIZE_DIR="${STAGE_DIR}/manifests"
FALCO_VALUES="${REPO_ROOT}/stages/stage-6-runtime-security/infra/falco/helm-values.yaml"
SECRETS_TF="${TF_DIR}/secrets.tf"

# ── 1. Prerequisites ────────────────────────────────────────────────────────
banner "Step 1 of 15 — Checking prerequisites"

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}✗  $1 not found.${NC}  Install: $2"
    exit 1
  }
  echo -e "${GREEN}✓  $1${NC}"
}

check_cmd aws "https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
check_cmd terraform "https://developer.hashicorp.com/terraform/install"
check_cmd kubectl "https://kubernetes.io/docs/tasks/tools/"
check_cmd docker "https://docs.docker.com/get-docker/"
check_cmd helm "https://helm.sh/docs/intro/install/"
check_cmd git "https://git-scm.com/downloads"
check_cmd kustomize "https://kubectl.docs.kubernetes.io/installation/kustomize/"

aws sts get-caller-identity >/dev/null || {
  echo -e "${RED}✗  AWS credentials not configured.${NC}"
  exit 1
}
echo -e "${GREEN}✓  AWS credentials valid${NC}"

aws_account=$(aws sts get-caller-identity --query Account --output text)
aws_region=$(aws configure get region 2>/dev/null || echo "eu-west-1")
echo -e "   Account: ${BOLD}${aws_account}${NC}  Region: ${BOLD}${aws_region}${NC}"

# ── 2. Terraform ────────────────────────────────────────────────────────────
banner "Step 2 of 15 — Terraform init & apply"

echo -e "${YELLOW}⚠  Demo stack — creates billable AWS resources (~\$0.35–0.45/hour).${NC}"
echo -e "${YELLOW}   Destroy with: make aws-down${NC}"
echo ""
read -rp "Continue? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }

if grep -q "CHANGE_ME_BEFORE_APPLY" "${SECRETS_TF}" 2>/dev/null; then
  echo -e "${RED}✗  Edit ${SECRETS_TF} — replace CHANGE_ME_BEFORE_APPLY before apply.${NC}"
  exit 1
fi

cd "${TF_DIR}"
terraform init -upgrade
terraform apply -auto-approve

ECR_REGISTRY=$(terraform output -raw ecr_registry_url)
AUTH_ECR=$(terraform output -raw auth_service_ecr_url)
LEDGER_ECR=$(terraform output -raw ledger_service_ecr_url)
NOTIFICATION_ECR=$(terraform output -raw notification_service_ecr_url)
CLUSTER_NAME=$(terraform output -raw cluster_name)
ESO_ROLE_ARN=$(terraform output -raw eso_role_arn)
FALCO_ROLE_ARN=$(terraform output -raw falco_role_arn)
AUTH_IRSA=$(terraform output -raw auth_service_irsa_role_arn)
LEDGER_IRSA=$(terraform output -raw ledger_service_irsa_role_arn)
NOTIFY_IRSA=$(terraform output -raw notification_service_irsa_role_arn)
KUBECONFIG_CMD=$(terraform output -raw kubeconfig_command)
cd "${REPO_ROOT}"

# ── 3. Verify AWS security services ─────────────────────────────────────────
banner "Step 3 of 15 — Verifying GuardDuty & CloudTrail"

DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || true)
[[ -n "${DETECTOR_ID}" && "${DETECTOR_ID}" != "None" ]] \
  && echo -e "${GREEN}✓  GuardDuty: ${DETECTOR_ID}${NC}" \
  || echo -e "${YELLOW}⚠  GuardDuty not found${NC}"

TRAIL_STATUS=$(aws cloudtrail get-trail-status --name "clearledger-trail" --query IsLogging --output text 2>/dev/null || true)
[[ "${TRAIL_STATUS}" == "True" ]] \
  && echo -e "${GREEN}✓  CloudTrail logging${NC}" \
  || echo -e "${YELLOW}⚠  CloudTrail not logging${NC}"

# ── 4. Build & push to ECR ────────────────────────────────────────────────────
banner "Step 4 of 15 — Build & push images to ECR"

aws ecr get-login-password --region "${aws_region}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

GIT_SHA=$(git -C "${REPO_ROOT}" rev-parse --short HEAD)
echo "→  Image tag: ${GIT_SHA}"

sign_image() {
  local image="$1"
  if [[ -n "${COSIGN_PRIVATE_KEY:-}" && -n "${COSIGN_PASSWORD:-}" ]]; then
    cosign sign --key env://COSIGN_PRIVATE_KEY --tlog-upload=false "${image}" || true
  elif [[ -f "${REPO_ROOT}/infra/cosign.key" ]]; then
    cosign sign --key "${REPO_ROOT}/infra/cosign.key" --tlog-upload=false "${image}" || true
  else
    echo -e "${YELLOW}  ⚠  No Cosign key — apply Kyverno ECR policy in Audit mode or sign images before deploy${NC}"
  fi
}

build_and_push() {
  local service="$1" ecr_url="$2"
  echo "→  ${service}..."
  docker build -t "${ecr_url}:${GIT_SHA}" "${REPO_ROOT}/app/${service}"
  docker push "${ecr_url}:${GIT_SHA}"
  sign_image "${ecr_url}:${GIT_SHA}"
  echo -e "${GREEN}✓  ${service} pushed${NC}"
}

build_and_push "auth-service" "${AUTH_ECR}"
build_and_push "ledger-service" "${LEDGER_ECR}"
build_and_push "notification-service" "${NOTIFICATION_ECR}"

# ── 5. Kustomize image tags (GitOps source) ─────────────────────────────────
banner "Step 5 of 15 — Updating GitOps manifests (kustomization.yaml)"

KUSTOMIZATION="${KUSTOMIZE_DIR}/kustomization.yaml"
sed -i.bak \
  -e "s|REPLACE_ECR_REGISTRY|${ECR_REGISTRY}|g" \
  -e "s|REPLACE_IMAGE_TAG|${GIT_SHA}|g" \
  "${KUSTOMIZATION}"
rm -f "${KUSTOMIZATION}.bak"

# Patch ESO + CSI region if not eu-west-1
sed -i.bak "s|region: eu-west-1|region: ${aws_region}|g" \
  "${KUSTOMIZE_DIR}/external-secrets.yaml" \
  "${KUSTOMIZE_DIR}/csi/auth-service-spc.yaml" \
  "${KUSTOMIZE_DIR}/csi/ledger-service-spc.yaml" 2>/dev/null || true
rm -f "${KUSTOMIZE_DIR}/external-secrets.yaml.bak" \
  "${KUSTOMIZE_DIR}/csi/auth-service-spc.yaml.bak" \
  "${KUSTOMIZE_DIR}/csi/ledger-service-spc.yaml.bak" 2>/dev/null || true

echo -e "${GREEN}✓  kustomization.yaml points at ECR:${GIT_SHA}${NC}"
echo -e "${YELLOW}→  Commit and push this file before ArgoCD sync (or set GIT_PUSH=1 below).${NC}"

# ── 6. kubeconfig ───────────────────────────────────────────────────────────
banner "Step 6 of 15 — Configuring kubectl"

eval "${KUBECONFIG_CMD}"
echo -e "${GREEN}✓  Context: ${CLUSTER_NAME}${NC}"

# ── 7. ArgoCD ───────────────────────────────────────────────────────────────
banner "Step 7 of 15 — Installing ArgoCD"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
echo -e "${GREEN}✓  ArgoCD ready${NC}"

# ── 8. Kyverno + policies ───────────────────────────────────────────────────
banner "Step 8 of 15 — Installing Kyverno & policies"

helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  -f "${REPO_ROOT}/stages/stage-4-admission-control/infra/kyverno/values.yaml" \
  --set admissionController.replicas=1 \
  --wait --timeout=180s

kubectl apply -f "${REPO_ROOT}/infra/policies/" --server-side=true 2>/dev/null || \
  kubectl apply -f "${REPO_ROOT}/infra/policies/"
echo -e "${GREEN}✓  Kyverno + ClusterPolicies applied${NC}"

# ── 9. Falco (correct IRSA + custom rules) ──────────────────────────────────
banner "Step 9 of 15 — Installing Falco"

helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update >/dev/null
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  -f "${FALCO_VALUES}" \
  --set driver.kind=modern_ebpf \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${FALCO_ROLE_ARN}" \
  --wait --timeout=300s
echo -e "${GREEN}✓  Falco ready (IRSA: falco role)${NC}"

# ── 10. External Secrets Operator ───────────────────────────────────────────
banner "Step 10 of 15 — Installing ESO + IRSA ServiceAccounts"

helm repo add external-secrets https://charts.external-secrets.io --force-update >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${ESO_ROLE_ARN}" \
  --wait --timeout=180s

kubectl apply -f "${STAGE_DIR}/manifests/resources/namespace.yaml"
export REPLACE_AUTH_IRSA_ROLE_ARN="${AUTH_IRSA}"
export REPLACE_LEDGER_IRSA_ROLE_ARN="${LEDGER_IRSA}"
export REPLACE_NOTIFICATION_IRSA_ROLE_ARN="${NOTIFY_IRSA}"
envsubst < "${STAGE_DIR}/manifests/clearledger-serviceaccounts.yaml" | kubectl apply -f -
echo -e "${GREEN}✓  ESO + workload ServiceAccounts (IRSA)${NC}"

# ── 11. Secrets Store CSI Driver ─────────────────────────────────────────────
banner "Step 11 of 15 — Installing CSI driver + SecretProviderClasses"

bash "${STAGE_DIR}/scripts/install-csi-secrets.sh"
echo -e "${GREEN}✓  CSI driver ready (SecretProviderClasses applied; default deploy still uses ESO)${NC}"

# ── 12. Observability (Stage 7 stack) ───────────────────────────────────────
banner "Step 12 of 15 — Installing observability (Prometheus + Grafana + Loki)"

bash "${REPO_ROOT}/stages/stage-7-observability/scripts/install-observability.sh"
echo -e "${GREEN}✓  Observability stack installed${NC}"

# ── 13. GitOps deploy (ArgoCD — not kubectl apply on Deployments) ───────────
banner "Step 13 of 15 — GitOps deploy via ArgoCD"

if [[ "${GIT_PUSH:-}" == "1" ]]; then
  git -C "${REPO_ROOT}" add "${KUSTOMIZATION}" "${KUSTOMIZE_DIR}/external-secrets.yaml" 2>/dev/null || true
  git -C "${REPO_ROOT}" commit -m "stage8: bootstrap ECR images ${GIT_SHA}" 2>/dev/null || true
  git -C "${REPO_ROOT}" push origin HEAD 2>/dev/null || {
    echo -e "${YELLOW}⚠  git push failed — push manually, then re-run: argocd app sync clearledger-aws${NC}"
  }
else
  echo -e "${YELLOW}→  Push kustomization.yaml to Git, then ArgoCD will sync.${NC}"
  echo "   Quick push: GIT_PUSH=1 bash stages/stage-8-aws-migration/scripts/aws-spinup.sh (from step 5)"
  echo "   Or: git add ${KUSTOMIZATION} && git commit && git push"
fi

kubectl apply -f "${STAGE_DIR}/argocd/clearledger-aws-app.yaml"

echo "→  Waiting for ArgoCD to sync (up to 5 min)..."
for _ in $(seq 1 30); do
  phase=$(kubectl get application clearledger-aws -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl get application clearledger-aws -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  if [[ "${phase}" == "Synced" && "${health}" == "Healthy" ]]; then
    echo -e "${GREEN}✓  ArgoCD Synced + Healthy${NC}"
    break
  fi
  sleep 10
done

# Bootstrap sync if Git not pushed yet (local kustomize build — one-time fallback)
if [[ "$(kubectl get application clearledger-aws -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)" != "Synced" ]]; then
  echo -e "${YELLOW}→  ArgoCD not synced yet — applying kustomize once for bootstrap (push Git for ongoing GitOps).${NC}"
  kubectl apply -k "${KUSTOMIZE_DIR}"
fi

# ── 14. ALB ─────────────────────────────────────────────────────────────────
banner "Step 14 of 15 — Waiting for ALB"

ALB_DNS=""
for i in $(seq 1 12); do
  ALB_DNS=$(kubectl get ingress clearledger-ingress -n clearledger \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "${ALB_DNS}" ]] && break
  echo "   Waiting... (${i}0s)"
  sleep 10
done

# ── 15. Summary ─────────────────────────────────────────────────────────────
banner "Step 15 of 15 — ClearLedger AWS demo stack is live"

echo ""
echo -e "${BOLD}Demo stack (not production):${NC} HTTP ALB, public EKS API, single env."
echo -e "${BOLD}Secrets:${NC} ESO (default deploy) + CSI driver installed (§8.5 lab switches auth to file mounts)."
echo -e "${BOLD}Manual steps:${NC} docs/LAB-GUIDE.md §8.2 — do not skip if you only ran make aws-up."
echo -e "${BOLD}Ongoing deploys:${NC} ci-aws.yaml → update kustomization.yaml → ArgoCD sync."
echo ""
echo -e "${GREEN}${BOLD}  URL: http://${ALB_DNS:-<pending>}${NC}"
echo -e "    Auth:          http://${ALB_DNS:-ALB_DNS}/auth/health"
echo -e "    Ledger:        http://${ALB_DNS:-ALB_DNS}/ledger/health"
echo -e "    Notifications: http://${ALB_DNS:-ALB_DNS}/notifications/health"
echo ""
echo -e "${BOLD}  Grafana (after observability):${NC} kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo -e "${BOLD}  HTTPS (production add-on):${NC} see manifests/ingress-aws-https.example.yaml"
echo -e "${BOLD}  Tear down:${NC} make aws-down"
echo ""
