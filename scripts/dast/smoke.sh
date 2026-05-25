#!/usr/bin/env bash
# ClearLedger DAST smoke — runtime checks against a live ingress URL.
# SAST cannot see auth bypasses, BOLA, or broken routing; this is a minimal DAST gate.
#
# Usage:
#   BASE_URL=http://clearledger.local ./scripts/dast/smoke.sh
#   # or (ALB)
#   BASE_URL=http://k8s-clearledger-1234567890.eu-west-1.elb.amazonaws.com ./scripts/dast/smoke.sh
set -euo pipefail

BASE_URL="${BASE_URL:-${DAST_BASE_URL:-}}"
if [[ -z "${BASE_URL}" ]]; then
  echo "error: set BASE_URL (or DAST_BASE_URL) to your ingress root, e.g. http://clearledger.local" >&2
  exit 1
fi

BASE_URL="${BASE_URL%/}"

code() {
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$@" || echo "000"
}

echo "== DAST smoke against ${BASE_URL} =="

h="$(code "${BASE_URL}/auth/health")"
echo "GET /auth/health -> ${h}"
if [[ "${h}" != "200" ]]; then
  echo "fail: expected 200 from auth health" >&2
  exit 1
fi

h="$(code "${BASE_URL}/ledger/health")"
echo "GET /ledger/health -> ${h}"
if [[ "${h}" != "200" ]]; then
  echo "fail: expected 200 from ledger health" >&2
  exit 1
fi

h="$(code "${BASE_URL}/notifications/health")"
echo "GET /notifications/health -> ${h}"
if [[ "${h}" != "200" ]]; then
  echo "fail: expected 200 from notifications health" >&2
  exit 1
fi

# Protected route — malformed JWT must not return 200
h="$(code -H "Authorization: Bearer invalid.token.here" "${BASE_URL}/auth/verify")"
echo "GET /auth/verify (malformed JWT) -> ${h}"
if [[ "${h}" == "200" ]]; then
  echo "fail: verify with bad token must not succeed with HTTP 200" >&2
  exit 1
fi

h="$(code "${BASE_URL}/auth/verify")"
echo "GET /auth/verify (no Authorization header) -> ${h}"
if [[ "${h}" == "200" ]]; then
  echo "fail: unauthenticated verify must not return 200" >&2
  exit 1
fi

# Syntactically valid JWT with wrong signature — must not authorize
h="$(code -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJvdGhlci11c2VyIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" \
  "${BASE_URL}/auth/verify")"
echo "GET /auth/verify (forged JWT structure) -> ${h}"
if [[ "${h}" == "200" ]]; then
  echo "fail: forged JWT must not return 200" >&2
  exit 1
fi

echo "== DAST smoke passed =="
