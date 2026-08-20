# Indentation: tabs only
# Several recipes use bash-only features (set -o pipefail); force bash instead of the
# system default /bin/sh (dash on Ubuntu/Debian, which doesn't support pipefail).
SHELL := /bin/bash

.PHONY: help setup check stage teardown aws-up aws-down \
	stage-0 stage-1 stage-2 stage-3 stage-4 \
	stage-5 stage-6 stage-7 stage-8 \
	integration-up integration-down integration-test open-local-ui \
	open-ui open-argocd open-grafana open-vault open-falco open-litmus \
	check-0 check-1 check-2 check-3 check-4 check-5 check-6 check-7 check-65 check-75 check-all \
	demo-6 demo-7 demo-65 fix-65-prereqs fix-argocd push-infra-manifests connect-litmus \
	runner-status runner-logs doctor reclaim snapshot restore snapshots

.DEFAULT_GOAL := help

GREEN  := \033[0;32m
YELLOW := \033[1;33m
CYAN   := \033[0;36m
BOLD   := \033[1m
NC     := \033[0m

help:
	@echo ""
	@echo "$(GREEN)New here? Start with: make setup$(NC)"
	@echo ""
	@echo "$(BOLD)ClearLedger DevSecOps Lab$(NC)"
	@echo "Production-grade fintech security — from raw Kubernetes to AWS."
	@echo ""
	@echo "$(CYAN)Getting started:$(NC)"
	@echo "  make setup        Provision the Multipass VM and install MicroK8s"
	@echo "  make stage-0      Stage 0 README + deploy steps in LAB-GUIDE §0.5"
	@echo ""
	@echo "$(CYAN)Stage navigation:$(NC)"
	@echo "  make stage-0      Raw Kubernetes — the running system"
	@echo "  make stage-1      CI Pipeline — automate the build"
	@echo "  make stage-2      GitOps — ArgoCD takes over deploys"
	@echo "  make stage-3      Security Gates — scan every commit"
	@echo "  make stage-4      Admission Control — Kyverno enforces policy"
	@echo "  make stage-5      Secrets Management — Vault replaces K8s Secrets"
	@echo "  make stage-6      Runtime Security — Falco watches live pods"
	@echo "  make stage-7      Observability — Grafana security dashboards"
	@echo "  make stage-8      AWS Migration — same architecture, cloud infra"
	@echo ""
	@echo "$(CYAN)Disk health:$(NC)"
	@echo "  make doctor       VM disk %, PVC usage, Prometheus TSDB — PASS/WARN/FAIL"
	@echo "  make reclaim      Prune unused images + vacuum journald inside the VM"
	@echo ""
	@echo "$(CYAN)Saving progress (Multipass snapshots — requires 1.13+):$(NC)"
	@echo "  make snapshot STAGE=7   Save VM state after completing a stage"
	@echo "  make restore STAGE=7    Restore VM to a saved snapshot"
	@echo "  make snapshots          List saved snapshots"
	@echo ""
	@echo "$(CYAN)Health checks:$(NC)"
	@echo "  make check        Check the current stage (prompts for stage number)"
	@echo "  make check-0      Check Stage 0 specifically"
	@echo "  make check-65     Check Stage 6.5 (chaos engineering)"
	@echo "  make demo-7       Run Stage 7 hands-on lab (terminal → Grafana)"
	@echo "  make check-75     Check Stage 7.5 (OpenTelemetry)"
	@echo "  make check-all    Run all health checks"
	@echo "  make runner-status  Check GitHub Actions runner is running"
	@echo "  make runner-logs    View last 50 runner log lines"
	@echo ""
	@echo "$(CYAN)Local stack (no Kubernetes — see docs/LAB-GUIDE.md):$(NC)"
	@echo "  make integration-up    Start docker-compose.integration.yml"
	@echo "  make integration-down  Stop local stack"
	@echo "  make integration-test  Run scripts/test-frontend-integration.sh"
	@echo "  make open-local-ui     Open http://localhost:3000"
	@echo ""
	@echo "$(CYAN)Open UIs (browser):$(NC)"
	@echo "  make open-ui      Open ClearLedger web UI (cluster)"
	@echo "  make open-argocd  Open ArgoCD dashboard"
	@echo "  make open-grafana Open Grafana dashboards"
	@echo "  make open-vault   Open HashiCorp Vault UI"
	@echo "  make open-falco   Open Falco security UI"
	@echo "  make open-litmus  Open Litmus ChaosCenter UI"
	@echo "  make demo-6       Guided Falco alert demo (UI + terminal)"
	@echo "  make fix-65-prereqs  Fix auth restarts before Stage 6.5 (netpol + probes)"
	@echo "  make connect-litmus  Connect Litmus UI to cluster (fixes empty Overview)"
	@echo "  make demo-65      Chaos pod-delete demo (auth-service resilience)"
	@echo ""
	@echo "$(CYAN)AWS (Stage 8):$(NC)"
	@echo "  make aws-up       Provision AWS infrastructure (Terraform)"
	@echo "  make aws-down     Destroy AWS infrastructure (stops charges)"
	@echo ""
	@echo "$(CYAN)Teardown:$(NC)"
	@echo "  make teardown     Stop and delete the local Multipass VM"
	@echo ""

setup:
	@echo "$(GREEN)Setting up ClearLedger cluster...$(NC)"
	@echo "This takes 3-5 minutes. Go make a coffee."
	@bash scripts/setup-cluster.sh
	@bash scripts/setup-hosts.sh
	@echo ""
	@echo "$(GREEN)Setup complete.$(NC)"
	@echo ""
	@echo "You have an empty Kubernetes cluster — the app is NOT deployed yet."
	@echo "Do NOT run make check-0 until Stage 0 deploy is done."
	@echo ""
	@echo "Next:"
	@echo "  1. docs/LAB-GUIDE.md — Stage 0 (§0.3 build/push, §0.5 deploy)"
	@echo "  2. export DOCKER_USERNAME=your-dockerhub-username"
	@echo "  3. LAB-GUIDE §0.5 — six deploy layers (use stage-0 deployments)"
	@echo "  4. make check-0"

stage-0:
	@echo "$(CYAN)Stage 0 — Raw Kubernetes$(NC)"
	@echo "Goal: ClearLedger is running. You deployed it manually."
	@echo ""
	@echo "Order:"
	@echo "  1. Build + push images (LAB-GUIDE §0.3) — Docker Hub repos required"
	@echo "  2. export DOCKER_USERNAME=your-username"
	@echo "  3. LAB-GUIDE §0.5 — six deploy layers (stage-0 deployments)"
	@echo "  4. make check-0  &&  open http://clearledger.local"
	@echo ""
	@echo "Full guide: docs/LAB-GUIDE.md#stage-0--the-running-system"

stage-1:
	@echo "$(CYAN)Stage 1 — CI Pipeline$(NC)"
	@echo "Goal: A git push builds images automatically."
	@echo ""
	@cat stages/stage-1-ci-pipeline/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-1-ci-pipeline/README.md"

stage-2:
	@echo "$(CYAN)Stage 2 — GitOps with ArgoCD$(NC)"
	@echo "Goal: Git is truth. The cluster enforces it."
	@echo ""
	@cat stages/stage-2-gitops/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-2-gitops/README.md"

stage-3:
	@echo "$(CYAN)Stage 3 — Security Gates$(NC)"
	@echo "Goal: Every commit passes Gitleaks, Semgrep, Trivy, Checkov."
	@echo ""
	@cat stages/stage-3-security-gates/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-3-security-gates/README.md"

stage-4:
	@echo "$(CYAN)Stage 4 — Admission Control$(NC)"
	@echo "Goal: Kyverno blocks bad pods at deploy time."
	@echo ""
	@cat stages/stage-4-admission-control/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-4-admission-control/README.md"

stage-5:
	@echo "$(CYAN)Stage 5 — Secrets Management$(NC)"
	@echo "Goal: No credentials in Git. Vault injects them at runtime."
	@echo ""
	@cat stages/stage-5-secrets-management/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-5-secrets-management/README.md"

stage-6:
	@echo "$(CYAN)Stage 6 — Runtime Security$(NC)"
	@echo "Goal: Falco watches every syscall in every running pod."
	@echo ""
	@cat stages/stage-6-runtime-security/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-6-runtime-security/README.md"

stage-7:
	@echo "$(CYAN)Stage 7 — Observability$(NC)"
	@echo "Goal: Security you can see, measure, and prove."
	@echo ""
	@echo "  1. bash stages/stage-7-observability/scripts/install-observability.sh"
	@echo "  2. Follow docs/LAB-GUIDE.md — Stage 7 (§7.2 verify, §7.4 hands-on lab)"
	@echo "  3. make demo-7   # guided Kyverno → Falco → logins → compliance"
	@echo "  4. make check-7"
	@echo ""
	@echo "Full guide: docs/LAB-GUIDE.md#stage-7--security-observability"

stage-8:
	@echo "$(CYAN)Stage 8 — AWS Migration$(NC)"
	@echo "Goal: Same architecture. Cloud infrastructure."
	@echo ""
	@cat stages/stage-8-aws-migration/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-8-aws-migration/README.md"

check:
	@read -p "Which stage to check? (0-7): " n; \
	bash scripts/health-check.sh $$n

check-0:
	@bash scripts/health-check.sh 0

check-1:
	@bash scripts/health-check.sh 1

check-2:
	@bash scripts/health-check.sh 2

check-3:
	@bash scripts/health-check.sh 3

check-4:
	@bash scripts/health-check.sh 4

check-5:
	@bash scripts/health-check.sh 5

check-6:
	@bash scripts/health-check.sh 6

demo-6:
	@bash stages/stage-6-runtime-security/scripts/demo-falco-alerts.sh

demo-7:
	@bash stages/stage-7-observability/scripts/generate-dashboard-data.sh

connect-litmus:
	@bash stages/stage-6.5-chaos-engineering/scripts/connect-litmus-infra.sh

fix-65-prereqs: fix-argocd
	@echo "$(GREEN)Applying Stage 6 network policies (allow-postgres + app egress)...$(NC)"
	@kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
	@kubectl rollout status deployment/auth-service -n clearledger --timeout=300s 2>/dev/null || true
	@kubectl rollout status deployment/ledger-service -n clearledger --timeout=300s 2>/dev/null || true

GITHUB_OWNER ?= YOUR_GITHUB_USERNAME
INFRA_REPO   ?= https://github.com/$(GITHUB_OWNER)/clearledger-infra.git

# Push canonical manifests to clearledger-infra (Kustomize image tags preserved from Git).
push-infra-manifests:
	@set -euo pipefail; \
	tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; \
	if [ -n "$${INFRA_REPO_TOKEN:-}" ]; then \
	  git clone "https://$${INFRA_REPO_TOKEN}@github.com/$(GITHUB_OWNER)/clearledger-infra.git" "$$tmp/infra"; \
	else \
	  git clone "https://github.com/$(GITHUB_OWNER)/clearledger-infra.git" "$$tmp/infra"; \
	fi; \
	command -v kustomize >/dev/null || { echo "Install kustomize: brew install kustomize"; exit 1; }; \
	if [ -f "$$tmp/infra/manifests/kustomization.yaml" ]; then \
	  cp "$$tmp/infra/manifests/kustomization.yaml" "$$tmp/saved-kustomization.yaml"; \
	else \
	  mkdir -p "$$tmp/saved-images"; \
	  for svc in auth-service ledger-service notification-service frontend; do \
	    grep -m1 'image:' "$$tmp/infra/manifests/$$svc/deployment.yaml" \
	      | awk '{print $$2}' > "$$tmp/saved-images/$$svc" 2>/dev/null || true; \
	  done; \
	fi; \
	rsync -a --delete \
	  infra/manifests/ "$$tmp/infra/manifests/"; \
	if [ -f "$$tmp/saved-kustomization.yaml" ]; then \
	  cp "$$tmp/saved-kustomization.yaml" "$$tmp/infra/manifests/kustomization.yaml"; \
	else \
	  cd "$$tmp/infra/manifests"; \
	  kustomize edit set image \
	    clearledger/auth-service=$$(cat "$$tmp/saved-images/auth-service") \
	    clearledger/ledger-service=$$(cat "$$tmp/saved-images/ledger-service") \
	    clearledger/notification-service=$$(cat "$$tmp/saved-images/notification-service") \
	    clearledger/frontend=$$(cat "$$tmp/saved-images/frontend"); \
	fi; \
	cd "$$tmp/infra/manifests" && kustomize build . >/dev/null; \
	cd "$$tmp/infra"; \
	git config user.email "github-ci@clearledger.local"; \
	git config user.name "GitHub Actions Bot"; \
	git add manifests/; \
	if git diff --staged --quiet; then echo "No manifest changes in clearledger-infra"; exit 0; fi; \
	git commit -m "fix(gitops): sync canonical manifests (Kustomize tags preserved)"; \
	git push; \
	echo "✓ clearledger-infra updated"

# Prod GitOps fix: align infra Git, re-apply Application (no kubectl apply to deployments).
# Requires GITHUB_OWNER (your GitHub username) — same as Stage 2 §2.1 repoURL.
fix-argocd: push-infra-manifests
	@test "$(GITHUB_OWNER)" != "YOUR_GITHUB_USERNAME" || { \
	  echo "$(YELLOW)Set GITHUB_OWNER=your-github-username (Stage 2 repoURL) before make fix-argocd$(NC)"; \
	  echo "  export GITHUB_OWNER=Osomudeya   # example"; \
	  exit 1; \
	}
	@echo "$(GREEN)Re-applying ArgoCD Application + triggering sync...$(NC)"
	@sed 's|YOUR_GITHUB_USERNAME|$(GITHUB_OWNER)|g' infra/argocd/clearledger-app.yaml | kubectl apply -f -
	@kubectl annotate application clearledger -n argocd \
		argocd.argoproj.io/refresh=hard --overwrite
	@argocd app sync clearledger --grpc-web --prune 2>/dev/null || \
		echo "$(YELLOW)argocd CLI not logged in — auto-sync will apply within ~3min$(NC)"
	@kubectl rollout status deployment/auth-service -n clearledger --timeout=300s 2>/dev/null || true
	@kubectl rollout status deployment/ledger-service -n clearledger --timeout=300s 2>/dev/null || true
	@kubectl get application clearledger -n argocd \
		-o jsonpath='ArgoCD: sync={.status.sync.status} health={.status.health.status}{"\n"}' 2>/dev/null || true
	@kubectl get pods -n clearledger

demo-65:
	@bash stages/stage-6.5-chaos-engineering/scripts/run-chaos.sh

check-7:
	@bash scripts/health-check.sh 7

check-65:
	@bash scripts/health-check.sh 65

check-75:
	@bash scripts/health-check.sh 75

check-all:
	@bash scripts/health-check.sh all

integration-up:
	docker compose -f docker-compose.integration.yml up --build -d

integration-down:
	docker compose -f docker-compose.integration.yml down

integration-test:
	BASE_URL=http://localhost:3000 bash scripts/test-frontend-integration.sh

OPEN_CMD := $(shell \
  if command -v open > /dev/null 2>&1; then echo "open"; \
  elif command -v xdg-open > /dev/null 2>&1; then echo "xdg-open"; \
  else echo "echo Opening:"; fi)

open-local-ui:
	@echo "Opening local integration UI (register first if the DB is fresh)..."
	@$(OPEN_CMD) http://localhost:3000

open-ui:
	@echo "Opening ClearLedger UI..."
	@$(OPEN_CMD) http://clearledger.local

open-argocd:
	@echo "Opening ArgoCD..."
	@echo "Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
	@$(OPEN_CMD) https://argocd.local

open-grafana:
	@echo "Opening Grafana (login: admin / admin123)..."
	@$(OPEN_CMD) http://grafana.local

open-vault:
	@echo "Opening Vault (token: root-dev-token)..."
	@$(OPEN_CMD) http://vault.local

open-falco:
	@echo "Opening Falco UI (login: admin / admin)..."
	@$(OPEN_CMD) http://falco.local

open-litmus:
	@echo "Opening Litmus ChaosCenter (login: admin / litmus)..."
	@$(OPEN_CMD) http://litmus.local

runner-status:
	@echo "Checking GitHub Actions runner status..."
	@bash scripts/runner-vm-state.sh status

runner-logs:
	@bash scripts/runner-vm-state.sh logs

doctor:
	@bash scripts/doctor.sh

reclaim:
	@bash scripts/reclaim-disk.sh

snapshot:
	@if [ -z "$(STAGE)" ]; then \
		echo "Usage: make snapshot STAGE=7"; \
		exit 1; \
	fi
	@bash scripts/vm-snapshot.sh snapshot "$(STAGE)"

restore:
	@if [ -z "$(STAGE)" ]; then \
		echo "Usage: make restore STAGE=7"; \
		exit 1; \
	fi
	@bash scripts/vm-snapshot.sh restore "$(STAGE)"

snapshots:
	@bash scripts/vm-snapshot.sh list

aws-up:
	@echo "$(YELLOW)Provisioning AWS infrastructure...$(NC)"
	@echo "This takes 15-20 minutes and will incur AWS charges."
	@echo "Destroy when done: make aws-down"
	@echo ""
	@bash stages/stage-8-aws-migration/scripts/aws-spinup.sh

aws-down:
	@echo "$(YELLOW)Destroying AWS infrastructure...$(NC)"
	@echo "This stops all AWS charges for ClearLedger."
	@bash stages/stage-8-aws-migration/scripts/aws-destroy.sh

teardown:
	@echo "$(YELLOW)Tearing down ClearLedger...$(NC)"
	@bash scripts/teardown.sh
	@echo "$(GREEN)Done. VM deleted. No further charges.$(NC)"
