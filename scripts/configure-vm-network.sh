#!/usr/bin/env bash
# configure-vm-network.sh
# Harden DNS on the Ubuntu host where MicroK8s and the self-hosted runner live.
# Idempotent — safe to re-run.
#
# Three entry points:
#   macOS (supported lab setup):
#     bash scripts/configure-vm-network.sh
#     -> detects the Multipass VM and applies the fix via multipass exec.
#   Linux (MicroK8s on the host):
#     bash scripts/configure-vm-network.sh --inside-vm
#   Windows (WSL2/Ubuntu running MicroK8s):
#     bash scripts/configure-vm-network.sh --inside-vm
#     (run inside WSL, on the same Ubuntu host as MicroK8s and Docker)
#
# setup-cluster.sh invokes the macOS path automatically during `make setup`.

set -euo pipefail

VM_NAME="${VM_NAME:-clearledger}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_SCRIPT="/tmp/clearledger-configure-vm-network.sh"

RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/clearledger.conf"
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
DOCKER_DNS='["1.1.1.1","8.8.8.8"]'

configure_inside_vm() {
  local resolved_changed=0 docker_changed=0
  local desired_resolved host_ok=1 container_ok=1

  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required but not installed." >&2
    exit 1
  fi

  desired_resolved='[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
'

  echo "==> [1/3] Pin systemd-resolved upstream (${RESOLVED_DROPIN})"
  sudo mkdir -p /etc/systemd/resolved.conf.d
  if [[ ! -f "${RESOLVED_DROPIN}" ]] || ! cmp -s <(printf '%s' "${desired_resolved}") "${RESOLVED_DROPIN}"; then
    printf '%s' "${desired_resolved}" | sudo tee "${RESOLVED_DROPIN}" >/dev/null
    resolved_changed=1
  else
    echo "    already configured"
  fi
  if [[ "${resolved_changed}" -eq 1 ]]; then
    sudo systemctl restart systemd-resolved
    sleep 2
  fi

  echo "==> [2/3] Pin Docker daemon resolver (${DOCKER_DAEMON_JSON})"
  docker_changed="$(
    sudo python3 - "${DOCKER_DAEMON_JSON}" "${DOCKER_DNS}" <<'PY'
import json, os, sys
path, dns_json = sys.argv[1], sys.argv[2]
dns = json.loads(dns_json)
data = {}
if os.path.isfile(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: {path} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)
if data.get("dns") == dns:
    print(0)
    sys.exit(0)
data["dns"] = dns
tmp = path + ".clearledger-new"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print(1)
PY
  )"
  if [[ "${docker_changed}" -eq 1 ]]; then
    sudo systemctl restart docker
    sleep 2
  else
    echo "    already configured"
  fi

  echo "==> [3/3] Verify host and container DNS"
  for host in github.com registry-1.docker.io files.pythonhosted.org archive.ubuntu.com; do
    if getent hosts "${host}" >/dev/null 2>&1; then
      echo "    ✓ host: ${host}"
    else
      echo "    ✗ host: ${host}" >&2
      host_ok=0
    fi
  done

  if docker run --rm alpine:3.20 getent hosts registry-1.docker.io >/dev/null 2>&1; then
    echo "    ✓ container: registry-1.docker.io"
  else
    echo "    ✗ container: registry-1.docker.io" >&2
    container_ok=0
  fi

  if [[ "${host_ok}" -eq 0 || "${container_ok}" -eq 0 ]]; then
    echo "" >&2
    echo "DNS verification failed — resolvectl status:" >&2
    resolvectl status 2>/dev/null || systemd-resolve --status 2>/dev/null || true
    exit 1
  fi

  echo ""
  echo "✓ VM network DNS configured"
}

dispatch_host() {
  if command -v multipass >/dev/null 2>&1 && multipass info "${VM_NAME}" >/dev/null 2>&1; then
    echo "==> Transfer configure-vm-network.sh to ${VM_NAME}"
    multipass transfer "${SCRIPT_DIR}/configure-vm-network.sh" "${VM_NAME}:${REMOTE_SCRIPT}"

    echo "==> Apply DNS configuration inside ${VM_NAME}"
    multipass exec "${VM_NAME}" -- bash "${REMOTE_SCRIPT}" --inside-vm

    echo "==> Cleanup"
    multipass exec "${VM_NAME}" -- rm -f "${REMOTE_SCRIPT}"
    return 0
  fi

  cat <<EOF
No Multipass VM detected. If MicroK8s runs directly on THIS host
(Linux, or Windows via WSL2/Ubuntu), apply the fix locally with:

  bash scripts/configure-vm-network.sh --inside-vm

ClearLedger provisioning uses Mac + Multipass (make setup). Linux and Windows
readers provision their own MicroK8s host, then run --inside-vm on that host.
EOF
  exit 0
}

if [[ "${1:-}" == "--inside-vm" ]]; then
  configure_inside_vm
else
  dispatch_host
fi
