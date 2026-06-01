#!/usr/bin/env bash
# Vault platform setup — Stage 5 (no application secrets in this file)
#
# Enables K8s auth, KV engine, policies, and roles. Application credentials
# belong in Vault KV only — load them with seed-vault-secrets.sh after editing .env

set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${STAGE_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "ERROR: VAULT_TOKEN is not set."
  echo "  cp stages/stage-5-secrets-management/.env.example stages/stage-5-secrets-management/.env"
  echo "  # set VAULT_TOKEN to the dev token you used at helm install"
  exit 1
fi

VAULT_POD="vault-0"
VAULT_NS="vault"
NAMESPACE="${CLEARLEDGER_NS:-clearledger}"

echo "==> Logging into Vault..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- vault login "$VAULT_TOKEN" >/dev/null

echo "==> Enabling Kubernetes auth method..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- vault auth enable kubernetes 2>/dev/null || true

echo "==> Configuring Kubernetes auth..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

echo "==> Enabling KV secrets engine..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  vault secrets enable -path=clearledger kv-v2 2>/dev/null || true

echo "==> Creating Vault policies..."
kubectl exec -i -n "$VAULT_NS" "$VAULT_POD" -- vault policy write auth-service - <<'EOF'
path "clearledger/data/auth-service" {
  capabilities = ["read"]
}
EOF

kubectl exec -i -n "$VAULT_NS" "$VAULT_POD" -- vault policy write ledger-service - <<'EOF'
path "clearledger/data/ledger-service" {
  capabilities = ["read"]
}
EOF

echo "==> Creating Kubernetes auth roles..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  vault write auth/kubernetes/role/auth-service \
    bound_service_account_names=auth-service \
    bound_service_account_namespaces="$NAMESPACE" \
    policies=auth-service \
    ttl=1h

kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  vault write auth/kubernetes/role/ledger-service \
    bound_service_account_names=ledger-service \
    bound_service_account_namespaces="$NAMESPACE" \
    policies=ledger-service \
    ttl=1h

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
echo "==> Applying RBAC + ServiceAccounts..."
kubectl apply -f "$REPO_ROOT/infra/manifests/rbac/rbac.yaml"

echo ""
echo "✓ Vault platform setup complete (no secrets written yet)."
echo "  Next: bash stages/stage-5-secrets-management/infra/vault/seed-vault-secrets.sh"
