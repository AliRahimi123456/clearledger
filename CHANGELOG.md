# Changelog

All notable changes to ClearLedger are documented here.
Format: Keep a Changelog (keepachangelog.com)
Versioning: Semantic Versioning (semver.org)

---

## [1.0.0] — 2026

### Added
- Stage 0: Three-service fintech app (auth, ledger, notifications)
  running on MicroK8s via Multipass. Cross-platform (macOS/Linux/Windows).
- Stage 1: GitHub Actions CI pipeline with a self-hosted runner inside the VM.
- Stage 2: GitOps with ArgoCD. selfHeal enforces Git as truth.
- Stage 3: Full DevSecOps pipeline — Gitleaks, Semgrep, Checkov,
  Trivy, Syft, Grype, Cosign image signing, SBOM generation, DAST smoke.
- Stage 4: Kyverno admission control — 5 ClusterPolicies in Enforce mode.
  kube-bench CIS Benchmark scanning.
- Stage 5: HashiCorp Vault secret injection via agent sidecar.
  RBAC least-privilege service accounts. Secret rotation scripts.
- Stage 6: Falco runtime security — 5 custom ClearLedger rules.
  Kubernetes NetworkPolicy zero-trust segmentation.
  K8s API audit logging.
- Stage 7: Prometheus + Grafana + Loki observability stack.
  5 importable security dashboards. Alertmanager rules with runbooks.
- Stage 8: AWS migration with Terraform — VPC, EKS, ECR, RDS,
  ALB, Secrets Manager, IRSA, GuardDuty, CloudTrail, VPC Flow Logs.
  One-command spinup and destroy scripts.
- `clearledger-infra` repo on GitHub as the GitOps source of truth for ArgoCD.
- Stage health check script covering all 8 stages.
- Interview prep guide with weak/strong answers per stage.
- Compliance mapping to PCI-DSS, SOC2, CIS K8s, NIST 800-53, SLSA.
