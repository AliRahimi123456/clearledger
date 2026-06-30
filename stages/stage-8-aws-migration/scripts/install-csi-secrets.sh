#!/usr/bin/env bash
# Stage 8 — Install Secrets Store CSI Driver + AWS provider on EKS
#
# Use ONE Helm release: the AWS provider chart installs the CSI driver as a
# dependency. Do not also install secrets-store-csi-driver/secrets-store-csi-driver
# separately — both charts own the same ServiceAccount and Helm will fail.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CSI_MANIFESTS="${ROOT_DIR}/stages/stage-8-aws-migration/manifests/csi"

helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws >/dev/null 2>&1 || true
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts >/dev/null 2>&1 || true
helm repo update aws-secrets-manager secrets-store-csi-driver >/dev/null 2>&1 || true

AWS_PROVIDER_ARGS=(
  --namespace kube-system
  --set secrets-store-csi-driver.syncSecret.enabled=true
  --set secrets-store-csi-driver.enableSecretRotation=true
  --wait --timeout=300s
)

if helm status csi-secrets-store -n kube-system >/dev/null 2>&1 \
  && ! helm status secrets-provider-aws -n kube-system >/dev/null 2>&1; then
  echo "▶ CSI driver already installed as release csi-secrets-store — adding AWS provider only"
  echo "  (driver chart is a dependency of the AWS chart; skip duplicate install)"
  helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws \
    "${AWS_PROVIDER_ARGS[@]}" \
    --set secrets-store-csi-driver.install=false
elif helm status csi-secrets-store -n kube-system >/dev/null 2>&1 \
  && helm status secrets-provider-aws -n kube-system >/dev/null 2>&1; then
  echo "▶ Upgrading AWS provider (CSI driver from existing csi-secrets-store release)"
  helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws \
    "${AWS_PROVIDER_ARGS[@]}" \
    --set secrets-store-csi-driver.install=false
else
  echo "▶ Installing AWS Secrets Manager CSI provider (includes CSI driver)"
  helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws \
    "${AWS_PROVIDER_ARGS[@]}"
fi

echo "▶ Applying SecretProviderClass manifests..."
kubectl apply -f "${CSI_MANIFESTS}/"

echo "✓ CSI driver + AWS provider ready"
echo "  Verify: kubectl get pods -n kube-system -l app=secrets-store-csi-driver"
echo "  Verify: kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws"
echo "  Verify: kubectl get secretproviderclass -n clearledger"
