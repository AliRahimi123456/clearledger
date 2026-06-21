# Stage 7 — Security Observability (Grafana + Prometheus + Loki)

**Goal:** Correlate Kyverno denials, Falco alerts, and auth failures in Grafana — triggered by **your** terminal actions, not empty demo data.

## Am I ready?

- [ ] `make check-6` passes — Falco runtime detection working (Stage 6.5 optional)
- [ ] Platform pods stable — run `make doctor` if the VM has been up for days
- [ ] Completed [LAB-GUIDE §7.0](../../docs/LAB-GUIDE.md#70--free-node-resources-scale-down-litmus) if you ran Stage 6.5 (scale Litmus down)

**Done when:** LAB-GUIDE §7.6 checklist complete — dashboards show **your** Kyverno denial and Falco alert, plus portfolio screenshots 1–3.

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 7](../../docs/LAB-GUIDE.md#stage-7--security-observability)** — install stack (§7.1), verify Prometheus/Loki (§7.2), hands-on lab (§7.4), screenshots (§7.6).

## Hands-on checkpoint

- `bash stages/stage-7-observability/scripts/install-observability.sh` — Grafana **3/3**, Loki **1/1**
- §7.4 exercises: Kyverno violation + Falco CRITICAL + failed login visible in named dashboards
- Compliance dashboard: Policy Violations, Runtime Threats, Failed Auth Attempts all **> 0**
- `make check-7` green (proves stack up — **not** a substitute for §7.4 events)

## What you can now claim

> **Security observability ties controls to evidence** — you can trace a terminal action through Prometheus metrics and Loki logs into Grafana dashboards an auditor can read.

---

## Reference

| Step | Command / doc |
|---|---|
| Install | `bash stages/stage-7-observability/scripts/install-observability.sh` |
| Guided lab | `make demo-7` or `generate-dashboard-data.sh` |
| Dashboards | `stages/stage-7-observability/infra/dashboards/` |
| Helm values | `stages/stage-7-observability/infra/helm/` |

UI: `http://grafana.local` (admin / admin123) · Troubleshooting: [docs/troubleshooting.md § Stage 7](../../docs/troubleshooting.md#stage-7--observability-grafana--prometheus--loki)

---

## → Next: [Stage 7.5 — OpenTelemetry](../stage-7.5-opentelemetry/README.md) (optional) · [Stage 8 — AWS Migration](../stage-8-aws-migration/README.md)
