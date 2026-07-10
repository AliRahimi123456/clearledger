# ClearLedger Security Controls: Compliance Mapping

Every control implemented in this lab maps to at least one compliance framework.
Use this table to explain your security posture to auditors, customers, and interviewers.

---

## Table of Contents

- [Control Matrix](#control-matrix)
  - [OWASP Project Mapping (DAST)](#owasp-project-mapping-dast)
- [Framework Reference](#framework-reference)
  - [PCI-DSS v4.0](#pci-dss-v40-payment-card-industry-data-security-standard)
  - [SOC2 Trust Service Criteria](#soc2-trust-service-criteria)
  - [CIS Kubernetes Benchmark 1.8](#cis-kubernetes-benchmark-18)
  - [NIST 800-53 Rev 5](#nist-800-53-rev-5)
  - [SLSA](#slsa-supply-chain-levels-for-software-artifacts)
  - [Executive Order 14028](#executive-order-14028-us-cyber-executive-order)
- [Audit Evidence Locations](#audit-evidence-locations)
- [EU DORA — Regulation 2022/2554](#eu-digital-operational-resilience-act-dora--regulation-20222554)
  - [Pillar 1: ICT Risk Management](#pillar-1--ict-risk-management-articles-516)
  - [Pillar 2: ICT-Related Incident Management](#pillar-2--ict-related-incident-management-articles-1723)
  - [Pillar 3: Digital Operational Resilience Testing](#pillar-3--digital-operational-resilience-testing-articles-2427)
  - [Pillar 4: ICT Third-Party Risk Management](#pillar-4--ict-third-party-risk-management-articles-2844)
  - [Pillar 5: Information Sharing](#pillar-5--information-sharing-article-45)
  - [DORA vs Existing Frameworks](#dora-vs-existing-frameworks--overlap-reference)

---

## Control Matrix

| Control | Tool | Stage | PCI-DSS | SOC2 | CIS Kubernetes | NIST 800-53 | SLSA / EO 14028 |
|---|---|---|---|---|---|---|---|
| Secrets detection (pre-commit) | Gitleaks | 3 | 6.2 | CC8.1 | — | IA-5(7) | — |
| SAST on every push | Semgrep | 3 | 6.3.2 | CC7.1 | — | SA-11 | — |
| Dependency vulnerability scan | Trivy (SCA) | 3 | 6.3.3 | CC7.1 | — | RA-5 | — |
| IaC misconfiguration scan | Checkov | 3 | 6.3.1 | CC6.1 | 5.2.x | CM-6 | — |
| DAST smoke (runtime API) | `scripts/dast/smoke.sh` | 3 | 6.4.1 | CC7.1 | — | SA-11 | — |
| Dynamic application security testing | OWASP ZAP | 3 | 6.4.1 | CC7.1 | — | SA-11 | — |
| BOLA / IDOR API testing | `stages/stage-3-security-gates/dast/fintech-test-payloads.py` | 3 | 6.4.1 | CC7.1 | — | SA-11 | — |
| Container image signing | Cosign | 3 | 6.3 | CC6.1 | — | SA-12 | SLSA Level 2 |
| SBOM generation | Syft | 3 | 6.3.3 | CC6.1 | — | SA-12 | EO 14028 §4(e) |
| Least-privilege service accounts | K8s RBAC Roles (`infra/manifests/rbac/rbac.yaml`) | 0 | — | CC6.3 | CIS K8s 5.1.5 | AC-6 | — |
| No API token automounting | `automountServiceAccountToken: false` (Stage 0 workloads) | 0 | — | CC6.3 | CIS K8s 5.1.6 | AC-6 | — |
| Developer read-only access | `clearledger-viewer` Role + SA | 0 | — | CC6.3 | — | AC-6 | — |
| Non-root containers enforced | Kyverno | 4 | 6.5 | CC6.3 | 5.2.6 | AC-6 | — |
| Resource limits required | Kyverno | 4 | — | A1.1 | 5.2.4 | SC-6 | — |
| Privilege escalation blocked | Kyverno | 4 | 6.5 | CC6.3 | 5.2.5 | AC-6 | — |
| All capabilities dropped | Kyverno | 4 | 6.5 | CC6.3 | 5.2.7 | AC-6 | — |
| Signed images required | Kyverno | 4 | 6.3 | CC6.1 | — | SA-12 | SLSA Level 2 |
| CIS Kubernetes Benchmark | kube-bench | 4 | — | CC7.1 | CIS K8s Benchmark v1.8 | SI-4 | — |
| Secrets at rest encrypted | HashiCorp Vault | 5 | 3.5 | CC6.1 | — | SC-28 | — |
| Secrets never in Git/etcd | HashiCorp Vault | 5 | 3.4, 6.2 | CC6.1 | — | IA-5 | — |
| Secret rotation on schedule | Vault KV versioning + CronJob | 5 | 8.3.9 | — | — | IA-5 | — |
| Secret version history | Vault KV metadata | 5 | — | CC6.1 | — | AU-2 | — |
| Zero-downtime rotation | Vault agent renewal | 5 | — | — | — | — | Operational excellence |
| Runtime threat detection | Falco | 6 | 10.7 | CC7.2 | — | SI-4 | — |
| Network segmentation (zero-trust) | NetworkPolicy | 6 | 1.3 | CC6.6 | 5.3.2 | SC-7 | — |
| CIS benchmark evidence | kube-bench Job | 6 | — | CC7.1 | CIS K8s Benchmark | SI-4 | — |
| Audit logging | Loki + app logs | 7 | 10.2 | CC7.3 | — | AU-2 | — |
| API audit policy (control plane) | See docs | 7–8 | 10.2 | CC7.3 | — | AU-2 | — |
| API server audit logging | K8s Audit + Loki | 6–7 | 10.2 | CC7.3 | — | AU-2 | — |
| Audit log retention (lab) | audit-log-maxage=30 | 6 | 10.7 | — | — | AU-11 | — |
| Privileged access monitoring | Audit log alert | 7 | — | CC6.3 | — | AU-6 | — |
| Account-level threat detection | GuardDuty | 8 | 10.6 | CC7.2 | — | SI-4 | — |
| All API calls audited | CloudTrail | 8 | 10.2 | CC7.3 | — | AU-2 | — |
| Network traffic logged | VPC Flow Logs | 8 | 10.6 | — | CIS AWS Foundations | SI-4 | — |
| Log encryption at rest | KMS | 8 | 3.4 | — | CIS AWS Foundations | SC-28 | — |
| Annual key rotation | KMS key rotation | 8 | 3.6 | — | CIS AWS Foundations | SC-12 | — |
| Infrastructure compliance rules | AWS Config | 8 | — | — | CIS AWS Foundations | CM-6 | — |
| Log retention 12 months | S3 lifecycle | 8 | 10.7 | — | CIS AWS Foundations | AU-11 | — |
| Pod IAM without static keys (AWS) | IRSA + permission boundary (Stage 8 Terraform) | 8 | — | CC6.1 | — | AC-3 | — |
| Security observability | Grafana | 7 | 10.6 | CC7.2 | — | SI-4 | — |
| Alerting on security events | Alertmanager | 7 | 10.6 | CC7.2 | — | IR-6 | — |
| Distributed tracing | OpenTelemetry + Tempo | 7.5 | — | — | — | — | ISO 27001 A.12.4 |
| Vendor-neutral telemetry | OTel SDK (CNCF standard) | 7.5 | — | — | — | NIST SP 800-137 | — |
| Chaos engineering resilience tests | LitmusChaos experiments | 6.5 | — | — | — | — | DORA Art.24 |
| Resilience test evidence artifacts | `run-chaos.sh` output | 6.5 | — | — | — | — | DORA Art.25 |
| SLSA build provenance | cosign attest | 3 | — | — | — | — | SLSA Level 2 |
| Build source verification | Kyverno provenance policy | 4 | — | — | — | — | EO 14028 §4(e) |
| EU CRA artifact attestation | Cosign + SLSA predicate | 3 | — | — | — | — | EU CRA Article 13 |
| Deployment frequency tracking | ArgoCD metrics + Grafana | 7 | — | — | — | — | DORA Deployment Frequency |
| Lead time measurement | ArgoCD reconcile metrics | 7 | — | — | — | — | DORA Lead Time for Changes |
| Change failure rate | ArgoCD sync failure rate | 7 | — | — | — | — | DORA Change Failure Rate |
| MTTR tracking | ArgoCD + Falco metrics | 7 | — | — | — | — | DORA MTTR |
| Automated dependency monitoring | Renovate Bot | 3 | 6.3.3 | CC7.1 | — | SI-2 | DORA Pillar 4 |
| Proactive CVE remediation | Renovate vulnerability alerts | 3 | 6.3.3 | CC7.1 | — | SI-2 | — |

### OWASP project mapping (DAST)

| Activity | Tool / script | OWASP reference |
|---|---|---|
| Dynamic application security testing | OWASP ZAP | OWASP ASVS V4.0 |
| BOLA / IDOR testing | `stages/stage-3-security-gates/dast/fintech-test-payloads.py` | OWASP API Security Top 10 |

**Evidence, not claims:** run kube-bench ([LAB-GUIDE §4.7](LAB-GUIDE.md#47--cis-benchmark-evidence-kube-bench)), DAST smoke ([scripts/dast/README.md](../scripts/dast/README.md)), ZAP + fintech DAST ([stages/stage-3-security-gates/README.md](../stages/stage-3-security-gates/README.md) §3.5), and configure API audit shipping as described in [kubernetes-audit-logging.md](kubernetes-audit-logging.md).

---

## Framework Reference

### PCI-DSS v4.0 (Payment Card Industry Data Security Standard)
- **3.4, 3.5**: Protect stored cardholder data
- **6.2**: Bespoke and custom software are protected from attacks
- **6.3.x**: Security vulnerabilities are identified and addressed
- **10.x**: Log and monitor all access to system components

### SOC2 Trust Service Criteria
- **CC6.x**: Logical and Physical Access Controls
- **CC7.x**: System Operations (monitoring, detection, response)
- **CC8.1**: Change management includes security assessment
- **A1.1**: Availability controls (resource limits)

### CIS Kubernetes Benchmark 1.8

| Control | Tool | Framework |
|---|---|---|
| CIS Kubernetes Benchmark | kube-bench | CIS K8s Benchmark v1.8 |

- **5.2.4**: Minimize the admission of containers wishing to share the host process ID namespace
- **5.2.5**: Minimize the admission of containers with allowPrivilegeEscalation
- **5.2.6**: Minimize the admission of root containers
- **5.2.7**: Minimize the admission of containers with the NET_RAW capability
- **5.3.2**: Ensure that all Namespaces have Network Policies defined

### NIST 800-53 Rev 5
- **AC-6**: Least Privilege
- **AU-2**: Event Logging
- **IA-5**: Authenticator Management
- **IR-6**: Incident Reporting
- **RA-5**: Vulnerability Monitoring and Scanning
- **SA-11**: Developer Testing and Evaluation
- **SA-12**: Supply Chain Protection
- **SC-6**: Resource Availability
- **SC-7**: Boundary Protection
- **SC-28**: Protection of Information at Rest
- **SI-4**: System Monitoring

### SLSA (Supply-chain Levels for Software Artifacts)
- **SLSA Level 2** requirements met by: GitHub Actions CI (self-hosted runner), Cosign signing, SBOM with Syft

### Executive Order 14028 (US Cyber Executive Order)
- **§4(e)** SBOM requirement: met by Syft generating SPDX-format SBOMs per build

---

## Audit Evidence Locations

When an auditor asks for evidence:

| Control | Evidence Location |
|---|---|
| Secrets scan runs on every commit | GitHub Actions run logs + gitleaks-report.json artifacts |
| SAST on every push | GitHub Actions run logs + semgrep-results.json artifacts |
| Images are scanned before deployment | GitHub Actions + trivy-*-results.json artifacts |
| Images are signed | Cosign signature in registry (verify with `cosign verify`) |
| SBOM exists per build | sbom-*.json artifacts in GitHub Actions |
| Non-root enforced | `kubectl get clusterpolicy disallow-root-containers` |
| Policy violations | `kubectl get policyreport -A` |
| Secrets not in Git | `git log --all --full-history -- '*secret*'` (should show no credential values) |
| Secrets not in K8s | `kubectl get secrets -n clearledger` (no app secrets after Stage 5) |
| Runtime events logged | Falco UI at falco.local / Loki in Grafana |
| Network segmentation | `kubectl get networkpolicy -n clearledger` |
| SLSA provenance attestation | `cosign verify-attestation --type slsaprovenance --key infra/cosign.pub IMAGE` |
| Distributed traces | Grafana → Explore → Tempo data source |
| DORA metrics | Dashboard `06-dora-metrics.json` at http://grafana.local |

---

## EU Digital Operational Resilience Act (DORA) — Regulation 2022/2554

DORA applies to financial entities in the EU since January 17, 2025.
It is a regulation (directly binding in all 27 EU member states, not
requiring national implementation). It applies to any fintech, bank,
investment firm, insurance company, or ICT provider serving EU financial entities.

> **Note:** ClearLedger is a lab. A production DORA implementation requires
> formal gap assessments, legal review, and regulatory registration. This mapping
> demonstrates understanding, not formal compliance.

### Pillar 1 — ICT Risk Management (Articles 5–16)

| DORA Requirement | ClearLedger Control | Stage | Evidence |
|---|---|---|---|
| ICT risk identification | Trivy CVE scanning | 3 | `trivy-*.json` artifacts in GitHub Actions |
| Configuration risk assessment | Checkov IaC scanning | 3 | `checkov-*.json` artifacts in GitHub Actions |
| Access risk mitigation | Kyverno RBAC policies | 4 | `kubectl get clusterpolicy` |
| Least-privilege access | RBAC service accounts | 0 | `infra/manifests/rbac/rbac.yaml` |
| Secrets protection | HashiCorp Vault | 5 | No credentials in Git/etcd |
| Change management controls | ArgoCD GitOps (selfHeal) | 2 | `argocd app get clearledger` |

### Pillar 2 — ICT-Related Incident Management (Articles 17–23)

| DORA Requirement | ClearLedger Control | Stage | Evidence |
|---|---|---|---|
| Incident detection capability | Falco runtime security | 6 | http://falco.local |
| Incident classification | Falco alert priorities (CRITICAL/WARNING) | 6 | `infra/falco/clearledger-rules.yaml` |
| Incident notification | Alertmanager rules with runbooks | 7 | `stages/stage-7-observability/infra/monitoring/alerting-rules.yaml` |
| Incident audit trail | Loki log aggregation + K8s audit logs | 7 | http://grafana.local |
| Post-incident analysis | Grafana Security Event Timeline | 7 | Dashboard `01-security-event-timeline.json` |
| Incident response procedures | Documented runbook annotations | 7 | `alerting-rules.yaml` annotations |

### Pillar 3 — Digital Operational Resilience Testing (Articles 24–27)

| DORA Requirement | ClearLedger Control | Stage | Evidence |
|---|---|---|---|
| Vulnerability assessments | Trivy + Grype CVE scanning | 3 | Pipeline artifacts |
| Security testing of applications | DAST smoke tests (`fintech-test-payloads.py`) | 3 | `stages/stage-3-security-gates/dast/` |
| TLPT (threat-led penetration testing) | Falco break-and-detect scenarios | 6 | `stages/stage-6-runtime-security/README.md` |
| CIS Benchmark compliance | kube-bench scanning | 4 | `stages/stage-4-admission-control/scripts/run-kube-bench.sh` |
| Pipeline resilience testing | Deliberate gate failure tests | 3 | `stages/stage-3-security-gates/README.md` §3.4 |
| Chaos engineering resilience tests | LitmusChaos experiments | 6.5 | `stages/stage-6.5-chaos-engineering/scripts/run-chaos.sh` |
| Resilience test evidence artifacts | `run-chaos.sh` output | 6.5 | `bash stages/stage-6.5-chaos-engineering/scripts/run-chaos.sh` |

### Pillar 4 — ICT Third-Party Risk Management (Articles 28–44)

| DORA Requirement | ClearLedger Control | Stage | Evidence |
|---|---|---|---|
| Third-party component inventory | SBOM generation (Syft, SPDX format) | 3 | `sbom-*.json` artifacts |
| Third-party vulnerability monitoring | Grype SBOM scanning | 3 | `grype-*.json` artifacts |
| Third-party component integrity | Cosign image signing | 3 | `cosign verify IMAGE` |
| Third-party supply chain attestation | SLSA provenance attestation | 3+ | `cosign verify-attestation --type slsaprovenance` |
| Cloud provider risk monitoring | GuardDuty (AWS Stage 8) | 8 | AWS Console |
| Critical third-party oversight | Trivy base image scanning | 3 | Pipeline Trivy step |

### Pillar 5 — Information Sharing (Article 45)

| DORA Requirement | ClearLedger Control | Stage | Evidence |
|---|---|---|---|
| Machine-readable vulnerability disclosure | SBOM in SPDX-JSON format | 3 | `sbom-*.json` |
| Security posture documentation | Compliance mapping (this document) | All | `docs/compliance-mapping.md` |
| Security posture visibility | Compliance Posture dashboard | 7 | Dashboard `04-compliance-posture.json` |
| Audit-ready evidence generation | All artifacts stored per build | 3 | Pipeline artifacts |

### DORA vs Existing Frameworks — Overlap Reference

| Control | PCI-DSS | SOC2 | CIS K8s | DORA |
|---|---|---|---|---|
| Falco runtime detection | 10.7 | CC7.2 | — | Pillar 2 Art.17 |
| Vault secrets management | 3.5 | CC6.1 | — | Pillar 1 Art.9 |
| Trivy CVE scanning | 6.3.3 | CC7.1 | — | Pillar 1 Art.8 |
| Kyverno admission control | 6.5 | CC6.3 | 5.2.6 | Pillar 1 Art.9 |
| SBOM generation | 6.3.3 | CC6.1 | — | Pillar 4 Art.28 |
| K8s audit logging | 10.2 | CC7.3 | — | Pillar 2 Art.17 |
| ArgoCD GitOps | — | CC8.1 | — | Pillar 1 Art.6 |
