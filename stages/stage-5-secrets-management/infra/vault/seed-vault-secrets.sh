#!/usr/bin/env bash
# Write application secrets into Vault KV from .env (gitignored).
# Values live in Vault after this — not in scripts, manifests, or Git.

set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${STAGE_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Missing $ENV_FILE"
  echo "  cp stages/stage-5-secrets-management/.env.example stages/stage-5-secrets-management/.env"
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

for var in VAULT_TOKEN SEED_AUTH_DATABASE_URL SEED_AUTH_JWT_SECRET SEED_LEDGER_DATABASE_URL; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

VAULT_POD="vault-0"
VAULT_NS="vault"

echo "==> Logging into Vault..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- vault login "$VAULT_TOKEN" >/dev/null

echo "==> Writing secrets to Vault KV (values are not printed)..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  vault kv put clearledger/auth-service \
    database_url="$SEED_AUTH_DATABASE_URL" \
    jwt_secret="$SEED_AUTH_JWT_SECRET"

kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  vault kv put clearledger/ledger-service \
    database_url="$SEED_LEDGER_DATABASE_URL"

echo "✓ Secrets stored at clearledger/data/auth-service and clearledger/data/ledger-service"
echo "  Verify metadata only: kubectl exec -n vault vault-0 -- vault kv metadata get clearledger/auth-service"
