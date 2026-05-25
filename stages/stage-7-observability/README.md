# Stage 7 — Security Observability (Grafana + Prometheus + Loki)

> **The problem you felt in Stage 6:** You have controls at every layer.
> Pipeline gates. Kyverno policies. Vault secrets. Falco alerts. But they
> all live in separate UIs. There is no single place to answer: *Is our
> security posture getting better or worse?* You cannot prove anything to
> an auditor. You cannot alert on a trend. Security you cannot measure is
> security you cannot prove.
>
> **What changes here:** Every security signal feeds into Grafana dashboards.
> Falco alerts, Kyverno violations, pipeline scan results, failed auth attempts
> — all correlated in one place, with alert thresholds that page you before a
> trend becomes an incident.

---

## What You Will Learn

- How to install the Prometheus + Grafana observability stack on Kubernetes
- How to install Loki for log aggregation (Falco alerts, app logs)
- How to configure Falco to expose Prometheus metrics
- How to build four security dashboards that answer specific compliance questions
- The difference between a dashboard that reports and one that acts

---

## What You Are Installing

| Tool | Purpose |
|---|---|
| kube-prometheus-stack | Prometheus + Grafana + Alertmanager |
| Loki + Promtail | Log aggregation — Falco alerts, app logs |
| ServiceMonitor (Falco) | Scrapes Falco's Prometheus metrics endpoint |

---

## Prerequisites

- Stage 6.5 complete — chaos resilience verified

---

## Steps

### 1. Install Prometheus + Grafana

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.hosts[0]=grafana.local \
  --set grafana.ingress.ingressClassName=nginx \
  --set grafana.adminPassword=admin123

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=grafana \
  -n monitoring --timeout=180s
```

Access Grafana at `http://grafana.local` — login: `admin` / `admin123`

### 2. Install Loki

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=5Gi
```

### API audit logs (control plane) and Loki

Falco and app logs are not a substitute for **Kubernetes audit logs** (who ran
`kubectl exec`, who read `Secret` objects, who deleted workloads). Stage 7’s
Loki stack is the right sink once audit logs are written to a path or shipped
from CloudWatch.

Read: [docs/kubernetes-audit-logging.md](../../docs/kubernetes-audit-logging.md)
for policy examples, MicroK8s vs EKS notes, and how to correlate with LogQL-style
questions once Promtail (or CloudWatch export) ingests the stream.


In Grafana:
1. Go to **Configuration → Data Sources → Add Data Source**
2. Select **Loki**
3. URL: `http://loki:3100`
4. Save and Test

### 3. Configure Falco Metrics

```bash
kubectl patch configmap falco -n falco --type merge -p '{
  "data": {
    "falco.yaml": "metrics:\n  enabled: true\n  listen_port: 8765\n  interval: 1h\n"
  }
}'

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: falco-metrics
  namespace: falco
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: falco
  endpoints:
    - port: metrics
      interval: 30s
EOF
```

---

## The Four Dashboards

Build each dashboard in Grafana. Each one answers a specific question.

### Dashboard 1 — Security Event Timeline

*Question: What security events happened, when, and how severe?*

```
Panel: Falco CRITICAL alerts per hour (time series)
LogQL: {namespace="falco"} |= "CRITICAL" | count_over_time[1h]

Panel: Alert breakdown by rule (pie chart)
LogQL: {namespace="falco"} | json | rule != ""
       | sum by (rule) (count_over_time[1h])

Panel: Which pods triggered the most alerts (table)
LogQL: {namespace="falco"} | json
       | line_format "{{.k8s_pod_name}}"
       | count_over_time[24h]
```

**Alert threshold:** Any CRITICAL alert → immediate page (no threshold)

### Dashboard 2 — Kyverno Policy Violations

*Question: Is anything trying to run that shouldn't?*

```
Panel: Policy violations per day (bar chart)
PromQL: increase(kyverno_policy_results_total{result="fail"}[1d])

Panel: Top violating policies (table)
PromQL: topk(10, kyverno_policy_results_total{result="fail"})

Panel: Violation trend (is it increasing?) (time series)
PromQL: rate(kyverno_policy_results_total{result="fail"}[1h])
```

**Alert threshold:** More than 5 violations in 10 minutes → investigate

### Dashboard 3 — Pipeline Security Health

*Question: Is the pipeline catching threats before they reach production?*

```
Panel: Last 30 days CVE trend per service (time series)
  Source: Trivy scan results pushed to Prometheus pushgateway

Panel: Images signed vs total images deployed (gauge)
  Source: Cosign verification logs in Loki

Panel: Gitleaks findings per week (stat)
  Source: Gitleaks report artifacts in Loki
```

### Dashboard 4 — ClearLedger Service Health + Security

*Question: Is the application healthy and is it being attacked?*

```
Panel: HTTP request rate (time series)
PromQL: rate(http_requests_total{namespace="clearledger"}[5m])

Panel: 5xx error rate (time series)
PromQL: rate(http_requests_total{namespace="clearledger",status=~"5.."}[5m])

Panel: Failed login attempts (stat + alert)
LogQL: {namespace="clearledger", app="auth-service"}
       |= "Failed login attempt"
       | count_over_time[1m]
```

**Alert threshold:** More than 10 failed login attempts per minute → page

---

## Making Dashboards Actionable

A dashboard without an alert is a report. It shows what happened.
It does not help you when something is happening.

Rules for every panel:
1. **Has a threshold** — what number means "investigate"?
2. **Links to a runbook** — what do I do when this fires?
3. **Has a trend direction** — is the metric getting better or worse over time?

For the failed login panel:
```yaml
Alert: FailedLoginRateHigh
Condition: count_over_time > 10 per minute for 2 consecutive minutes
Severity: warning
Runbook: |
  1. Check auth-service logs: kubectl logs -n clearledger -l app=auth-service | grep "Failed login"
  2. Identify source IP from logs
  3. Check if IP is from known range (internal tooling vs external)
  4. If external and sustained: apply rate limiting via ingress annotation
  5. If credential stuffing: notify security team
```

---

## What the Complete System Looks Like

```
git push
  │
  ▼
[Gitleaks → Semgrep → Checkov → Trivy → Cosign] ── all scanning ──► [Loki]
  │ all pass
  ▼
[ArgoCD] syncs cluster ──────────────────────────────────────────► [Prometheus]
  │
  ▼
[Kyverno] admission control ─────────────────────────────────────► [Prometheus]
  │
  ▼
Pod starts → [Vault agent] injects secrets
  │
  ▼
App running → [Falco eBPF] ──────────────────────────────────────► [Loki]
  │
  ▼
Traffic → [Network policies] enforce zero-trust
  │
  ▼
Everything → [Grafana] ── dashboards ── alerts ── runbooks
```

---

## What Is Still Broken

Nothing in the system — from a security architecture perspective.
But you cannot yet trace a single request across all three services.
Prometheus and Loki show aggregates; they do not show the request journey.

**Stage 7.5 adds OpenTelemetry distributed tracing.**

Stage 8 migrates everything to AWS EKS. The tools, manifests, and policies
transfer directly — only the infrastructure underneath changes.

---

## 7.6 — DORA Metrics: Measuring Engineering Performance

DORA metrics — Deployment Frequency, Lead Time for Changes, Change Failure
Rate, and Mean Time to Recovery — are the industry standard for measuring
software delivery performance in 2026. Every serious engineering organization
tracks these four numbers.

| Metric | Plain English |
|---|---|
| Deployment frequency | How often do you ship? More often = lower risk per deploy |
| Lead time | How long from "code merged" to "code in production"? |
| Change failure rate | What % of deploys cause incidents? |
| MTTR | When something breaks, how fast do you recover? |

### Setup

```bash
# Enable ArgoCD metrics scraping
kubectl apply -f stages/stage-7-observability/infra/monitoring/argocd-servicemonitor.yaml

# Import the dashboard
# Grafana → Dashboards → Import → Upload:
# stages/stage-7-observability/infra/dashboards/06-dora-metrics.json
```

### Generate data

```bash
# Trigger 3 deployments to see frequency data
# Push a change → wait for ArgoCD sync → repeat 3 times

# Trigger a failure to see change failure rate
# Push a manifest with an invalid image tag
# Watch the failure appear in ArgoCD
# Revert → watch recovery
```

---

## What to Screenshot

After triggering **5 deployments** (push a small change → wait for ArgoCD sync → repeat), open the DORA dashboard:

Grafana → **Dashboards** → **Import** → `stages/stage-7-observability/infra/dashboards/06-dora-metrics.json`

The **Deployment Frequency** panel should show `5` (or your count).
Screenshot the dashboard with all **four DORA panels** visible in one frame.

In an interview, *"I track deployment frequency with ArgoCD metrics in Grafana — here is my dashboard"* is a different category of answer than *"we deploy frequently."* You have a number and a screen to back it up.

**Limitation:** true DORA Lead Time requires tracking from git commit timestamp
to production deployment. The ArgoCD `reconcile_duration` approximation shows
reconcile time, not full pipeline time. Acknowledge this honestly in interviews.

**MTTR note:** the dashboard uses ArgoCD reconcile duration as a proxy. True
MTTR requires incident timestamps from PagerDuty, Opsgenie, or similar.

---

## Before You Move On

Run the health check to confirm this stage is working:

```bash
bash scripts/health-check.sh 7
```

Green output = ready for the next stage.
Red output = something needs fixing. The message tells you what.

## ← Previous: [Stage 6.5 — Chaos Engineering](../stage-6.5-chaos-engineering/README.md)

## → Next: [Stage 7.5 — OpenTelemetry](../stage-7.5-opentelemetry/README.md)
