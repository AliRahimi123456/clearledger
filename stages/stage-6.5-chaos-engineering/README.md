# Stage 6.5 — Chaos Engineering

> Falco **detects**. Chaos **proves you survive**.

**Full guide (UI walkthrough):** [LAB-GUIDE.md § Stage 6.5](../../docs/LAB-GUIDE.md#stage-65--chaos-engineering-optional)

## What you are learning (not just installing)

| Concept | Meaning |
|---------|---------|
| **Chaos engineering** | Deliberately break something small, watch if users still succeed |
| **Resilience** | `auth-service` has 2 replicas — killing one should not kill login |
| **ChaosCenter UI** | Where you *see* experiments; useless until the cluster is **connected** |
| **Terminal** | Proves availability with `curl` while the UI shows the experiment timeline |

**Empty Litmus UI?** The control plane was running but **no agent** was registered with your cluster. The install script now runs `connect-litmus-infra.sh` to fix that automatically.

## Steps (≈30 minutes)

### 1. Stabilize auth (required)

```bash
make fix-65-prereqs
kubectl get pods -n clearledger -l app=auth-service   # 2 pods, 2/2 Ready
```

### 2. Install + connect Litmus

```bash
# If you changed the admin password at first login:
export LITMUS_PASSWORD='your-password'

bash stages/stage-6.5-chaos-engineering/scripts/install-litmus.sh
```

**Checkpoints after login:**

| Where | What you must see |
|-------|-------------------|
| **Overview** | Infrastructures: **Active 1** |
| **Environments → clearledger-lab → clearledger-cluster** | Status **Active** (not **Pending**) |

**Navigation guide:** [LAB-GUIDE §6.5.1c](../../docs/LAB-GUIDE.md#651c--how-to-navigate-the-litmus-ui-read-before-you-click)

If Overview still says **0**, re-run:

```bash
export LITMUS_PASSWORD='your-password'
bash stages/stage-6.5-chaos-engineering/scripts/connect-litmus-infra.sh
```

**Stuck on PENDING?** See [LAB-GUIDE §6.5.1d](../../docs/LAB-GUIDE.md#651d--why-infrastructure-shows-pending).

### 3. Learn in the UI (main exercise)

Open **http://litmus.local** → log in → follow the lab guide:

| Guide section | What you do |
|---------------|-------------|
| [§6.5.1](../../docs/LAB-GUIDE.md#651--install-litmuschaos-operator-ui-cluster-connection) | Install + connect (one script) |
| [§6.5.1c](../../docs/LAB-GUIDE.md#651c--how-to-navigate-the-litmus-ui-read-before-you-click) | Sidebar, **Active** infrastructure, click order |
| [§6.5.2](../../docs/LAB-GUIDE.md#652--how-to-use-chaoshub-and-run-your-first-chaos-experiment) | **ChaosHubs → Pod Delete** — version-agnostic wizard + terminals |

### 4. Optional — same test as YAML

```bash
make demo-65
```

See [LAB-GUIDE §6.5.3](../../docs/LAB-GUIDE.md#653--same-experiment-from-the-terminal-make-demo-65). Use after the UI exercise.

## Scripts

| Script | Purpose |
|--------|---------|
| `install-litmus.sh` | Operator + UI + ingress + **connect cluster** |
| `connect-litmus-infra.sh` | Re-connect UI to cluster (empty Overview fix) |
| `run-chaos.sh` | `make demo-65` — YAML path |

## Pass criteria

- Overview → **Infrastructures: Active 1**
- You ran **pod-delete** on `auth-service` from the UI (or `make demo-65`)
- During chaos: `curl http://clearledger.local/auth/health` → **200**
- After chaos: **2/2** auth pods Ready
- You can explain: *Falco detects; chaos proves we survive*
