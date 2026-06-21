#!/usr/bin/env bash
# Build metrics-enabled ClearLedger images, sign with Cosign, roll out to the cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TAG="${METRICS_IMAGE_TAG:-metrics-stage7}"
DOCKER_USERNAME="${DOCKER_USERNAME:-}"

if [ -z "${DOCKER_USERNAME}" ]; then
  echo "✗ Set DOCKER_USERNAME (your Docker Hub user from Stage 1)."
  exit 1
fi

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "✗ Missing dependency: $1"
    exit 1
  }
}

require docker
require kubectl
require cosign

build_and_push() {
  local service="$1"
  local context="${ROOT_DIR}/app/${service}"
  local image="index.docker.io/${DOCKER_USERNAME}/clearledger-${service}:${TAG}"

  echo "▶ Building ${service}..."
  docker build -t "${image}" "${context}"
  docker push "${image}"

  if [ -n "${COSIGN_PRIVATE_KEY:-}" ] && [ -n "${COSIGN_PASSWORD:-}" ]; then
    echo "  Signing ${image}..."
    cosign sign --key env://COSIGN_PRIVATE_KEY --tlog-upload=false "${image}"
  elif [ -f "${ROOT_DIR}/infra/cosign.key" ]; then
    echo "  Signing ${image} with infra/cosign.key..."
    cosign sign --key "${ROOT_DIR}/infra/cosign.key" --tlog-upload=false "${image}"
  else
    echo "  ⚠ No Cosign key found — Kyverno may block unsigned images at rollout."
  fi

  kubectl -n clearledger set image "deployment/${service}" \
    "${service}=${image}"
}

for svc in auth-service ledger-service notification-service; do
  build_and_push "${svc}"
done

echo "▶ Waiting for rollouts..."
kubectl -n clearledger rollout status deployment/auth-service --timeout=300s
kubectl -n clearledger rollout status deployment/ledger-service --timeout=300s
kubectl -n clearledger rollout status deployment/notification-service --timeout=300s

echo ""
echo "✓ Metrics-enabled images deployed."
echo "  Verify: kubectl exec -n clearledger deploy/auth-service -c auth-service -- wget -qO- http://127.0.0.1:8000/metrics | head"
