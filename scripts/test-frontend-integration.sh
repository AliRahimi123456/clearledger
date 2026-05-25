#!/usr/bin/env bash
# End-to-end test: frontend UI routes + real API connectivity (register, login, tx, alerts).
set -euo pipefail

BASE="${BASE_URL:-http://localhost:3000}"
EMAIL="uitest-$(date +%s)@clearledger.io"
PASS="TestPass1234!"

echo "=== ClearLedger frontend integration test ==="
echo "Base URL: $BASE"
echo ""

pass=0
fail=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "  PASS: $name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $name"
    fail=$((fail + 1))
  fi
}

# 1. Static assets served
check "index.html served" bash -c "curl -sf '$BASE/' | grep -q ClearLedger"
check "app.js served" bash -c "curl -sf '$BASE/app.js' | grep -q 'function api'"
check "style.css served" bash -c "curl -sf '$BASE/style.css' | grep -q dashboard"

# 2. Register
REG=$(curl -sf -X POST "$BASE/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
check "register API" bash -c "echo '$REG' | grep -q '$EMAIL'"

# 3. Login
LOGIN=$(curl -sf -X POST "$BASE/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
TOKEN=$(echo "$LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
check "login returns token" test -n "$TOKEN"

# 4. Verify token
VERIFY=$(curl -sf "$BASE/auth/verify" -H "Authorization: Bearer $TOKEN")
check "verify token" python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d.get('valid') else 1)" "$VERIFY"

# 5. Create credit transaction
curl -sf -X POST "$BASE/ledger/transactions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":5000,"direction":"credit","description":"Salary"}' > /dev/null
check "create credit tx" test $? -eq 0

# 6. Create large debit (triggers alert)
curl -sf -X POST "$BASE/ledger/transactions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":12000,"direction":"debit","description":"Equipment"}' > /dev/null
check "create large debit tx" test $? -eq 0

# 7. Balance
BAL=$(curl -sf "$BASE/ledger/balance" -H "Authorization: Bearer $TOKEN")
check "balance is -7000" bash -c "echo '$BAL' | python3 -c \"import json,sys; b=json.load(sys.stdin)['balance']; sys.exit(0 if b == -7000 else 1)\""

# 8. Transaction list
TXS=$(curl -sf "$BASE/ledger/transactions" -H "Authorization: Bearer $TOKEN")
check "2 transactions listed" bash -c "echo '$TXS' | python3 -c \"import json,sys; sys.exit(0 if len(json.load(sys.stdin)) == 2 else 1)\""

# 9. Alerts (notification service may need a moment for redis pub/sub)
sleep 2
ALERTS=$(curl -sf "$BASE/notifications/alerts")
check "large transaction alert" bash -c "echo '$ALERTS' | grep -q LARGE_TRANSACTION"

# 10. 401 on bad token
check "401 on bad token" bash -c "curl -sf -o /dev/null -w '%{http_code}' '$BASE/ledger/balance' -H 'Authorization: Bearer badtoken' | grep -q 401"

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "All checks passed — UI connects to live APIs."
