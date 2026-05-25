#!/usr/bin/env bash
set -euo pipefail

# Secret rotation demo: JWT secret rotation with zero pod restarts and zero downtime.
# This uses Vault KV v2 versioning + Vault agent template refresh inside the running pod.
#
# Requirements:
# - Vault running in namespace "vault" with dev token already logged in on vault-0
# - auth-service deployed with Vault agent injection (Stage 5 deployment)
# - clearledger ingress reachable at http://clearledger.local

BASE_URL="${BASE_URL:-http://clearledger.local}"
VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_NS="${VAULT_NS:-vault}"
AUTH_NS="${AUTH_NS:-clearledger}"

step() { echo; echo "==> $1"; }
die() { echo "ERROR: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || die "kubectl not found"
command -v openssl >/dev/null 2>&1 || die "openssl not found"
command -v curl >/dev/null 2>&1 || die "curl not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

vault() {
  kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -c vault -- vault "$@"
}

step "Step 1 — Show current secret value (redacted)"
current_json="$(vault kv get -format=json clearledger/auth-service)" || die "vault kv get failed"
CURRENT_JWT="$(python3 - <<'PY'
import json,sys
d=json.loads(sys.stdin.read())
print(d["data"]["data"]["jwt_secret"])
PY
<<<"${current_json}")"
CURRENT_DB="$(python3 - <<'PY'
import json,sys
d=json.loads(sys.stdin.read())
print(d["data"]["data"]["database_url"])
PY
<<<"${current_json}")"
echo "Current jwt_secret: ${CURRENT_JWT:0:10}***"

step "Step 2 — Generate a new JWT secret"
NEW_SECRET="$(openssl rand -base64 64)"
echo "Generated new jwt_secret: ${NEW_SECRET:0:10}***"

step "Step 3 — Write the new version to Vault"
#
# IMPORTANT: To avoid breaking already-issued tokens, we keep a short overlap window:
# we write BOTH new and old secrets into the injected file (newline separated).
# The auth-service signs new tokens with the first value and verifies with either.
#
# In production, you would remove the old secret after your token TTL window expires.
ROTATED_VALUE="${NEW_SECRET}"$'\n'"${CURRENT_JWT}"
vault kv put clearledger/auth-service \
  database_url="${CURRENT_DB}" \
  jwt_secret="${ROTATED_VALUE}" >/dev/null || die "vault kv put failed"
echo "Vault write OK"

step "Step 4 — Show Vault has two versions now"
vault kv metadata get clearledger/auth-service || die "vault kv metadata get failed"

step "Step 5 — Wait for Vault agent to pick up the new version"
echo "Waiting 65 seconds for Vault agent renewal cycle..."
sleep 65

step "Step 6 — Verify the running pod now has the new secret (no restart)"
AUTH_POD="$(kubectl get pod -n "${AUTH_NS}" -l app=auth-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "${AUTH_POD}" ]] || die "Could not find auth-service pod in namespace ${AUTH_NS}"
POD_PREFIX="$(kubectl exec -n "${AUTH_NS}" "${AUTH_POD}" -c auth-service -- sh -lc 'cat /vault/secrets/jwt_secret | head -1 | cut -c1-10' 2>/dev/null || true)"
[[ -n "${POD_PREFIX}" ]] || die "Could not read /vault/secrets/jwt_secret from pod ${AUTH_POD}"
echo "Pod jwt_secret prefix: ${POD_PREFIX}***"
echo "New jwt_secret prefix: ${NEW_SECRET:0:10}***"
[[ "${POD_PREFIX}" == "${NEW_SECRET:0:10}" ]] || die "Pod did not pick up new secret"

step "Step 7 — Verify the API still works with the new secret"
login_payload='{"email":"test@clearledger.io","password":"SecurePass123"}'
echo "Login (new token) ..."
TOKEN_NEW="$(curl -fsS -X POST "${BASE_URL}/auth/login" -H 'Content-Type: application/json' -d "${login_payload}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')" || die "login failed"
curl -fsS "${BASE_URL}/auth/verify" -H "Authorization: Bearer ${TOKEN_NEW}" >/dev/null || die "verify failed for new token"
echo "New login + verify OK"

step "Step 8 — Show the old version is still in Vault (rollback available)"
vault kv get -version=1 clearledger/auth-service || die "vault kv get -version=1 failed"

step "Step 9 — Summary"
cat <<EOF
Secret rotated. Zero pod restarts. Zero downtime.
Old version retained by Vault KV history (retention configurable).
Rollback example:
  kubectl exec -n ${VAULT_NS} ${VAULT_POD} -c vault -- vault kv rollback -version=1 clearledger/auth-service

Note: We wrote both NEW and OLD jwt_secret values for an overlap window so existing tokens remain valid.
After your token TTL expires, rotate again and write only the new secret.
EOF

