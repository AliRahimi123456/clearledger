#!/usr/bin/env bash
# doctor.sh
# Disk health snapshot for the ClearLedger lab VM and cluster.

set -euo pipefail

VM_NAME="${VM_NAME:-clearledger}"
WARN_THRESHOLD=75
FAIL_THRESHOLD=90

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

if ! command -v multipass >/dev/null 2>&1; then
  echo "ERROR: multipass not found — install Multipass (https://multipass.run)" >&2
  exit 1
fi

if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
  echo "ERROR: Multipass VM '${VM_NAME}' not found — run make setup" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lab-env.sh"
lab_ensure_kubeconfig 2>/dev/null || true

echo ""
echo -e "${BOLD}ClearLedger disk doctor${NC}"
echo ""

# ── VM root filesystem ────────────────────────────────────────────────────────
disk_line=$(multipass exec "$VM_NAME" -- df -P / | awk 'NR==2 {print $2, $3, $4, $5}')
disk_total_kb=$(echo "$disk_line" | awk '{print $1}')
disk_used_kb=$(echo "$disk_line" | awk '{print $2}')
disk_avail_kb=$(echo "$disk_line" | awk '{print $3}')
disk_pct_raw=$(echo "$disk_line" | awk '{print $4}')
disk_pct="${disk_pct_raw%%%}"

disk_total_h=$(multipass exec "$VM_NAME" -- df -h / | awk 'NR==2 {print $2}')
disk_used_h=$(multipass exec "$VM_NAME" -- df -h / | awk 'NR==2 {print $3}')
disk_avail_h=$(multipass exec "$VM_NAME" -- df -h / | awk 'NR==2 {print $4}')

echo "VM disk (/) — ${disk_used_h} used / ${disk_total_h} total (${disk_pct}%), ${disk_avail_h} free"

# ── Top 5 namespaces by PVC requested storage ─────────────────────────────────
echo ""
echo "Top 5 namespaces by PVC requested storage:"
if command -v kubectl >/dev/null 2>&1 && kubectl get pvc -A >/dev/null 2>&1; then
  pvc_summary=$(
    kubectl get pvc -A -o json 2>/dev/null | python3 -c "
import json, sys, re
from collections import defaultdict

def parse_size(s):
    if not s:
        return 0
    m = re.match(r'^(\d+(?:\.\d+)?)(Ki|Mi|Gi|Ti|K|M|G|T)?$', str(s))
    if not m:
        return 0
    val = float(m.group(1))
    unit = m.group(2) or 'B'
    mult = {
        'Ki': 1024, 'Mi': 1024**2, 'Gi': 1024**3, 'Ti': 1024**4,
        'K': 1000, 'M': 1000**2, 'G': 1000**3, 'T': 1000**4,
    }
    return int(val * mult.get(unit, 1))

data = json.load(sys.stdin)
totals = defaultdict(int)
for item in data.get('items', []):
    ns = item['metadata']['namespace']
    cap = (item.get('status') or {}).get('capacity') or {}
    req = (item.get('spec') or {}).get('resources', {}).get('requests') or {}
    size = cap.get('storage') or req.get('storage') or '0'
    totals[ns] += parse_size(size)

if not totals:
    print('  (no PVCs found)')
else:
    ranked = sorted(totals.items(), key=lambda x: x[1], reverse=True)[:5]
    for ns, bytes_ in ranked:
        if bytes_ >= 1024**3:
            human = f'{bytes_ / 1024**3:.1f}Gi'
        elif bytes_ >= 1024**2:
            human = f'{bytes_ / 1024**2:.0f}Mi'
        else:
            human = f'{bytes_ / 1024:.0f}Ki'
        print(f'  {ns:<24} {human}')
" 2>/dev/null || true
  )
  if [ -n "$pvc_summary" ]; then
    echo "$pvc_summary"
  else
    echo "  (could not summarize PVCs — is python3 available?)"
  fi
else
  echo "  (kubectl unavailable or cluster not reachable)"
fi

# ── Prometheus TSDB size ──────────────────────────────────────────────────────
echo ""
echo -n "Prometheus TSDB size: "
if command -v kubectl >/dev/null 2>&1 && kubectl get ns monitoring >/dev/null 2>&1; then
  prom_pod=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$prom_pod" ]; then
    tsdb_size=$(kubectl exec -n monitoring "$prom_pod" -c prometheus -- \
      du -sh /prometheus 2>/dev/null | awk '{print $1}' || true)
    if [ -n "$tsdb_size" ]; then
      echo "$tsdb_size  (pod: ${prom_pod})"
    else
      echo "unknown (pod ${prom_pod} — could not read /prometheus)"
    fi
  else
    echo "not installed (no Prometheus pod in monitoring namespace)"
  fi
else
  echo "not installed (monitoring namespace missing or cluster unreachable)"
fi

# ── Verdict ───────────────────────────────────────────────────────────────────
echo ""
if [ "$disk_pct" -ge "$FAIL_THRESHOLD" ] 2>/dev/null; then
  echo -e "Disk health: ${RED}${BOLD}FAIL${NC} (${disk_pct}% used — critical)"
  echo "  Hint: run make reclaim"
  exit 2
elif [ "$disk_pct" -ge "$WARN_THRESHOLD" ] 2>/dev/null; then
  echo -e "Disk health: ${YELLOW}${BOLD}WARN${NC} (${disk_pct}% used — consider reclaiming)"
  echo "  Hint: run make reclaim"
  exit 1
else
  echo -e "Disk health: ${GREEN}${BOLD}PASS${NC} (${disk_pct}% used)"
  exit 0
fi
