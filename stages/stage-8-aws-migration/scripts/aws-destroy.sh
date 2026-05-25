#!/usr/bin/env bash
# chmod +x stages/stage-8-aws-migration/scripts/aws-destroy.sh
#
# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: Tear down all ClearLedger AWS resources cleanly and safely.
#          Kubernetes resources are deleted first to allow the ALB controller
#          to deregister load balancers before Terraform destroys the VPC —
#          skipping this step causes dependency errors in terraform destroy.
#
# Usage: bash stages/stage-8-aws-migration/scripts/aws-destroy.sh
# Run from the repository root.

set -euo pipefail

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

# ── 1. Confirmation prompt ────────────────────────────────────────────────────
banner "ClearLedger AWS Teardown"

echo ""
echo -e "${RED}${BOLD}  WARNING: This will permanently destroy all ClearLedger AWS resources.${NC}"
echo ""
echo "  Resources to be destroyed:"
echo "    • EKS cluster and all node groups"
echo "    • ECR repositories and all images"
echo "    • RDS PostgreSQL instance (no final snapshot — lab configuration)"
echo "    • Secrets Manager secrets (7-day recovery window applies)"
echo "    • VPC, subnets, NAT Gateway, and all networking"
echo "    • IAM roles created by this lab"
echo ""
echo -e "${YELLOW}  AWS billing will stop after this completes.${NC}"
echo ""
read -rp "Type 'destroy' to confirm: " confirm

if [[ "$confirm" != "destroy" ]]; then
  echo ""
  echo "Aborted — you did not type 'destroy' exactly."
  exit 0
fi

echo ""

# ── 2. Delete Kubernetes resources first ──────────────────────────────────────
banner "Step 1 of 4 — Removing Kubernetes resources"

# Why: the ALB Ingress controller creates AWS load balancers when Ingress objects
# exist. If we destroy the VPC before deleting the Ingress, the ALB's security
# group may still be attached to the VPC, causing Terraform to fail.

if kubectl cluster-info &>/dev/null 2>&1; then
  echo "→  Deleting Ingress (triggers ALB deregistration)..."
  kubectl delete ingress clearledger-ingress -n clearledger --ignore-not-found

  echo "→  Deleting application namespaces..."
  kubectl delete namespace clearledger      --ignore-not-found
  kubectl delete namespace argocd           --ignore-not-found
  kubectl delete namespace kyverno          --ignore-not-found
  kubectl delete namespace falco            --ignore-not-found
  kubectl delete namespace external-secrets --ignore-not-found

  echo ""
  echo -e "${YELLOW}→  Waiting 30 seconds for ALB to deregister from target groups...${NC}"
  echo "   (Skipping this wait risks 'DependencyViolation' errors in Terraform)"
  sleep 30
  echo -e "${GREEN}✓  Kubernetes resources removed${NC}"
else
  echo -e "${YELLOW}⚠  kubectl cannot reach the cluster (may already be destroyed). Skipping.${NC}"
fi

# ── 3. Terraform destroy ───────────────────────────────────────────────────────
banner "Step 2 of 4 — Terraform destroy"

echo "→  Running terraform destroy..."
cd "$TF_DIR"
terraform destroy -auto-approve
cd "$REPO_ROOT"

echo -e "${GREEN}✓  Terraform destroy complete${NC}"

# ── 4. Clean up local kubeconfig ──────────────────────────────────────────────
banner "Step 3 of 4 — Cleaning up local kubeconfig"

# Determine the EKS context name (format: arn:aws:eks:REGION:ACCOUNT:cluster/NAME)
aws_region=$(aws configure get region 2>/dev/null || echo "eu-west-1")
aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [[ -n "$aws_account" ]]; then
  eks_context="arn:aws:eks:${aws_region}:${aws_account}:cluster/clearledger"
  if kubectl config get-contexts "$eks_context" &>/dev/null 2>&1; then
    kubectl config delete-context "$eks_context"
    echo -e "${GREEN}✓  Removed kubeconfig context: ${eks_context}${NC}"
  else
    echo "   Context not found in kubeconfig (may have already been removed)."
  fi
else
  echo -e "${YELLOW}⚠  Could not determine account ID — kubeconfig context not removed.${NC}"
  echo "   Remove manually: kubectl config delete-context <arn:aws:eks:...>"
fi

# ── 5. Confirmation ───────────────────────────────────────────────────────────
banner "Step 4 of 4 — Done"

echo ""
echo -e "${GREEN}${BOLD}  ClearLedger AWS infrastructure destroyed.${NC}"
echo -e "${GREEN}  No further AWS charges will accrue for these resources.${NC}"
echo ""
echo "  Notes:"
echo "    • Secrets Manager secrets have a 7-day recovery window."
echo "      To delete immediately: aws secretsmanager delete-secret \\"
echo "        --secret-id clearledger/postgres --force-delete-without-recovery"
echo ""
echo "    • ECR images were not deleted by Terraform (lifecycle policy handles them)."
echo "      To force-delete: aws ecr delete-repository --repository-name clearledger/auth-service --force"
echo ""
