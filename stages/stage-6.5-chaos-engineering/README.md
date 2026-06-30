# Stage 6.5 — Chaos Engineering (Optional)

> **Skip to Stage 7** unless you want chaos/resilience depth. Nothing in Stages 7–8 requires Litmus.

**Full guide:** [LAB-GUIDE.md § Stage 6.5](../../docs/LAB-GUIDE.md#stage-65--chaos-engineering-optional)

## Skip to Stage 7 (default path)

After Stage 6:

```bash
make check-6
make snapshot STAGE=6
make snapshots
```

Open [Stage 7](../../docs/LAB-GUIDE.md#stage-7--security-observability).

## Only if you continue (~1 hour)

**What Litmus does:** Deletes a pod on purpose so you prove the app stays up (HTTP 200) and Kubernetes replaces the pod. Falco (Stage 6) **detects** bad behavior; Litmus **tests survival**.

### Steps in order

| Step | Section | What you do |
|------|---------|-------------|
| 1 | [§6.5.0](../../docs/LAB-GUIDE.md#650--before-you-start-fix-auth-service-restarts) | `make fix-65-prereqs` — auth **2/2 Ready** |
| 2 | [§6.5.1](../../docs/LAB-GUIDE.md#651--install-litmuschaos-operator-ui-cluster-connection) | Install Litmus — Overview **Active 1** |
| 3 | [§6.5.2](../../docs/LAB-GUIDE.md#652--run-your-first-experiment-pod-delete) | Pod-delete experiment — `curl` stays **200** |
| 4 | [§6.5.7](../../docs/LAB-GUIDE.md#657--health-check) | `make check-65`, snapshot |

**Copy-paste path:**

```bash
export GITHUB_OWNER=YOUR_GITHUB_USERNAME
make fix-65-prereqs
bash stages/stage-6.5-chaos-engineering/scripts/install-litmus.sh
open http://litmus.local               # admin / litmus
# §6.5.2 — ChaosHub → Pod Delete → Run
make check-65
make snapshot STAGE=65
```

**Optional:** [§6.5.3](../../docs/LAB-GUIDE.md#653--same-experiment-from-the-terminal-make-demo-65) — same test via `make demo-65` instead of the UI.

## Scripts

| Script | Purpose |
|--------|---------|
| `install-litmus.sh` | Operator + UI + ingress + connect cluster |
| `connect-litmus-infra.sh` | Re-connect UI (Overview shows 0 or PENDING) |
| `run-chaos.sh` | Used by `make demo-65` |

## Pass criteria

- Overview → **Infrastructures: Active 1**
- Pod-delete on `auth-service` (UI or `make demo-65`)
- During chaos: `curl http://clearledger.local/auth/health` → **200**
- After chaos: **2/2** auth pods Ready
- `make check-65` passes
