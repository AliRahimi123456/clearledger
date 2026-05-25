# Stage 7.5 — OpenTelemetry (Distributed Tracing)

> **The problem you felt in Stage 7:** Prometheus tells you request rates and
> error counts. Loki tells you what was logged. Neither shows you **why** a
> request was slow or **which service** in the chain caused the delay.
>
> **What changes here:** OpenTelemetry instruments all three ClearLedger services
> and exports distributed traces to Grafana Tempo. One transaction request
> shows spans across ledger-service → auth-service → postgres → redis as a
> single trace. This is the 2026 observability standard.

---

## What You Will Learn

- The three observability signals: metrics, logs, and traces
- How OpenTelemetry instruments Python/FastAPI without vendor lock-in
- How the OTel Collector routes telemetry to Tempo and Prometheus
- How to find a request trace in Grafana Explore
- Why W3C TraceContext headers link cross-service calls into one trace

---

## Metrics vs Logs vs Traces

| Signal | Answers | ClearLedger tool |
|---|---|---|
| Metrics | How often? How much? | Prometheus (Stage 7) |
| Logs | What happened? | Loki (Stage 7) |
| Traces | Where did time go? Which service called which? | OTel + Tempo (this stage) |

---

## Prerequisites

- Stage 7 complete — Prometheus, Grafana, and Loki running
- App images rebuilt with OTel instrumentation (see `app/*/requirements.txt`)

---

## Steps

### 1. Install Grafana Tempo

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install tempo grafana/tempo \
  --namespace monitoring \
  --set tempo.storage.trace.backend=local \
  --set tempo.storage.trace.local.path=/var/tempo \
  --set persistence.enabled=true \
  --set persistence.size=5Gi
```

### 2. Deploy OTel Collector and Tempo data source

```bash
kubectl apply -f stages/stage-7.5-opentelemetry/infra/otel/
```

This applies:
- `otel-collector.yaml` — receives traces from app services on port 4317
- `tempo.yaml` — PVC for trace storage
- `grafana-datasource-tempo.yaml` — auto-provisions Tempo in Grafana

### 3. Verify app pods have OTel env vars

The deployment manifests in `infra/manifests/` include:

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://otel-collector.monitoring.svc.cluster.local:4317"
- name: OTEL_SERVICE_NAME
  value: "auth-service"  # or ledger-service / notification-service
```

Redeploy if you built images before OTel was added:

```bash
# Trigger a CI pipeline run or manually rollout restart after new images are pushed
kubectl rollout restart deployment/auth-service -n clearledger
kubectl rollout restart deployment/ledger-service -n clearledger
kubectl rollout restart deployment/notification-service -n clearledger
```

### 4. Generate a trace

```bash
# Register first if needed
curl -s -X POST http://clearledger.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' | jq .

TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@clearledger.io","password":"SecurePass123"}' \
  | jq -r .access_token)

curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount": 5000, "direction": "credit"}' | jq .
```

### 5. View the trace in Grafana

1. Open http://grafana.local → **Explore**
2. Select **Tempo** data source
3. Search: `service.name = "ledger-service"`

Expected spans:
- `POST /transactions` (ledger-service)
  - `GET /verify` (auth-service via HTTPX)
  - SQL INSERT (postgres via SQLAlchemy)
  - Redis PUBLISH (if amount ≥ threshold)

**Aha moment:** expand the auth-service span and see the exact database query duration.

---

## What to Screenshot

Open Grafana → **Explore** → **Tempo** data source.
Search for `service.name = "ledger-service"`.
Click on any trace. Expand it.

You should see something like:

```
POST /transactions (ledger-service, total: ~45ms)
  GET /verify (auth-service call: ~12ms)
  INSERT INTO transactions (postgres: ~8ms)
```

**Screenshot this.** This is a **distributed trace**.

It shows you understand how microservices talk to each other at a depth that Prometheus metrics alone cannot show. In an interview, you are not saying "we use OpenTelemetry" — you are showing one transaction crossing auth, ledger, and the database.

---

## What a Trace Looks Like

```
POST /login (auth-service)
  └── SELECT * FROM users WHERE email=? (postgres, ~2ms)

POST /transactions (ledger-service)
  ├── GET /verify (auth-service, ~5ms)
  ├── INSERT INTO transactions (postgres, ~3ms)
  └── PUBLISH ledger-events (redis, if amount ≥ 10000)
```

Click any span in Tempo → **Logs** tab jumps to the matching Loki entry for that pod.

---

## What Is Still Broken

Everything runs on a single Multipass VM. Stage 8 migrates the same
architecture to AWS EKS — the OTel instrumentation transfers unchanged.

---

## Before You Move On

```bash
bash scripts/health-check.sh 7.5
```

## ← Previous: [Stage 7 — Observability](../stage-7-observability/README.md)

## → Next: [Stage 8 — AWS Migration](../stage-8-aws-migration/README.md)
