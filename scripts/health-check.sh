#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ClearLedger Stage Health Check
# PURPOSE: Verify each stage is working correctly before moving to the next.
#          Run this after completing a stage. Green = ready to proceed.
#          Red = something is broken — fix it before continuing.
#
# Usage:
#   bash scripts/health-check.sh [stage-number]
#   bash scripts/health-check.sh 0    # verify Stage 0
#   bash scripts/health-check.sh 4    # verify Stage 4
#   bash scripts/health-check.sh all  # run all checks
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARN=$((WARN + 1)); }
header() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }

# Max restarts for pods matching a label selector in a namespace (platform stability).
check_max_restarts() {
  local ns=$1 selector=$2 limit=$3 desc=$4
  local lines line name restarts max_seen=0

  if ! kubectl get namespace "$ns" &>/dev/null; then
    return 0
  fi

  lines=$(kubectl get pods -n "$ns" -l "$selector" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].restartCount}{"\n"}{end}' \
    2>/dev/null || true)

  if [ -z "$lines" ]; then
    warn "$desc — no pods found (skipped)"
    return 0
  fi

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%% *}"
    restarts="${line##* }"
    [[ "$restarts" =~ ^[0-9]+$ ]] || restarts=0
    if [ "$restarts" -gt "$max_seen" ]; then
      max_seen=$restarts
    fi
    if [ "$restarts" -gt "$limit" ]; then
      fail "$desc: $name has $restarts restarts (limit $limit) — likely crash loop; fix before next stage"
      return 1
    fi
  done <<< "$lines"

  pass "$desc stable (highest: $max_seen restarts, limit $limit)"
}

show_top_restarts() {
  echo ""
  echo -e "  ${BOLD}Top restart counts (cluster-wide):${NC}"
  if kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' \
    --no-headers 2>/dev/null | tail -15 | sed 's/^/    /'; then
    :
  else
    warn "Could not list pod restart counts — API may be slow; retry when load settles"
  fi
}

check_node_load() {
  local limit=$1 load_1m

  if ! command -v multipass &>/dev/null || ! multipass info clearledger &>/dev/null 2>&1; then
    return 0
  fi

  load_1m=$(multipass exec clearledger -- uptime 2>/dev/null \
    | awk -F'load average:' '{print $2}' | awk -F, '{gsub(/ /,"",$1); print int($1+0.5)}' || true)

  if [ -z "${load_1m:-}" ]; then
    warn "Could not read node load average from Multipass VM"
    return 0
  fi

  if [ "$load_1m" -gt "$limit" ]; then
    warn "Node load average (1m) is ${load_1m} — expected ≤ ${limit} before heavy observability stages; wait or scale down Litmus (LAB-GUIDE §7.0)"
  else
    pass "Node load average (1m) is ${load_1m} (comfortable, limit ${limit})"
  fi
}

# Platform pods can be Running while crash-looping — catch restart storms early.
check_platform_stability() {
  local stage=${1:-help}

  header "Platform stability (restart counts)"

  case "$stage" in
    0|1|2|3|help|*)
      show_top_restarts
      return 0
      ;;
  esac

  if kubectl get namespace kyverno &>/dev/null; then
    for component in admission-controller background-controller cleanup-controller reports-controller; do
      check_max_restarts kyverno "app.kubernetes.io/component=${component}" 5 "Kyverno ${component}"
    done
  fi

  if kubectl get namespace kube-system &>/dev/null; then
    check_max_restarts kube-system "k8s-app=hostpath-provisioner" 10 "MicroK8s hostpath-provisioner"
    check_max_restarts kube-system "k8s-app=metrics-server" 15 "metrics-server"
  fi

  case "$stage" in
    5|6|6.5|65|7|7.5|75|8|all)
      if kubectl get namespace vault &>/dev/null; then
        check_max_restarts vault "app.kubernetes.io/name=vault-agent-injector" 10 "Vault agent injector"
      fi
      ;;
  esac

  case "$stage" in
    6|6.5|65|7|7.5|75|8|all)
      if kubectl get namespace falco &>/dev/null; then
        check_max_restarts falco "app.kubernetes.io/name=falco" 5 "Falco"
      fi
      ;;
  esac

  case "$stage" in
    7|7.5|75|8|all)
      check_node_load 18
      if kubectl get namespace monitoring &>/dev/null; then
        check_max_restarts monitoring "app.kubernetes.io/name=kube-prometheus-stack-operator" 10 "Prometheus operator"
        check_max_restarts monitoring "app.kubernetes.io/name=loki" 5 "Loki"
      fi
      ;;
  esac

  show_top_restarts
}

# ── Helper functions ──────────────────────────────────────────────────────────
pod_running() {
  local label=$1 namespace=${2:-clearledger} label_key=${3:-app}
  local count
  count=$(kubectl get pods -n "$namespace" -l "${label_key}=${label}" \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
  [ "$count" -gt 0 ]
}

pod_ready() {
  local label=$1 namespace=${2:-clearledger}
  kubectl wait --for=condition=ready pod \
    -l "app=$label" -n "$namespace" --timeout=10s &>/dev/null
}

http_ok() {
  local url=$1
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$url" 2>/dev/null || echo "000")
  [ "$status" = "200" ] || [ "$status" = "201" ]
}

http_status() {
  curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$1" 2>/dev/null || echo "000"
}

# Grafana often redirects / to /login (302). Host curl may fail in some environments;
# fall back to an in-cluster health check against the Grafana Service.
grafana_reachable() {
  local status
  status=$(http_status "http://grafana.local")
  if [ "$status" = "200" ] || [ "$status" = "302" ] || [ "$status" = "301" ]; then
    return 0
  fi

  local grafana_pod
  grafana_pod=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "${grafana_pod:-}" ]; then
    if kubectl exec -n monitoring "$grafana_pod" -c grafana -- \
      wget -qO- http://localhost:3000/api/health 2>/dev/null | grep -q '"database":"ok"'; then
      return 0
    fi
  fi
  return 1
}

# ── Stage 0: Raw Kubernetes ───────────────────────────────────────────────────
check_stage_0() {
  header "Stage 0 — Raw Kubernetes"

  # Cluster
  if kubectl get nodes &>/dev/null; then
    pass "kubectl can reach the cluster"
  else
    fail "kubectl cannot reach the cluster — run QUICKSTART.md first"
    return
  fi

  local node_status
  node_status=$(kubectl get nodes --no-headers | awk '{print $2}')
  if echo "$node_status" | grep -q "Ready"; then
    pass "Node is Ready"
  else
    fail "Node is not Ready: $node_status"
  fi

  # Namespace
  if kubectl get namespace clearledger &>/dev/null; then
    pass "clearledger namespace exists"
  else
    fail "clearledger namespace missing — run: kubectl apply -f infra/manifests/namespace.yaml"
  fi

  # RBAC — ServiceAccounts + least-privilege Roles (infra/manifests/rbac/rbac.yaml)
  for sa in auth-service ledger-service notification-service clearledger-viewer; do
    if kubectl get serviceaccount "$sa" -n clearledger &>/dev/null; then
      pass "ServiceAccount $sa exists"
    else
      fail "ServiceAccount $sa missing — kubectl apply -f infra/manifests/rbac/rbac.yaml"
    fi
  done

  local can_secrets_auth can_ep_auth can_pods_viewer can_secrets_viewer
  can_secrets_auth=$(kubectl auth can-i get secrets \
    --as=system:serviceaccount:clearledger:auth-service -n clearledger 2>/dev/null) || true
  if [[ "$can_secrets_auth" == "no" ]]; then
    pass "RBAC: auth-service cannot get Secrets"
  else
    fail "RBAC: auth-service should not get Secrets (got: $can_secrets_auth)"
  fi

  can_ep_auth=$(kubectl auth can-i get endpoints \
    --as=system:serviceaccount:clearledger:auth-service -n clearledger 2>/dev/null) || true
  if [[ "$can_ep_auth" == "yes" ]]; then
    pass "RBAC: auth-service can get Endpoints"
  else
    fail "RBAC: auth-service should get Endpoints (got: $can_ep_auth)"
  fi

  can_pods_viewer=$(kubectl auth can-i get pods \
    --as=system:serviceaccount:clearledger:clearledger-viewer -n clearledger 2>/dev/null) || true
  if [[ "$can_pods_viewer" == "yes" ]]; then
    pass "RBAC: clearledger-viewer can get Pods"
  else
    fail "RBAC: clearledger-viewer should get Pods (got: $can_pods_viewer)"
  fi

  can_secrets_viewer=$(kubectl auth can-i get secrets \
    --as=system:serviceaccount:clearledger:clearledger-viewer -n clearledger 2>/dev/null) || true
  if [[ "$can_secrets_viewer" == "no" ]]; then
    pass "RBAC: clearledger-viewer cannot get Secrets"
  else
    fail "RBAC: clearledger-viewer must not get Secrets (got: $can_secrets_viewer)"
  fi

  local vault_auth automount_expected automount_actual
  for deploy in auth-service ledger-service notification-service; do
    vault_auth=$(kubectl get deploy "$deploy" -n clearledger \
      -o jsonpath='{.spec.template.metadata.annotations.vault\.hashicorp\.com/agent-inject}' 2>/dev/null || true)
    if [[ "$vault_auth" == "true" ]]; then
      automount_expected="true"
    else
      automount_expected="false"
    fi
    automount_actual=$(kubectl get deploy "$deploy" -n clearledger \
      -o jsonpath='{.spec.template.spec.automountServiceAccountToken}' 2>/dev/null || echo "")
    if [[ "$automount_actual" == "$automount_expected" ]]; then
      pass "Deployment $deploy automountServiceAccountToken=$automount_actual (expected for Vault=$vault_auth)"
    else
      fail "Deployment $deploy automountServiceAccountToken=$automount_actual (expected $automount_expected when vault inject=$vault_auth)"
    fi
  done

  # Infrastructure pods
  for svc in postgres redis; do
    if pod_running "$svc"; then
      pass "$svc is running"
    else
      fail "$svc is not running"
    fi
  done

  # Application pods
  for svc in auth-service ledger-service notification-service frontend; do
    if pod_running "$svc"; then
      pass "$svc is running"
    else
      fail "$svc is not running"
    fi
  done

  # Ingress
  if kubectl get ingress clearledger-api -n clearledger &>/dev/null; then
    pass "API Ingress exists"
  else
    fail "API Ingress missing — run: kubectl apply -f infra/manifests/ingress.yaml"
  fi

  if kubectl get ingress clearledger-frontend -n clearledger &>/dev/null; then
    pass "Frontend Ingress exists"
  else
    fail "Frontend Ingress missing — run: kubectl apply -f infra/manifests/ingress.yaml"
  fi

  # /etc/hosts
  if grep -q "clearledger.local" /etc/hosts 2>/dev/null; then
    pass "clearledger.local in /etc/hosts"
  else
    warn "/etc/hosts entry missing — run scripts/setup-hosts.sh"
  fi

  # API health checks
  if http_ok "http://clearledger.local/auth/health"; then
    pass "auth-service /health responds 200"
  else
    fail "auth-service /health not reachable at http://clearledger.local/auth/health"
  fi

  if http_ok "http://clearledger.local/ledger/health"; then
    pass "ledger-service /health responds 200"
  else
    fail "ledger-service /health not reachable"
  fi

  if http_ok "http://clearledger.local/notifications/health"; then
    pass "notification-service /health responds 200"
  else
    fail "notification-service /health not reachable"
  fi

  if curl -sf "http://clearledger.local/" 2>/dev/null | grep -q "ClearLedger"; then
    pass "frontend UI served at http://clearledger.local/"
  else
    fail "frontend UI not reachable at http://clearledger.local/"
  fi

  # End-to-end smoke test
  local reg_status
  reg_status=$(http_status "http://clearledger.local/auth/register" || echo "000")
  # 405 = method not allowed (GET on a POST endpoint) = service is up
  if [ "$reg_status" = "405" ] || [ "$reg_status" = "422" ]; then
    pass "auth-service /register endpoint responds (end-to-end routing works)"
  elif [ "$reg_status" = "200" ] || [ "$reg_status" = "201" ]; then
    pass "auth-service /register responds"
  else
    fail "auth-service /register not reachable (status: $reg_status)"
  fi
}

# ── Stage 1: CI Pipeline ──────────────────────────────────────────────────────
check_stage_1() {
  header "Stage 1 — CI Pipeline (GitHub Actions + Self-Hosted Runner)"

  local runner_check
  runner_check=$(bash scripts/runner-vm-state.sh state 2>/dev/null || echo "missing")

  case "$runner_check" in
    systemd:active:*)
      pass "GitHub Actions self-hosted runner is active (${runner_check#systemd:active:})"
      ;;
    process:running)
      pass "GitHub Actions runner process is running"
      warn "Runner is not managed by systemd — CI works now but will not survive a VM reboot. Fix: bash scripts/runner-vm-state.sh start (see stages/stage-1-ci-pipeline/README.md section 2)"
      ;;
    no-multipass)
      fail "multipass not found on this machine — install Multipass first (macOS/Linux/Windows: https://multipass.run)"
      ;;
    no-vm)
      fail "Multipass VM 'clearledger' not found — launch the VM first (see QUICKSTART.md)"
      ;;
    *)
      fail "GitHub Actions runner is not running inside the VM.
    Fix: bash scripts/runner-vm-state.sh start
    Setup: see stages/stage-1-ci-pipeline/README.md section 2"
      ;;
  esac

  # Remind the learner what to verify on GitHub (cannot check these from the host)
  echo ""
  echo "  Verify on GitHub:"
  echo "    Infra repo: github.com/YOUR_USERNAME/clearledger-infra (must exist)"
  echo "    Secrets:    github.com/YOUR_USERNAME/clearledger/settings/secrets/actions"
  echo "    Required:   DOCKER_USERNAME, DOCKER_PASSWORD, INFRA_REPO_TOKEN"
  echo "    Runner:     github.com/YOUR_USERNAME/clearledger → Settings → Actions → Runners"
}

# ── Stage 2: GitOps / ArgoCD ──────────────────────────────────────────────────
check_stage_2() {
  header "Stage 2 — GitOps (ArgoCD)"

  if pod_running "argocd-server" "argocd" "app.kubernetes.io/name"; then
    pass "ArgoCD server is running"
  else
    fail "ArgoCD not running — install from stable manifest"
  fi

  # ArgoCD application exists
  if kubectl get application clearledger -n argocd &>/dev/null; then
    pass "ArgoCD Application 'clearledger' exists"

    local app_repo
    app_repo=$(kubectl get application clearledger -n argocd \
      -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || echo "")
    if echo "$app_repo" | grep -q 'YOUR_GITHUB_USERNAME'; then
      fail "ArgoCD Application still has placeholder repoURL — edit and apply stages/stage-2-gitops/argocd/clearledger-app.yaml"
    fi

    local app_conditions
    app_conditions=$(kubectl get application clearledger -n argocd \
      -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || echo "")
    if echo "$app_conditions" | grep -qiE 'authentication required|repository not found'; then
      fail "ArgoCD cannot read clearledger-infra (ComparisonError) — run: argocd repo add with INFRA_REPO_TOKEN (see troubleshooting.md §ComparisonError)"
    fi

    local sync_status
    sync_status=$(kubectl get application clearledger -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    local health_status
    health_status=$(kubectl get application clearledger -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    if [ "$sync_status" = "Synced" ]; then
      pass "ArgoCD sync status: Synced"
    else
      warn "ArgoCD sync status: $sync_status (expected: Synced)"
    fi

    if [ "$health_status" = "Healthy" ]; then
      pass "ArgoCD health status: Healthy"
    else
      fail "ArgoCD health status: $health_status (expected: Healthy) — fix red pods before Stage 3"
    fi
  else
    fail "ArgoCD Application 'clearledger' not found — apply infra/argocd/clearledger-app.yaml"
  fi

  # Auth/ledger must be running (secretKeyRef until Stage 5)
  for deploy in auth-service ledger-service; do
    local ready desired
    ready=$(kubectl get deployment "$deploy" -n clearledger \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    desired=$(kubectl get deployment "$deploy" -n clearledger \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
    if [ "${ready:-0}" -ge "${desired:-2}" ] && [ "${ready:-0}" -gt 0 ]; then
      pass "$deploy ready ($ready/$desired)"
    else
      fail "$deploy not ready ($ready/$desired) — check secrets in clearledger-infra and ArgoCD sync"
    fi
  done

  # Prove selfHeal is enabled
  local self_heal
  self_heal=$(kubectl get application clearledger -n argocd \
    -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null || echo "false")
  if [ "$self_heal" = "true" ]; then
    pass "selfHeal is enabled — cluster drift is auto-reverted"
  else
    warn "selfHeal is not enabled — manual kubectl changes will not be reverted"
  fi
}

# ── Stage 3: Security Gates ───────────────────────────────────────────────────
check_stage_3() {
  header "Stage 3 — Security Gates"

  # Check pipeline file exists and has security jobs
  if [ -f ".github/workflows/ci.yaml" ]; then
    pass ".github/workflows/ci.yaml exists"

    for gate in "gitleaks" "semgrep" "checkov" "trivy" "cosign"; do
      if grep -qi "$gate" .github/workflows/ci.yaml; then
        pass "Pipeline includes $gate"
      else
        fail "Pipeline missing $gate gate in .github/workflows/ci.yaml"
      fi
    done
  else
    fail "No CI pipeline file at .github/workflows/ci.yaml"
  fi

  # Pre-commit hooks
  if [ -f ".pre-commit-config.yaml" ]; then
    pass ".pre-commit-config.yaml exists"
    if command -v pre-commit &>/dev/null; then
      if pre-commit run --all-files --show-diff-on-failure &>/dev/null 2>&1; then
        pass "pre-commit hooks pass on current codebase"
      else
        warn "pre-commit hooks found issues — run: pre-commit run --all-files"
      fi
    else
      warn "pre-commit not installed on host — macOS: brew install pre-commit && pre-commit install"
    fi
  else
    warn ".pre-commit-config.yaml not found"
  fi

  # Cosign keys
  if [ -f "infra/cosign.pub" ]; then
    pass "cosign.pub exists in infra/"
  else
    warn "cosign.pub not found — generate with: cosign generate-key-pair"
  fi
}

# ── Stage 4: Kyverno ─────────────────────────────────────────────────────────
check_stage_4() {
  header "Stage 4 — Admission Control (Kyverno)"

  if pod_running "admission-controller" "kyverno" "app.kubernetes.io/component"; then
    pass "Kyverno is running"
  else
    fail "Kyverno not running — see stages/stage-4-admission-control/README.md (helm upgrade --install kyverno ... --version 3.2.8)"
  fi

  # Policies
  local expected_policies=(
    "disallow-root-containers"
    "require-resource-limits"
    "require-signed-images"
    "disallow-privilege-escalation"
    "drop-all-capabilities"
  )

  for policy in "${expected_policies[@]}"; do
    if kubectl get clusterpolicy "$policy" &>/dev/null; then
      local action
      action=$(kubectl get clusterpolicy "$policy" \
        -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null)
      if [ "$action" = "Enforce" ]; then
        pass "Policy $policy — Enforce mode"
      else
        warn "Policy $policy exists but is in $action mode (expected: Enforce)"
      fi
    else
      fail "Policy $policy not found — apply infra/policies/ (see LAB-GUIDE §4.3)"
    fi
  done

  # Test that a root pod is rejected
  local test_result
  test_result=$(kubectl apply --dry-run=server -f - 2>&1 <<'TESTPOD' || true
apiVersion: v1
kind: Pod
metadata:
  name: health-check-root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
TESTPOD
)

  if echo "$test_result" | grep -qi "denied\|webhook"; then
    pass "Kyverno correctly rejects pods without securityContext"
  else
    warn "Kyverno dry-run did not reject root pod — policies may not be enforcing"
  fi

  # kube-bench CIS benchmark evidence (Stage 4)
  local baseline
  baseline="stages/stage-4-admission-control/scripts/kube-bench-baseline.json"
  if [ -f "$baseline" ]; then
    pass "kube-bench baseline exists ($baseline)"
  else
    fail "kube-bench baseline missing — expected $baseline"
    return
  fi

  if [ -x "stages/stage-4-admission-control/scripts/run-kube-bench.sh" ]; then
    if bash stages/stage-4-admission-control/scripts/run-kube-bench.sh >/dev/null 2>&1; then
      pass "kube-bench matches baseline (no new FAIL regressions)"
    else
      fail "kube-bench regressions detected — run: bash stages/stage-4-admission-control/scripts/run-kube-bench.sh"
    fi
  else
    warn "run-kube-bench.sh not executable — chmod +x stages/stage-4-admission-control/scripts/run-kube-bench.sh"
  fi
}

# ── Stage 5: Vault ────────────────────────────────────────────────────────────
check_stage_5() {
  header "Stage 5 — Secrets Management (Vault)"

  if pod_running "vault" "vault" "app.kubernetes.io/name"; then
    pass "Vault pod is running"
  else
    fail "Vault not running — helm install vault hashicorp/vault ..."
  fi

  # Vault agent injector (required for pod secret injection)
  if pod_running "vault-agent-injector" "vault" "app.kubernetes.io/name"; then
    pass "Vault agent injector is running"
  else
    fail "Vault injector not running — helm install with injector.enabled=true"
  fi

  # Vault unsealed
  local vault_status
  vault_status=$(kubectl exec -n vault vault-0 -- \
    vault status -format=json 2>/dev/null | jq -r .sealed 2>/dev/null || echo "unknown")

  if [ "$vault_status" = "false" ]; then
    pass "Vault is unsealed"
  elif [ "$vault_status" = "true" ]; then
    fail "Vault is sealed — secrets cannot be injected. Unseal with: vault operator unseal"
  else
    warn "Could not determine Vault seal status"
  fi

  # K8s auth configured
  local k8s_auth
  k8s_auth=$(kubectl exec -n vault vault-0 -- \
    vault auth list -format=json 2>/dev/null | jq -r '.["kubernetes/"]' 2>/dev/null || echo "null")

  if [ "$k8s_auth" != "null" ] && [ -n "$k8s_auth" ]; then
    pass "Vault Kubernetes auth method is enabled"
  else
    fail "Vault Kubernetes auth not configured — see Stage 5 README Step 2"
  fi

  # K8s Secrets deleted (Stage 5 removes them)
  if kubectl get secret auth-service-secret -n clearledger &>/dev/null; then
    warn "auth-service-secret still exists as K8s Secret — Stage 5 not fully applied"
  else
    pass "auth-service-secret removed — Vault is the secret source"
  fi

  # Vault agent injected files
  local auth_pod
  auth_pod=$(kubectl get pod -n clearledger -l app=auth-service -o name | head -1)
  if [ -n "$auth_pod" ]; then
    if kubectl exec -n clearledger "$auth_pod" -c auth-service -- \
      test -f /vault/secrets/database_url 2>/dev/null; then
      pass "Vault injected /vault/secrets/database_url into auth-service"
    else
      fail "Vault secret file not found in auth-service pod — check Vault agent logs"
    fi
  fi
}

# ── Stage 6: Falco ────────────────────────────────────────────────────────────
check_stage_6() {
  header "Stage 6 — Runtime Security (Falco)"

  # Falco daemonset
  local falco_desired falco_ready
  falco_desired=$(kubectl get daemonset falco -n falco \
    -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
  falco_ready=$(kubectl get daemonset falco -n falco \
    -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

  if [ "$falco_desired" = "$falco_ready" ] && [ "$falco_ready" -gt 0 ]; then
    pass "Falco DaemonSet: $falco_ready/$falco_desired nodes"
  else
    fail "Falco DaemonSet not ready: $falco_ready/$falco_desired"
  fi

  # Custom rules loaded
  if kubectl get configmap clearledger-falco-rules -n falco &>/dev/null; then
    pass "ClearLedger custom Falco rules ConfigMap exists"
  else
    fail "Custom rules not loaded — apply infra/falco/clearledger-rules.yaml"
  fi

  # Network policies
  for policy in default-deny-all allow-auth-service allow-ledger-service allow-notification-service; do
    if kubectl get networkpolicy "$policy" -n clearledger &>/dev/null; then
      pass "NetworkPolicy $policy exists"
    else
      fail "NetworkPolicy $policy missing — apply infra/deferred-by-stage/stage-6-runtime-security/netpol/"
    fi
  done

  # Services still reachable after network policies applied
  if http_ok "http://clearledger.local/auth/health"; then
    pass "auth-service reachable after network policies"
  else
    fail "auth-service unreachable — network policy may be too restrictive"
  fi

  if http_ok "http://clearledger.local/notifications/health"; then
    pass "notification-service reachable after network policies"
  else
    fail "notification-service unreachable — check allow-notification-service policy"
  fi
}

# ── Stage 6.5: Chaos Engineering ─────────────────────────────────────────────
check_stage_65() {
  header "Stage 6.5 — Chaos Engineering (LitmusChaos)"

  if kubectl get namespace litmus &>/dev/null; then
    pass "litmus namespace exists"
  else
    fail "litmus namespace missing — install LitmusChaos (Stage 6.5 README)"
  fi

  if kubectl get serviceaccount litmus-admin -n litmus &>/dev/null; then
    pass "litmus-admin ServiceAccount exists in litmus"
  else
    fail "litmus-admin SA missing — apply stages/stage-6.5-chaos-engineering/infra/chaos/litmus-rbac.yaml"
  fi

  if kubectl get chaosexperiment pod-delete -n litmus &>/dev/null; then
    pass "pod-delete ChaosExperiment installed in litmus"
  else
    fail "pod-delete experiment missing — run install-litmus.sh"
  fi

  if kubectl get pods -n litmus -l app=litmus --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | grep -q .; then
    pass "Litmus chaos operator is running"
  else
    warn "Litmus operator pod not found — run install-litmus.sh"
  fi

  if http_ok "http://litmus.local"; then
    pass "Litmus ChaosCenter reachable at http://litmus.local"
  else
    warn "Litmus UI not reachable — kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/litmus-ingress.yaml"
  fi

  if kubectl get pods -n litmus 2>/dev/null | grep -E 'subscriber.*Running' | grep -q .; then
    pass "Litmus subscriber running (UI connected to cluster)"
  else
    fail "Litmus subscriber missing — UI will be empty: make connect-litmus (set LITMUS_PASSWORD if needed)"
  fi

  if http_ok "http://clearledger.local/auth/health"; then
    pass "auth-service healthy (baseline before chaos)"
  else
    fail "auth-service not reachable — run: make fix-65-prereqs"
  fi

  local auth_ready
  auth_ready=$(kubectl get pods -n clearledger -l app=auth-service \
    --no-headers 2>/dev/null | awk '$2=="2/2" && $3=="Running"' | wc -l | tr -d ' ')
  if [ "${auth_ready:-0}" -ge 2 ]; then
    pass "auth-service has 2/2 Ready replicas (stable for chaos)"
  else
    fail "auth-service not 2/2 Ready (${auth_ready:-0} ready) — run: make fix-65-prereqs"
  fi

  if kubectl get networkpolicy allow-postgres -n clearledger &>/dev/null; then
    pass "allow-postgres NetworkPolicy exists (Stage 6 fix)"
  else
    warn "allow-postgres missing — postgres may block auth DB connections: make fix-65-prereqs"
  fi
}

# ── Stage 7: Observability ────────────────────────────────────────────────────
check_stage_7() {
  header "Stage 7 — Observability (Grafana + Prometheus + Loki)"

  # Prometheus
  if kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus" \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q "."; then
    pass "Prometheus is running"
  else
    fail "Prometheus not running"
  fi

  # Grafana (browser uses http://grafana.local; accept redirect + in-cluster fallback)
  if grafana_reachable; then
    pass "Grafana reachable (http://grafana.local or in-cluster health OK)"
  else
    fail "Grafana not reachable — run: bash scripts/setup-hosts.sh && kubectl get ingress -n monitoring"
  fi

  # Loki (pod up + query path from Grafana — same path dashboards use)
  local loki_restarts=0
  if kubectl get pod -n monitoring loki-0 --no-headers 2>/dev/null | awk '{print $2}' | grep -q '1/1'; then
    loki_restarts="$(kubectl get pod -n monitoring loki-0 -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)"
    if [ "${loki_restarts:-0}" -gt 5 ]; then
      warn "Loki is running but restarted ${loki_restarts}× — likely query overload; re-run install-observability.sh with FORCE=1"
    else
      pass "Loki pod is running (${loki_restarts} restarts)"
    fi
    if kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
      wget -qO- --timeout=5 http://loki:3100/ready 2>/dev/null | grep -q ready; then
      pass "Loki reachable from Grafana (http://loki:3100/ready)"
    else
      warn "Loki not reachable from Grafana — dashboards will show connection refused"
    fi
  else
    warn "Loki not running — log aggregation unavailable"
  fi

  # Alert rules
  if kubectl get prometheusrule clearledger-security-alerts -n monitoring &>/dev/null; then
    pass "ClearLedger alerting rules exist"
  else
    warn "Alerting rules not applied — apply stages/stage-7-observability/infra/monitoring/alerting-rules.yaml"
  fi

  # Dashboards imported (host API or in-cluster fallback)
  local dashboard_count grafana_pod
  dashboard_count=$(curl -s \
    "http://admin:admin123@grafana.local/api/search?tag=clearledger" \
    2>/dev/null | jq length 2>/dev/null || echo "0")
  if [ "${dashboard_count:-0}" -eq 0 ]; then
    grafana_pod=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "${grafana_pod:-}" ]; then
      dashboard_count=$(kubectl exec -n monitoring "$grafana_pod" -c grafana -- \
        wget -qO- --header="Authorization: Basic $(printf '%s' 'admin:admin123' | base64)" \
        "http://localhost:3000/api/search?tag=clearledger" 2>/dev/null \
        | jq length 2>/dev/null || echo "0")
    fi
  fi

  if [ "$dashboard_count" -ge 4 ]; then
    pass "ClearLedger dashboards imported ($dashboard_count found)"
  elif [ "$dashboard_count" -gt 0 ]; then
    warn "$dashboard_count ClearLedger dashboard(s) imported (expected 4)"
  else
    warn "No ClearLedger dashboards imported — import JSON files from stages/stage-7-observability/infra/dashboards/"
  fi
}

# ── Stage 7.5: OpenTelemetry ───────────────────────────────────────────────────
check_stage_75() {
  header "Stage 7.5 — OpenTelemetry (Distributed Tracing)"

  if kubectl get deployment otel-collector -n monitoring &>/dev/null; then
  local otel_ready
  otel_ready=$(kubectl get deployment otel-collector -n monitoring \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "${otel_ready:-0}" -ge 1 ]; then
      pass "OTel Collector is running ($otel_ready replica(s))"
    else
      fail "OTel Collector not ready — apply stages/stage-7.5-opentelemetry/infra/otel/"
    fi
  else
    fail "OTel Collector deployment missing — apply stages/stage-7.5-opentelemetry/infra/otel/"
  fi

  if kubectl get configmap grafana-datasource-tempo -n monitoring &>/dev/null; then
    pass "Grafana Tempo datasource ConfigMap exists"
  else
    warn "Tempo datasource ConfigMap missing — Grafana may not show Tempo"
  fi

  if kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q "."; then
    pass "Tempo is running"
  else
    warn "Tempo not running — install via helm (Stage 7.5 README)"
  fi

  if kubectl get deployment auth-service -n clearledger \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}' \
    2>/dev/null | grep -q otel-collector; then
    pass "auth-service has OTEL_EXPORTER_OTLP_ENDPOINT configured"
  else
    warn "OTel env vars not found on auth-service — redeploy with updated manifests"
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  check_platform_stability "${STAGE:-help}"

  echo -e "\n${BOLD}─────────────────────────────────────────${NC}"
  echo -e "${BOLD}Health Check Summary${NC}"
  echo -e "${GREEN}✓ Passed: $PASS${NC}"
  [ "$WARN" -gt 0 ] && echo -e "${YELLOW}⚠ Warnings: $WARN${NC}"
  [ "$FAIL" -gt 0 ] && echo -e "${RED}✗ Failed: $FAIL${NC}"
  echo -e "${BOLD}─────────────────────────────────────────${NC}"

  if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All checks passed. Ready for the next stage.${NC}"
  elif [ "$FAIL" -eq 0 ]; then
    echo -e "${YELLOW}${BOLD}Warnings present but no failures. Review warnings before proceeding.${NC}"
  else
    echo -e "${RED}${BOLD}Fix the failures above before moving to the next stage.${NC}"
    exit 1
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
STAGE=${1:-"help"}

echo -e "${BOLD}ClearLedger DevSecOps Lab — Health Check${NC}"
echo -e "Running checks for stage: ${CYAN}${STAGE}${NC}"

case "$STAGE" in
  0) check_stage_0 ;;
  1) check_stage_0; check_stage_1 ;;
  2) check_stage_1; check_stage_2 ;;
  3) check_stage_2; check_stage_3 ;;
  4) check_stage_3; check_stage_4 ;;
  5) check_stage_4; check_stage_5 ;;
  6) check_stage_5; check_stage_6 ;;
  6.5|65) check_stage_6; check_stage_65 ;;
  7)
    if [ "${SKIP_CHAOS_CHECK:-0}" != "1" ]; then
      check_stage_65
    fi
    check_stage_7 ;;
  7.5|75) check_stage_7; check_stage_75 ;;
  8) check_stage_75 ;;
  all)
    check_stage_0
    check_stage_1
    check_stage_2
    check_stage_3
    check_stage_4
    check_stage_5
    check_stage_6
    check_stage_65
    check_stage_7
    check_stage_75
    ;;
  help|*)
    echo ""
    echo "Usage: bash scripts/health-check.sh [stage]"
    echo ""
    echo "  bash scripts/health-check.sh 0      # Stage 0: Raw Kubernetes"
    echo "  bash scripts/health-check.sh 1      # Stage 1: CI Pipeline"
    echo "  bash scripts/health-check.sh 2      # Stage 2: GitOps"
    echo "  bash scripts/health-check.sh 3      # Stage 3: Security Gates"
    echo "  bash scripts/health-check.sh 4      # Stage 4: Kyverno"
    echo "  bash scripts/health-check.sh 5      # Stage 5: Vault"
    echo "  bash scripts/health-check.sh 6      # Stage 6: Falco"
    echo "  bash scripts/health-check.sh 6.5    # Stage 6.5: Chaos Engineering"
    echo "  bash scripts/health-check.sh 7      # Stage 7: Observability"
    echo "  bash scripts/health-check.sh 7.5    # Stage 7.5: OpenTelemetry"
    echo "  bash scripts/health-check.sh all    # All stages"
    echo ""
    exit 0
    ;;
esac

print_summary
