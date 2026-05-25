#!/usr/bin/env bash
set -euo pipefail

# Enable Kubernetes API audit logging on the MicroK8s VM (Multipass).
#
# Audit logs capture API server calls: every kubectl command, every Secret read,
# every pod creation. For fintech, this is SOC2 + PCI-DSS evidence.
#
# Production note (PCI-DSS 10.7 retention): this lab uses 30 days (maxage=30)
# and small local rotation. Production needs longer-term storage (e.g., S3).

VM_NAME="${VM_NAME:-clearledger}"
POLICY_SRC="infra/audit/audit-policy.yaml"
POLICY_TMP="/tmp/audit-policy.yaml"
MICROK8S_ARGS_DIR="/var/snap/microk8s/current/args"
APISERVER_ARGS="${MICROK8S_ARGS_DIR}/kube-apiserver"
AUDIT_POLICY_DST="${MICROK8S_ARGS_DIR}/audit-policy.yaml"
AUDIT_LOG_PATH="/var/log/kubernetes/audit.log"

if ! command -v multipass >/dev/null 2>&1; then
  echo "multipass not found"
  exit 2
fi

if [[ ! -f "${POLICY_SRC}" ]]; then
  echo "Audit policy not found: ${POLICY_SRC}"
  exit 2
fi

echo "1) Transfer audit policy to VM (${VM_NAME})"
multipass transfer "${POLICY_SRC}" "${VM_NAME}:${POLICY_TMP}"

echo "2) Move policy into MicroK8s args directory"
multipass exec "${VM_NAME}" -- sudo mv "${POLICY_TMP}" "${AUDIT_POLICY_DST}"

echo "3) Add audit flags to kube-apiserver args"
multipass exec "${VM_NAME}" -- bash -lc "sudo grep -q -- '--audit-policy-file=' '${APISERVER_ARGS}' || echo '--audit-policy-file=${AUDIT_POLICY_DST}' | sudo tee -a '${APISERVER_ARGS}' >/dev/null"
multipass exec "${VM_NAME}" -- bash -lc "sudo grep -q -- '--audit-log-path=' '${APISERVER_ARGS}' || echo '--audit-log-path=${AUDIT_LOG_PATH}' | sudo tee -a '${APISERVER_ARGS}' >/dev/null"
multipass exec "${VM_NAME}" -- bash -lc "sudo grep -q -- '--audit-log-maxage=' '${APISERVER_ARGS}' || echo '--audit-log-maxage=30' | sudo tee -a '${APISERVER_ARGS}' >/dev/null"
multipass exec "${VM_NAME}" -- bash -lc "sudo grep -q -- '--audit-log-maxbackup=' '${APISERVER_ARGS}' || echo '--audit-log-maxbackup=5' | sudo tee -a '${APISERVER_ARGS}' >/dev/null"
multipass exec "${VM_NAME}" -- bash -lc "sudo grep -q -- '--audit-log-maxsize=' '${APISERVER_ARGS}' || echo '--audit-log-maxsize=100' | sudo tee -a '${APISERVER_ARGS}' >/dev/null"

echo "4) Restart MicroK8s"
multipass exec "${VM_NAME}" -- sudo microk8s stop
multipass exec "${VM_NAME}" -- sudo microk8s start

echo "5) Wait for cluster to be ready"
multipass exec "${VM_NAME}" -- sudo microk8s status --wait-ready

echo "6) Verify audit logs are being written (${AUDIT_LOG_PATH})"
multipass exec "${VM_NAME}" -- sudo tail -5 "${AUDIT_LOG_PATH}"

cat <<'EKS_NOTE'

EKS equivalent (Terraform) example:

  # in eks.tf
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

EKS_NOTE
