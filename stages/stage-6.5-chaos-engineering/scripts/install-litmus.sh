#!/usr/bin/env bash
# Install LitmusChaos: operator + experiments + ChaosCenter UI for Stage 6.5
set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAOS_DIR="${STAGE_DIR}/infra/chaos"

helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ 2>/dev/null || true
helm repo update litmuschaos

kubectl apply -f "${CHAOS_DIR}/litmus-install.yaml"
kubectl apply -f "${CHAOS_DIR}/litmus-rbac.yaml"

echo "Installing Litmus chaos operator (litmus-core)..."
helm upgrade --install litmus-core litmuschaos/litmus-core \
  --namespace litmus \
  --wait --timeout 5m

echo "Installing Kubernetes chaos experiments (pod-delete, network-latency, memory-hog)..."
helm upgrade --install litmus-k8s litmuschaos/kubernetes-chaos \
  --namespace litmus \
  --set environment.runtime=containerd \
  --set environment.socketPath=/run/containerd/containerd.sock \
  --wait --timeout 5m

echo "Installing Litmus ChaosCenter UI (may take 3–5 min — MongoDB startup)..."
helm upgrade --install chaos litmuschaos/litmus \
  --namespace litmus \
  -f "${CHAOS_DIR}/litmus-values.yaml" \
  --wait --timeout 10m

kubectl apply -f "${CHAOS_DIR}/litmus-ingress.yaml"

# Ensure GraphQL server knows traffic arrives via ingress (/backend/ prefix)
kubectl set env deployment/chaos-litmus-server -n litmus \
  --containers=graphql-server \
  INGRESS=true INGRESS_NAME=litmus-ingress 2>/dev/null || true

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=litmus-frontend -n litmus --timeout=300s 2>/dev/null || \
  kubectl wait --for=condition=ready pod \
  -l app=litmus -n litmus --timeout=180s

echo ""
echo "Connecting this cluster to the Litmus UI (fixes empty Overview)…"
echo "  (Set LITMUS_PASSWORD if you changed the default from 'litmus')"
bash "${STAGE_DIR}/scripts/connect-litmus-infra.sh"

echo ""
echo "✓ LitmusChaos ready — open http://litmus.local and follow LAB-GUIDE §6.5.2 (UI walkthrough)"
