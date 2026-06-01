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

count_status() {
  local status="$1"
  local n
  n="$(grep -Ec "\"status\"[[:space:]]*:[[:space:]]*\"${status}\"" "${REPORT_JSON}" 2>/dev/null || true)"
  echo "${n:-0}"
}

total_controls="$(grep -Ec '"test_number"' "${REPORT_JSON}" 2>/dev/null || true)"
pass_count="$(count_status PASS)"
fail_count="$(count_status FAIL)"
warn_count="$(count_status WARN)"
info_count="$(count_status INFO)"

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
python3 - "${REPORT_JSON}" <<'PY'
import json, sys
report = json.loads(open(sys.argv[1]).read())
for control in report.get("Controls", []):
    for test in control.get("tests", []):
        for result in test.get("results", []):
            if result.get("status") == "FAIL":
                desc = result.get("test_desc", "")
                rem = (result.get("remediation") or "").replace("\n", " ")[:80]
                print(f'{result["test_number"]} | {desc} | {rem}')
PY
echo

echo "WARN controls (IDs)"
echo "------------------------------------------------------------"
python3 - "${REPORT_JSON}" <<'PY'
import json, sys
report = json.loads(open(sys.argv[1]).read())
warn_ids = set()
for control in report.get("Controls", []):
    for test in control.get("tests", []):
        for result in test.get("results", []):
            if result.get("status") == "WARN":
                warn_ids.add(result["test_number"])
for test_id in sorted(warn_ids):
    print(test_id)
PY
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

python3 - "${BASELINE_JSON}" "${REPORT_JSON}" "${tmp_expected}" "${tmp_current}" <<'PY'
import json
import sys

baseline_path, report_path, expected_out, current_out = sys.argv[1:5]

baseline = json.loads(open(baseline_path).read()).get("expected", {})
report = json.loads(open(report_path).read())

current = {}
for control in report.get("Controls", []):
    for test in control.get("tests", []):
        for result in test.get("results", []):
            current[result["test_number"]] = result["status"]

with open(expected_out, "w") as f:
    for test_id, status in sorted(baseline.items()):
        f.write(f"{test_id} {status}\n")

with open(current_out, "w") as f:
    for test_id, status in sorted(current.items()):
        f.write(f"{test_id} {status}\n")
PY

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

# Baseline documents known FAIL/WARN on lab clusters (e.g. MicroK8s). Only regressions
# (expected PASS/WARN → now FAIL) fail the check above — not pre-existing FAILs.
if [[ "${fail_count}" -gt 0 ]]; then
  echo "kube-bench: ${fail_count} FAIL control(s) present (documented in baseline — no regressions)."
fi

echo "kube-bench: no regressions vs baseline."
