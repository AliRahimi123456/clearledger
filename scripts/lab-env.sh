#!/usr/bin/env bash
# Shared helpers for ClearLedger lab scripts. Source, do not execute directly.
# shellcheck shell=bash

lab_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

lab_load_env() {
  local root f
  root="$(lab_root)"
  f="${root}/scripts/lab.local.env"
  if [ -f "$f" ]; then
    # shellcheck disable=SC1090
    set -a
    source "$f"
    set +a
  fi
}

lab_github_owner() {
  lab_load_env
  if [ -n "${GITHUB_OWNER:-}" ]; then
    echo "$GITHUB_OWNER"
    return 0
  fi
  local url owner
  url="$(git -C "$(lab_root)" remote get-url origin 2>/dev/null || true)"
  owner="$(printf '%s' "$url" | sed -E 's#.*github.com[:/]([^/]+)/.*#\1#' 2>/dev/null || true)"
  if [ -n "$owner" ] && [ "$owner" != "$url" ]; then
    echo "$owner"
    return 0
  fi
  echo "YOUR_GITHUB_USERNAME"
}

lab_require_docker_username() {
  lab_load_env
  if [ -n "${DOCKER_USERNAME:-}" ]; then
    return 0
  fi
  echo "ERROR: DOCKER_USERNAME is not set." >&2
  echo "  export DOCKER_USERNAME=your-dockerhub-user" >&2
  echo "  or run: make configure" >&2
  return 1
}

lab_patch_kustomization() {
  local root user
  root="$(lab_root)"
  lab_require_docker_username || return 1
  user="$DOCKER_USERNAME"
  if grep -q 'YOUR_DOCKERHUB_USERNAME' "${root}/infra/manifests/kustomization.yaml"; then
    if [[ "$(uname)" == Darwin ]]; then
      sed -i '' "s/YOUR_DOCKERHUB_USERNAME/${user}/g" "${root}/infra/manifests/kustomization.yaml"
    else
      sed -i "s/YOUR_DOCKERHUB_USERNAME/${user}/g" "${root}/infra/manifests/kustomization.yaml"
    fi
    echo "✓ kustomization.yaml → docker.io/${user}/..."
  else
    echo "✓ kustomization.yaml already has a Docker Hub username"
  fi
}

lab_patch_argocd_apps() {
  local root owner
  root="$(lab_root)"
  owner="$(lab_github_owner)"
  if [ "$owner" = "YOUR_GITHUB_USERNAME" ]; then
    echo "WARN: could not detect GitHub owner — set GITHUB_OWNER in scripts/lab.local.env" >&2
    return 1
  fi
  for f in \
    "${root}/infra/argocd/clearledger-app.yaml" \
    "${root}/stages/stage-2-gitops/argocd/clearledger-app.yaml" \
    "${root}/stages/stage-8-aws-migration/argocd/clearledger-aws-app.yaml"; do
    [ -f "$f" ] || continue
    if grep -q 'YOUR_GITHUB_USERNAME\|YOUR_USERNAME\|Osomudeya' "$f" 2>/dev/null; then
      if [[ "$(uname)" == Darwin ]]; then
        sed -i '' "s|YOUR_GITHUB_USERNAME|${owner}|g; s|YOUR_USERNAME|${owner}|g; s|Osomudeya|${owner}|g" "$f"
      else
        sed -i "s|YOUR_GITHUB_USERNAME|${owner}|g; s|YOUR_USERNAME|${owner}|g; s|Osomudeya|${owner}|g" "$f"
      fi
      echo "✓ patched $(basename "$f") → ${owner}"
    fi
  done
}

lab_ensure_kubeconfig() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl not found" >&2
    return 1
  fi
  if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="${HOME}/.kube/clearledger-config"
  fi
  if kubectl get nodes >/dev/null 2>&1; then
    return 0
  fi
  if command -v multipass >/dev/null 2>&1 && multipass info clearledger >/dev/null 2>&1; then
    bash "$(lab_root)/scripts/ensure-kubeconfig.sh"
    export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/clearledger-config}"
    kubectl get nodes >/dev/null 2>&1
  else
    echo "ERROR: cannot reach cluster — run make setup" >&2
    return 1
  fi
}
