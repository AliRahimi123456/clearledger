#!/usr/bin/env bash
# Vault setup script for ClearLedger — Stage 5
# Run this once after Vault is installed and reachable.
# All commands exec into the vault-0 pod directly.

set -euo pipefail

VAULT_POD="vault-0"
VAULT_NS="vault"
VAULT_TOKEN="root-dev-token"

echo "==> Logging into Vault..."
kubectl exec -n $VAULT_NS $VAULT_POD -- vault login $VAULT_TOKEN

echo "==> Enabling Kubernetes auth method..."
kubectl exec -n $VAULT_NS $VAULT_POD -- vault auth enable kubernetes || true

echo "==> Configuring Kubernetes auth..."
kubectl exec -n $VAULT_NS $VAULT_POD -- \
  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

echo "==> Enabling KV secrets engine..."
kubectl exec -n $VAULT_NS $VAULT_POD -- \
  vault secrets enable -path=clearledger kv-v2 || true

echo "==> Storing auth-service secrets..."
kubectl exec -n $VAULT_NS $VAULT_POD -- \
  vault kv put clearledger/auth-service \
    database_url="postgresql://clearledger:changeme-vault@postgres:5432/clearledger" \
    jwt_secret="vault-managed-jwt-secret-replace-in-production"

echo "==> Storing ledger-service secrets..."
kubectl exec -n $VAULT_NS $VAULT_POD -- \
  vault kv put clearledger/ledger-service \
    database_url="postgresql://clearledger:changeme-vault@postgres:5432/clearledger"

echo "==> Creating Vault policies..."
kubectl exec -n $VAULT_NS $VAULT_POD -- vault policy write auth-service - <<'EOF'
path "clearledger/data/auth-service" {
  capabilities = ["read"]
}
EOF

kubectl exec -n $VAULT_NS $VAULT_POD -- vault policy write ledger-service - <<'EOF'
path "clearledger/data/ledger-service" {
  capabilities = ["read"]
}
EOF

echo "==> Creating Kubernetes auth roles..."
kubectl exec -n $VAULT_NS $VAULT_POD -- \
  vault write auth/kubernetes/role/auth-service \
    bound_service_account_names=auth-service \
    bound_service_account_namespaces=clearledger \
    policies=auth-service \
    ttl=1h

kubectl exec -n $VAULT_NS $VAULT_POD -- \
  vault write auth/kubernetes/role/ledger-service \
    bound_service_account_names=ledger-service \
    bound_service_account_namespaces=clearledger \
    policies=ledger-service \
    ttl=1h

echo "==> Applying RBAC + ServiceAccounts (infra/manifests/rbac/rbac.yaml)..."
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
kubectl apply -f "$REPO_ROOT/infra/manifests/rbac/rbac.yaml"

echo ""
echo "✓ Vault setup complete."
echo ""
echo "Next steps:"
echo "  1. Update the passwords above with real generated values"
echo "  2. Apply updated deployments: kubectl apply -f stages/stage-5-secrets-management/infra/manifests/"
echo "  3. Delete old K8s Secrets: kubectl delete secret auth-service-secret ledger-service-secret -n clearledger"
