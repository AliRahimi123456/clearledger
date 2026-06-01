# Stage 6 — Runtime Security (Falco + Network Policies)

> **The problem you felt in Stage 5:** Once a pod is running, nothing watches what happens inside it.
>
> **What changes here:** Falco detects shells, sensitive file reads, and suspicious network activity in real time. Network policies enforce zero-trust between services.

See **[LAB-GUIDE.md § Stage 6](../../docs/LAB-GUIDE.md#stage-6--runtime-security-falco)** for the full walkthrough.

---

## Quick path

```bash
bash stages/stage-6-runtime-security/scripts/install-falco.sh

# Guided demo (detection + how to read the alert): make demo-6
# UI: http://falco.local — login admin / password admin
# After demo: LAB-GUIDE §6.2 "After the demo — read your first alert"

# Manual break-it scenarios — §6.3 in lab guide
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -c auth-service -- /bin/sh -c "id && exit"

kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
make check-6
```

---

After applying network policies, verify apps still work (`make check-6`). If `auth-service` restarts, ensure `allow-postgres` is applied — run `make fix-65-prereqs` before Stage 6.5.

## → Next: [Stage 6.5 — Chaos Engineering](../stage-6.5-chaos-engineering/README.md)
