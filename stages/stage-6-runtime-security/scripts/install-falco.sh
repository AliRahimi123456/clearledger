#!/usr/bin/env bash
# Install Falco + Falcosidekick UI for ClearLedger Stage 6
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="${ROOT_DIR}/infra/falco/clearledger-rules-content.yaml"
VALUES="${STAGE_DIR}/infra/falco/helm-values.yaml"
TMP_VALUES="$(mktemp)"

helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo update falcosecurity

{
  cat "${VALUES}"
  echo "customRules:"
  echo "  clearledger_rules.yaml: |"
  grep -v '^#' "${RULES}" | sed '/^$/d' | sed 's/^/    /'
} > "${TMP_VALUES}"

helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  -f "${TMP_VALUES}" \
  --wait --timeout 5m

rm -f "${TMP_VALUES}"

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=falco -n falco --timeout=180s

kubectl apply -f "${ROOT_DIR}/infra/falco/clearledger-rules.yaml"
kubectl apply -f "${STAGE_DIR}/infra/falco-ingress.yaml"

echo "✓ Falco installed — UI at http://falco.local"
echo "  Login: admin  Password: admin  (Falcosidekick chart default)"
echo ""
echo "  Guided demo (UI + terminal): bash stages/stage-6-runtime-security/scripts/demo-falco-alerts.sh"
