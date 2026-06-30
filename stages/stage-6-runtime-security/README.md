# Stage 6 — Runtime Security (Falco + Network Policies)

**Goal:** Trigger a Falco alert on purpose, confirm it fired, apply network policies, pass `make check-6`.

**Feeling lost?** In the lab guide, jump to **[Stage 6 in plain English](../../docs/LAB-GUIDE.md#stage-6-in-plain-english-read-this-if-you-feel-lost)** — copy-paste commands and a “what done looks like” checklist. You do not need to read every Falco UI row.

## Am I ready?

- [ ] `make check-5` passes — Vault is injecting secrets and app Secrets are gone from Git and the cluster
- [ ] Login and transactions still work at `http://clearledger.local`
- [ ] Platform pods are stable with low restarts

**Order:** §6.1 install → §6.2 `make demo-6` → §6.4 netpol → §6.5 `make check-6` (§6.3 optional).

**You are done** when you triggered a Falco alert, applied netpol, and `make check-6` passes.

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 6](../../docs/LAB-GUIDE.md#stage-6--runtime-security-falco)** — install Falco, custom rules, `make demo-6`, break-it scenarios, network policies, troubleshooting.

## Hands-on checkpoint

- Falco DaemonSet **`2/2`**; custom rules ConfigMap loaded
- **Critical Falco alert** from shell or sensitive-file scenario (§6.2 / §6.3) — you read pod, rule, and command in the UI
- Seven NetworkPolicies in `clearledger` (`default-deny-all` plus six allow-* rules); auth + notification health curls return **200**
- `make check-6` green

## What you can now claim

> CI and Kyverno guard what gets deployed. Falco watches syscalls inside running pods. Network policies block traffic that should not happen between services.

---

## Reference

| Command | Purpose |
|---|---|
| `bash stages/stage-6-runtime-security/scripts/install-falco.sh` | Install Falco + custom rules |
| `make demo-6` | Guided alert demo → Falco UI at `http://falco.local` |
| `kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml` | Stage 6 netpol (after Falco exercises) |

If auth restarts after netpol, run `make fix-65-prereqs` before Stage 6.5.

---

## → Next: [Stage 6.5 — Chaos Engineering](../stage-6.5-chaos-engineering/README.md) (optional) · [Stage 7 — Observability](../stage-7-observability/README.md)
