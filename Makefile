# Indentation: tabs only
.PHONY: help setup check stage teardown aws-up aws-down \
	stage-0 stage-1 stage-2 stage-3 stage-4 \
	stage-5 stage-6 stage-7 stage-8 \
	integration-up integration-down integration-test open-local-ui \
	open-ui open-argocd open-grafana open-vault open-falco \
	check-0 check-1 check-2 check-3 check-4 check-5 check-6 check-7 check-65 check-75 check-all \
	runner-status runner-logs

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
	@echo "  make stage-0      Open Stage 0 README (start here)"
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
	@echo "$(CYAN)Health checks:$(NC)"
	@echo "  make check        Check the current stage (prompts for stage number)"
	@echo "  make check-0      Check Stage 0 specifically"
	@echo "  make check-65     Check Stage 6.5 (chaos engineering)"
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
	@echo "Next: make stage-0"

stage-0:
	@echo "$(CYAN)Stage 0 — Raw Kubernetes$(NC)"
	@echo "Goal: ClearLedger is running. You deployed it manually."
	@echo ""
	@cat stages/stage-0-raw-kubernetes/README.md | head -30
	@echo ""
	@echo "Full guide: stages/stage-0-raw-kubernetes/README.md"
	@echo "Lab guide:  docs/LAB-GUIDE.md#stage-0"

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
	@cat stages/stage-7-observability/README.md | head -20
	@echo ""
	@echo "Full guide: stages/stage-7-observability/README.md"

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
	@echo "Opening Falco UI..."
	@$(OPEN_CMD) http://falco.local

runner-status:
	@echo "Checking GitHub Actions runner status..."
	@multipass exec clearledger -- \
	  sudo systemctl status actions.runner.*.service --no-pager 2>/dev/null \
	  || echo "Runner service not found. See Stage 1 README for setup."

runner-logs:
	@multipass exec clearledger -- \
	  journalctl -u actions.runner.*.service --lines=50 --no-pager 2>/dev/null \
	  || echo "Runner not installed. See Stage 1 README."

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
