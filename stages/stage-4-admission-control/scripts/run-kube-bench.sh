#!/usr/bin/env bash
set -euo pipefail

# Runs kube-bench against the live cluster and produces:
# - kube-bench-report.json (full JSON output from kube-bench)
# - human-readable summary (PASS/FAIL/WARN/INFO counts and details)
#
# This script intentionally uses bash-only parsing (no jq / no python) so it can
# run in minimal CI environments.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOB_YAML="${ROOT_DIR}/infra/kube-bench/kube-bench-job.yaml"
BASELINE_JSON="${ROOT_DIR}/scripts/kube-bench-baseline.json"
REPORT_JSON="${ROOT_DIR}/scripts/kube-bench-report.json"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found in PATH"
  exit 2
fi

echo "Applying kube-bench Job: ${JOB_YAML}"
kubectl apply -f "${JOB_YAML}" >/dev/null

echo "Waiting for Job completion (kube-system/job kube-bench)..."
kubectl -n kube-system wait --for=condition=complete job/kube-bench --timeout=10m >/dev/null

POD="$(kubectl -n kube-system get pods -l job-name=kube-bench -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${POD}" ]]; then
  echo "Could not find kube-bench pod"
  exit 2
fi

echo "Extracting JSON output to: ${REPORT_JSON}"
kubectl -n kube-system logs "${POD}" > "${REPORT_JSON}"

if [[ ! -s "${REPORT_JSON}" ]]; then
  echo "kube-bench report is empty: ${REPORT_JSON}"
  exit 2
fi

total_controls="$(grep -Eo '"test_number"\s*:\s*"[^"]+"' "${REPORT_JSON}" | wc -l | tr -d ' ')"
pass_count="$(grep -Eo '"status"\s*:\s*"PASS"' "${REPORT_JSON}" | wc -l | tr -d ' ')"
fail_count="$(grep -Eo '"status"\s*:\s*"FAIL"' "${REPORT_JSON}" | wc -l | tr -d ' ')"
warn_count="$(grep -Eo '"status"\s*:\s*"WARN"' "${REPORT_JSON}" | wc -l | tr -d ' ')"
info_count="$(grep -Eo '"status"\s*:\s*"INFO"' "${REPORT_JSON}" | wc -l | tr -d ' ')"

echo
echo "kube-bench summary"
echo "  Total controls: ${total_controls}"
echo "  PASS: ${pass_count}"
echo "  FAIL: ${fail_count}"
echo "  WARN: ${warn_count}"
echo "  INFO: ${info_count}"
echo

echo "FAIL controls (ID | description | remediation)"
echo "------------------------------------------------------------"
awk '
  BEGIN { id=""; desc=""; rem=""; status="" }
  /"test_number"[[:space:]]*:/ { if (match($0, /"test_number"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) id=m[1] }
  /"desc"[[:space:]]*:/        { if (match($0, /"desc"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) desc=m[1] }
  /"remediation"[[:space:]]*:/ { if (match($0, /"remediation"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) rem=m[1] }
  /"status"[[:space:]]*:/      {
    if (match($0, /"status"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) status=m[1]
    if (status == "FAIL" && id != "") {
      printf "%s | %s | %s\n", id, desc, rem
    }
  }
' "${REPORT_JSON}" || true
echo

echo "WARN controls (IDs)"
echo "------------------------------------------------------------"
awk '
  BEGIN { id=""; status="" }
  /"test_number"[[:space:]]*:/ { if (match($0, /"test_number"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) id=m[1] }
  /"status"[[:space:]]*:/      {
    if (match($0, /"status"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) status=m[1]
    if (status == "WARN" && id != "") {
      print id
    }
  }
' "${REPORT_JSON}" | sort -u || true
echo

if [[ ! -f "${BASELINE_JSON}" ]]; then
  echo "Baseline not found: ${BASELINE_JSON}"
  echo "Create it (commit to git) before using this in CI."
  exit 2
fi

# Compare current results against the baseline and fail if NEW FAILs appear.
echo "Comparing against baseline: ${BASELINE_JSON}"

tmp_expected="$(mktemp)"
tmp_current="$(mktemp)"
trap 'rm -f "$tmp_expected" "$tmp_current"' EXIT

# expected: "1.2.1": "PASS"
grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+"\s*:\s*"[A-Z]+"' "${BASELINE_JSON}" \
  | sed -E 's/"([0-9]+\.[0-9]+\.[0-9]+)"\s*:\s*"([A-Z]+)"/\1 \2/' \
  > "${tmp_expected}" || true

awk '
  BEGIN { id=""; status="" }
  /"test_number"[[:space:]]*:/ { if (match($0, /"test_number"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) id=m[1] }
  /"status"[[:space:]]*:/      {
    if (match($0, /"status"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) status=m[1]
    if (id != "" && status != "") {
      print id, status
    }
  }
' "${REPORT_JSON}" | sort -u > "${tmp_current}" || true

regressions=0
while read -r id expected_status; do
  [[ -z "${id}" ]] && continue
  current_status="$(awk -v id="${id}" '$1==id {print $2; exit}' "${tmp_current}" || true)"
  [[ -z "${current_status}" ]] && continue

  # Only fail on newly introduced FAILs vs the baseline expectation.
  if [[ "${current_status}" == "FAIL" && "${expected_status}" != "FAIL" ]]; then
    echo "REGRESSION: ${id} expected=${expected_status} now=FAIL"
    regressions=$((regressions + 1))
  fi
done < "${tmp_expected}"

if [[ "${regressions}" -gt 0 ]]; then
  echo
  echo "kube-bench regressions detected: ${regressions}"
  exit 1
fi

if [[ "${fail_count}" -gt 0 ]]; then
  echo
  echo "kube-bench FAIL controls present (baseline may allow them, but CI should track regressions)."
  exit 1
fi

echo "kube-bench: no FAILs and no regressions."
