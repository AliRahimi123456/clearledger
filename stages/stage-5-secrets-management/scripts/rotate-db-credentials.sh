#!/usr/bin/env bash
set -euo pipefail

# Database credential rotation demo (stateful rotation).
# Correct order matters:
#   create new user -> update Vault -> wait for agent refresh -> drop old user -> rename
#
# If done wrong:
# - Update Vault before creating the DB user: app gets new URL, DB rejects it (outage).
# - Drop old user before Vault agent refresh: brief outage window.

BASE_URL="${BASE_URL:-http://clearledger.local}"
VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_NS="${VAULT_NS:-vault}"
APP_NS="${APP_NS:-clearledger}"
PG_POD="${PG_POD:-postgres-0}"

step() { echo; echo "==> $1"; }
die() { echo "ERROR: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || die "kubectl not found"
command -v curl >/dev/null 2>&1 || die "curl not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

vault() {
  kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -c vault -- vault "$@"
}

step "Step 1 — Current state: show database_url in Vault (redacted)"
current_json="$(vault kv get -format=json clearledger/auth-service)" || die "vault kv get failed"
CURRENT_DB="$(python3 - <<'PY'
import json,sys
d=json.loads(sys.stdin.read())
print(d["data"]["data"]["database_url"])
PY
<<<"${current_json}")"
CURRENT_JWT="$(python3 - <<'PY'
import json,sys
d=json.loads(sys.stdin.read())
print(d["data"]["data"]["jwt_secret"])
PY
<<<"${current_json}")"
echo "Current database_url prefix: ${CURRENT_DB:0:25}***"

step "Step 2 — Create new database user in Postgres"
NEW_PASS="$(python3 -c 'import secrets; print(secrets.token_urlsafe(18))')"
echo "Creating clearledger_v2 user (password redacted)"

kubectl exec -n "${APP_NS}" "${PG_POD}" -c postgres -- psql \
  -U clearledger -d clearledger \
  -c "CREATE USER clearledger_v2 WITH PASSWORD '${NEW_PASS}';" || die "CREATE USER failed"

kubectl exec -n "${APP_NS}" "${PG_POD}" -c postgres -- psql \
  -U clearledger -d clearledger \
  -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO clearledger_v2;" || die "GRANT failed"

step "Step 3 — Update Vault with new credentials"
NEW_DB_URL="postgresql://clearledger_v2:${NEW_PASS}@postgres:5432/clearledger"
vault kv put clearledger/auth-service \
  database_url="${NEW_DB_URL}" \
  jwt_secret="${CURRENT_JWT}" >/dev/null || die "vault kv put failed"
echo "Vault updated"

step "Step 4 — Wait for Vault agent renewal"
echo "Waiting 65 seconds for Vault agent renewal cycle..."
sleep 65

step "Step 5 — Verify new credentials work (API still responds)"
curl -fsS "${BASE_URL}/auth/health" >/dev/null || die "auth health failed after DB URL update"
echo "auth /health OK"

step "Step 6 — Remove old database user and rename v2 to clearledger"
kubectl exec -n "${APP_NS}" "${PG_POD}" -c postgres -- psql \
  -U clearledger -d clearledger \
  -c "DROP USER clearledger;" || die "DROP USER clearledger failed"

kubectl exec -n "${APP_NS}" "${PG_POD}" -c postgres -- psql \
  -U clearledger_v2 -d clearledger \
  -c "ALTER USER clearledger_v2 RENAME TO clearledger;" || die "ALTER USER rename failed"

step "Step 7 — Verify the API still works end-to-end"
curl -fsS "${BASE_URL}/auth/health" >/dev/null || die "auth health failed after user swap"
echo "auth /health OK"

cat <<EOF

DB credentials rotated with an overlap window.
If any step failed, stop and rollback by restoring the previous Vault database_url.
Correct order matters:
  create new -> update Vault -> wait -> drop old

EOF
