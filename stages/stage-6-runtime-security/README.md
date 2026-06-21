# Stage 6 — Runtime Security (Falco + Network Policies)

**Goal:** Trigger a Falco alert from a running pod, read it like an operator, then apply network policies without breaking the app.

## Am I ready?

- [ ] `make check-5` passes — Vault injecting secrets, app Secrets removed from Git/cluster
- [ ] Login and transactions still work at `http://clearledger.local`
- [ ] Platform pods stable (low RESTARTS)

**Done when:** `make check-6` passes and you have triggered at least one Falco alert (LAB-GUIDE §6.2 or §6.3).

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 6](../../docs/LAB-GUIDE.md#stage-6--runtime-security-falco)** — install Falco, custom rules, `make demo-6`, break-it scenarios, network policies, troubleshooting.

## Hands-on checkpoint

- Falco DaemonSet **`2/2`**; custom rules ConfigMap loaded
- **Critical Falco alert** from shell or sensitive-file scenario (§6.2 / §6.3) — you read pod, rule, and command in the UI
- Seven NetworkPolicies in `clearledger` (`default-deny-all` plus six allow-* rules); auth + notification health curls return **200**
- `make check-6` green

## What you can now claim

> **Detection at runtime closes the last gap on the node.** CI and Kyverno guard what gets deployed; Falco watches syscalls inside running pods; network policies block unauthorized pod-to-pod traffic.

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
