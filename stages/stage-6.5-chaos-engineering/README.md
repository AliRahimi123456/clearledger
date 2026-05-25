# Stage 6.5 — Chaos Engineering (LitmusChaos)

> **The problem you felt in Stage 6:** Falco detects threats inside running pods.
> Network policies block unauthorized connections. But you never proved the
> system **survives** failure — only that you can **detect** it.
>
> **What changes here:** LitmusChaos injects controlled failures — pod kills,
> network latency, memory pressure — and you verify ClearLedger keeps serving
> requests. Detection (Falco) and resilience (chaos) are different skills.
> EU DORA Pillar 3 requires documented resilience testing. This stage is that evidence.

---

## What You Will Learn

- The difference between **detection** (Falco) and **resilience** (chaos engineering)
- How to install LitmusChaos on Kubernetes
- How to run three failure experiments against ClearLedger
- How chaos test output satisfies DORA resilience testing requirements
- Why MTTR is measured from failure to recovery, not failure to alert

---

## Falco vs LitmusChaos

| Tool | Question it answers |
|---|---|
| Falco | Did a threat or anomaly occur? |
| LitmusChaos | Did the service stay available when something failed? |

Falco seeing a pod die is **detection**.
The service staying available while the pod dies is **resilience**.

---

## Prerequisites

- Stage 6 complete — Falco running, NetworkPolicies applied

---

## Steps

### 1. Install LitmusChaos

```bash
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
helm repo update

helm install chaos litmuschaos/litmus \
  --namespace litmus --create-namespace \
  -f stages/stage-6.5-chaos-engineering/infra/chaos/litmus-values.yaml

kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/litmus-install.yaml
kubectl apply -f stages/stage-6.5-chaos-engineering/infra/chaos/litmus-rbac.yaml
```

### 2. Run the automated resilience test

```bash
bash stages/stage-6.5-chaos-engineering/scripts/run-chaos.sh
```

This kills one auth-service replica (50% of 2 replicas) and verifies:
- `/auth/health` returns **200 during chaos** (availability)
- Both replicas are **Running after chaos ends** (recovery)

Save the script output — it is your DORA Pillar 3 evidence artifact.

### 3. Manual experiments (one at a time)

> **WARNING:** Never run all three experiments simultaneously.
> Always verify recovery before starting the next experiment.

All experiments are defined in:
`stages/stage-6.5-chaos-engineering/infra/chaos/clearledger-experiments.yaml`

| Experiment | Apply | Proves |
|---|---|---|
| Pod delete | `auth-service-pod-delete.yaml` | Replica redundancy (2 replicas) |
| Network latency | `ledger-service-network-latency` doc in experiments file | 503 on auth timeout, not hang |
| Memory hog | `notification-service-memory-hog` doc in experiments file | OOMKill + Redis subscription recovery |

---

## EU DORA Connection

DORA Pillar 3 — Digital Operational Resilience Testing (Articles 24–27)
requires documented resilience tests, not just vulnerability scans.

| DORA requirement | ClearLedger evidence |
|---|---|
| Resilience testing | LitmusChaos experiments in this stage |
| Test evidence | `run-chaos.sh` output saved to file |
| TLPT-style scenarios | Pod delete + network latency + memory pressure |

---

## What Is Still Broken

You can survive pod failures, but you cannot yet **trace** a request across
services or **measure** deployment frequency and MTTR in dashboards.

**Stage 7 adds observability. Stage 7.5 adds distributed tracing.**

---

## Before You Move On

```bash
bash scripts/health-check.sh 6.5
```

## ← Previous: [Stage 6 — Runtime Security](../stage-6-runtime-security/README.md)

## → Next: [Stage 7 — Observability](../stage-7-observability/README.md)
