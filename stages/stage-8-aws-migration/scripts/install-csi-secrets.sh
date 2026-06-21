#!/usr/bin/env bash
# Stage 8 — Install Secrets Store CSI Driver + AWS provider on EKS
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CSI_MANIFESTS="${ROOT_DIR}/stages/stage-8-aws-migration/manifests/csi"

echo "▶ Installing Secrets Store CSI Driver..."
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts >/dev/null 2>&1 || true
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  --wait --timeout=300s

echo "▶ Installing AWS Secrets Manager CSI provider..."
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws >/dev/null 2>&1 || true
helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws \
  --namespace kube-system \
  --wait --timeout=300s

echo "▶ Applying SecretProviderClass manifests..."
kubectl apply -f "${CSI_MANIFESTS}/"

echo "✓ CSI driver + AWS provider ready"
echo "  Verify: kubectl get pods -n kube-system -l app=secrets-store-csi-driver"
echo "  Verify: kubectl get secretproviderclass -n clearledger"
