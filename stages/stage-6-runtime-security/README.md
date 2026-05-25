# Stage 6 — Runtime Security (Falco + Network Policies)

> **The problem you felt in Stage 5:** The pipeline enforces gates. Kyverno
> enforces policy at admission. Vault protects secrets. But once a pod is
> running — what happens inside it? A command injection flaw gives an attacker
> a shell. They read `/vault/secrets/database_url`. They make an outbound
> connection. They install tools. You have no idea.
>
> **What changes here:** Falco watches every syscall inside every running pod
> in real time. A shell spawn fires an alert in seconds. Network policies
> enforce zero-trust between services — no pod can talk to any pod it isn't
> explicitly allowed to reach.

---

## What You Will Learn

- How Falco uses eBPF to observe kernel syscalls without modifying containers
- How to write custom Falco rules for fintech-specific threat scenarios
- How to trigger Falco alerts deliberately (the break-and-detect workflow)
- How Kubernetes NetworkPolicy implements zero-trust at the pod level
- How to read a Falco alert and know what to investigate

---

## What You Are Installing

| Tool | Purpose |
|---|---|
| Falco | eBPF-based runtime threat detection |
| Falcosidekick | Routes Falco alerts to Grafana, Slack, PagerDuty |
| Falcosidekick UI | Web UI for browsing alerts |
| NetworkPolicy | Zero-trust network segmentation (built into K8s) |

---

## Prerequisites

- Stage 5 complete — Vault injecting secrets, no K8s Secrets with credentials

---

## Steps

### 1. Install Falco

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=modern_ebpf \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true \
  --set tty=true

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=falco \
  -n falco --timeout=180s
```

Add Falco UI ingress:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: falco-ingress
  namespace: falco
spec:
  ingressClassName: nginx
  rules:
    - host: falco.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: falco-falcosidekick-ui
                port:
                  number: 2802
EOF
```

Access Falco UI at `http://falco.local`

### 2. Apply Custom ClearLedger Rules

```bash
kubectl apply -f infra/falco/clearledger-rules.yaml

kubectl patch configmap falco -n falco --type merge -p '{
  "data": {
    "falco.yaml": "rules_file:\n  - /etc/falco/falco_rules.yaml\n  - /etc/falco/clearledger_rules.yaml\n"
  }
}'

kubectl rollout restart daemonset/falco -n falco
kubectl rollout status daemonset/falco -n falco
```

## 6.6 — Kubernetes Audit Logs: The API Layer

Falco watches **syscalls inside pods** — what processes do inside the container.

Kubernetes audit logs watch **API server calls** — what humans and services do *to the cluster*:
`kubectl exec`, `kubectl get secret`, pod creations, deletions, token requests.

An attacker who runs `kubectl exec` shows up in **K8s audit logs**.
The shell they spawn shows up in **Falco**.
Both are needed. They watch different layers.

### Enable audit logging (MicroK8s)

```bash
chmod +x scripts/enable-audit-logging.sh
bash scripts/enable-audit-logging.sh
```

### What an audit event contains

Key fields to understand:
- `requestURI` — the API path that was called
- `verb` — the action (get/list/watch/create/update/patch/delete)
- `user.username` — who made the call (human or service account)
- `objectRef` — what object was targeted (resource/namespace/name/subresource)
- `responseStatus.code` — HTTP status code (401/403 spikes are suspicious)
- `requestReceivedTimestamp` — when the API server received it

### Query secret access (last 24h)

In Grafana Explore (Loki), use structured JSON parsing:

```
{job="kubernetes-audit"} | json | resource="secrets"
```

Then open the dashboard: `stages/stage-7-observability/infra/dashboards/05-audit-log-analysis.json`.

### 3. Apply Network Policies

```bash
kubectl apply -f infra/manifests/netpol/network-policies.yaml

# Verify policies are active
kubectl get networkpolicy -n clearledger
```

---

## Trigger Falco Alerts (The Break-and-Detect Scenarios)

Each scenario below triggers a specific Falco rule. Run them in order.
After each one, check `http://falco.local` for the alert.

### Scenario 1 — Shell in a Running Pod

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- /bin/sh

# In Falco UI:
# CRITICAL: Shell spawned in ClearLedger container
# container=auth-service pod=auth-service-xxx cmd=/bin/sh
```

This is what a command injection exploit looks like from Falco's perspective.
In production this fires a PagerDuty alert and starts your incident response clock.

### Scenario 2 — Read a Sensitive File

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- cat /etc/passwd

# In Falco UI:
# CRITICAL: Sensitive file read in ClearLedger
# file=/etc/passwd container=auth-service
```

### Scenario 3 — Package Manager at Runtime

```bash
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- sh -c "wget -q ifconfig.me -O -"

# In Falco UI (two alerts):
# WARNING: Package manager executed in running container (wget)
# WARNING: Unexpected outbound connection from ClearLedger
```

### Scenario 4 — Verify Network Policies Block Cross-Service Traffic

```bash
# ledger-service should not be able to reach notification-service directly
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=ledger-service -o name | head -1) \
  -- sh -c "wget -q http://notification-service/ -O - --timeout=5"

# Expected: connection timed out
# The NetworkPolicy default-deny-all is working.
```

### 5. Run kube-bench (CIS Kubernetes Benchmark)

The compliance mapping references CIS controls — **kube-bench** is how you produce
evidence that specific controls pass or fail on *your* cluster.

```bash
kubectl delete job kube-bench -n default --ignore-not-found
kubectl apply -f infra/manifests/compliance/kube-bench-job.yaml
kubectl wait --for=condition=complete job/kube-bench -n default --timeout=300s
kubectl logs job/kube-bench -n default | head -120
```

MicroK8s users: prefix with `microk8s` if `kubectl` is not aliased.

The Job mounts host paths expected on a Linux worker (same pattern as the
[upstream kube-bench job](https://github.com/aquasecurity/kube-bench/blob/main/job.yaml)).
On managed clouds, use the kube-bench docs for **EKS / AKS / GKE** targets if
node results differ. Save the log output next to `docs/compliance-mapping.md`
when you run an audit exercise.

More detail: [infra/manifests/compliance/README.md](../../infra/manifests/compliance/README.md).

---

## Reading a Falco Alert

When Falco fires, the output contains everything you need to start investigation:

```
CRITICAL: Shell spawned in ClearLedger container
  user=nobody                    ← which user spawned the shell
  container=auth-service         ← which container
  image=DOCKER_USERNAME/...      ← which image
  pod=auth-service-abc123        ← exact pod name
  cmd=/bin/sh                    ← what was executed
```

With the pod name you can:
```bash
# Capture evidence before touching anything
kubectl logs auth-service-abc123 -n clearledger > evidence/logs.txt
kubectl exec auth-service-abc123 -n clearledger -- ps aux > evidence/processes.txt

# Isolate the pod (deny all traffic without killing it — preserve evidence)
kubectl label pod auth-service-abc123 -n clearledger incident=isolated
```

Then apply a NetworkPolicy that blocks all traffic to pods with `incident=isolated`.

---

## What the Cluster Looks Like Now

```
git push → [gates] → [ArgoCD] → [Kyverno] → Pod starts
                                                │
                                         [Vault agent] injects secrets
                                                │
                                         App running
                                                │
                              ┌─────────────────┤
                              │                 │
                        [Falco eBPF]     [NetworkPolicy]
                        watches syscalls  blocks unauthorized
                        fires on threats  connections
                              │
                        [Falcosidekick]
                        routes to Grafana (Stage 7)
```

---

## What Is Still Broken

You can see Falco alerts in the Falco UI. But:
- You have not proven the system **survives** failures — only that you detect them
- Events are not correlated with Kyverno violations or pipeline scan results
- There is no trend, no SLA, no way to prove controls to an auditor

**Stage 6.5 injects controlled failures and verifies resilience.**
**Stage 7 gives you the dashboards to measure and prove all of it.**

---

## Before You Move On

Run the health check to confirm this stage is working:

```bash
bash scripts/health-check.sh 6
```

Green output = ready for the next stage.
Red output = something needs fixing. The message tells you what.

## ← Previous: [Stage 5 — Secrets Management](../stage-5-secrets-management/README.md)

## → Next: [Stage 6.5 — Chaos Engineering](../stage-6.5-chaos-engineering/README.md)
