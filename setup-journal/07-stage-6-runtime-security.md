# Stage 6 — Runtime Security (Falco)

**Goal (from the book):** Stages 3–5 secure what gets *deployed* — code, images, admission,
secrets. None of them watch what already-running, already-approved software actually *does*
after it starts. Falco fills that gap using eBPF to watch real Linux syscalls in real time —
catching things like a shell spawning inside an app container, which would mean something is
very wrong even if every earlier gate passed cleanly. Network policies then add pod-to-pod
firewalling on top.

**Status: ✅ Done.** `make check-6` → 14 passed, 0 failures. Real Falco alert triggered and
read like an on-call engineer would; all 7 network policies applied and verified not to break
the real app; a genuine cross-service block proven with a real timeout.

---

## Readiness check

`make check-5` confirmed passing before starting.

## A real, useful infrastructure fix: `helm` needed a real wrapper

This was flagged as a known gap all the way back in Stage 0 (`kubectl` and `argocd` got real
`~/.local/bin` wrapper scripts early on; `helm` was deliberately left as a `.bashrc` alias
since it wasn't needed yet). It finally mattered today: `bash
stages/stage-6-runtime-security/scripts/install-falco.sh` failed immediately with `helm:
command not found`, even though `helm version` worked fine typed directly in the terminal —
classic alias-vs-real-command gap, since a script run via `bash script.sh` starts a fresh,
non-interactive shell that never sources `.bashrc`.

Root-caused precisely: `type helm` showed `helm is aliased to 'microk8s helm3'`. Fixed
permanently with a real wrapper script, same pattern as `kubectl`/`argocd`:
```bash
cat > ~/.local/bin/helm << 'EOF'
#!/usr/bin/env bash
exec microk8s helm3 "$@"
EOF
chmod +x ~/.local/bin/helm
```
Confirmed via `which helm` (now a real file) and `helm version` (still correct), then the
install script ran cleanly. This fix should also help Stage 7 (Prometheus/Grafana, also
Helm-installed).

## Incident: pasted book prose directly into the terminal

Before the `helm` fix was found, a large chunk of the book's own narrative text (section
headers, prose sentences, tables) got pasted directly into the terminal alongside the real
commands, producing dozens of harmless `command not found` errors (`Do: command not found`,
`§6.1:: command not found`, etc.). No actual damage — purely noise. Worth remembering for
future stages: **only the exact text inside a fenced code block should ever be typed into the
terminal**, never the surrounding explanatory sentences. Re-established this rule explicitly
partway through the stage and the rest of the session went cleanly.

One side effect: Scenario 4 (the optional cross-service network-block test) got run once by
accident *before* network policies were actually applied, producing a misleading
`BLOCKED (expected): HTTP Error 404: Not Found` — a 404 actually means the connection
*succeeded* (just hit a non-existent route), not that anything was blocked. Re-ran it properly
after §6.4 for a correct result (see below).

## §6.1 — Installed Falco + Falcosidekick UI

```bash
bash stages/stage-6-runtime-security/scripts/install-falco.sh
```
(After the `helm` wrapper fix) installed cleanly — `STATUS: deployed`, custom rules ConfigMap
and ingress both created. Verified:
```bash
kubectl get pods -n falco
```
`falco-mrfgf` (the DaemonSet pod) `2/2 Running`; Falcosidekick, the UI, Redis, and the
k8s-metacollector all `1/1 Running`.

**Verified custom rules actually loaded** (the book explicitly warns this step matters — a
silent rule-load failure would make later steps look like they passed when nothing was really
tested):
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=200 | grep 'rules.d/clearledger_rules'
# → clearledger_rules.yaml | schema validation: ok
```

## §6.2 — Guided demo (`make demo-6`)

```bash
make demo-6
```
Ran cleanly end-to-end: opened `http://falco.local` (login `admin`/`admin`), simulated a
post-exploit shell spawn (`kubectl exec ... sh -c "id && exit"` inside a real `auth-service`
pod), and got a genuine confirmed detection:
```
✓ Runtime detection confirmed
Rule:   Shell Spawned in ClearLedger Container
Output: ... Critical CRITICAL: Shell spawned in ClearLedger container
        (user=<NA> container=<NA> pod=auth-service-6fdb87bdbf-7gfzg cmd=sh -c id && exit)
        k8smeta_pod_name=auth-service-6fdb87bdbf-7gfzg k8smeta_ns_name=clearledger
```

**Reading it like an on-call engineer, per the book's own framing:**
- `Critical` priority — correctly the most severe tier, not the routine `Notice` noise from
  ArgoCD
- `Rule: Shell Spawned in ClearLedger Container` — the specific custom rule that matched
- `cmd=sh -c id && exit` — the forensic evidence of exactly what ran
- `k8smeta_pod_name=...`, `k8smeta_ns_name=clearledger` — exactly where, for incident response

§6.3 (manual break-it scenarios) skipped per the book's own guidance — same detections,
redundant once `make demo-6` already succeeded.

**Screenshot difficulty, resolved via the terminal fallback:** the Falcosidekick UI's Events
tab was already buried under ~10 minutes of repeating, expected `postgres-0` "Sensitive File
Read" noise (a known, documented distractor — `postgres-0` reads `/etc/passwd` on a loop) by
the time I went to screenshot, and `Ctrl+F` browser search found nothing (likely due to
virtualized/paginated table rendering). Used the book's own documented fallback instead —
confirmed identical from Falco's raw logs, then screenshotted that:
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=500 | grep 'Shell Spawned'
```
Returned the full structured JSON alert, `"priority":"Critical"`,
`"rule":"Shell Spawned in ClearLedger Container"`. Screenshot saved:
`stage6-shell-spawned-alert.png`.

## §6.4 — Applied network policies

```bash
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
kubectl get networkpolicy -n clearledger
```
All 7 policies confirmed: `default-deny-all` plus 6 `allow-*` rules (auth-service,
ledger-service, notification-service, postgres, redis, frontend).

Official checkpoint, all 3 passed:
```bash
kubectl get networkpolicy -n clearledger                                        # 7 policies
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/              # 200
kubectl get pods -n clearledger --field-selector=status.phase!=Running          # (empty — no crashed pods)
```

**Scenario 4, re-run correctly** (properly this time, after netpol was actually in place —
correcting the earlier accidental pre-netpol run):
```bash
LEDGER_POD=$(kubectl get pods -n clearledger -l app=ledger-service --no-headers \
  | awk '$2=="2/2" && $3=="Running" {print $1; exit}')
kubectl exec -n clearledger "$LEDGER_POD" -c ledger-service -- python3 -c "
import urllib.request
try:
    urllib.request.urlopen('http://notification-service/', timeout=5)
    print('UNEXPECTED: connection succeeded')
except Exception as e:
    print('BLOCKED (expected):', e)
"
# → BLOCKED (expected): <urlopen error timed out>
```
A genuine timeout (not a 404) proves the network policy is actually blocking the connection at
the network layer — `ledger-service` has no legitimate path to `notification-service` and now
genuinely cannot reach it.

## §6.6 — Final health check

```
make check-6
✓ Passed: 14
All checks passed. Ready for the next stage.
```
0 failures.

## What I can now claim (per the book)

> Deployed Falco for runtime threat detection with custom rules, and can trigger and read an
> alert for a shell-in-container or sensitive-file read the way an on-call engineer would.

Concretely demonstrated: watched a genuine eBPF-level detection fire for a real shell spawn
inside a real running pod, read the alert the way an on-call engineer would (priority → rule →
command → pod), and proved network segmentation actually blocks unauthorized traffic with a
real timeout, not a guess. Also fixed a real, predicted infrastructure gap (`helm` needing the
same wrapper-script treatment as `kubectl`/`argocd`) that will help every later Helm-based stage.

## Full command reference — every terminal command run today, in order

```bash
# Readiness
make check-5

# helm wrapper fix (blocking issue found and resolved before §6.1 could proceed)
bash stages/stage-6-runtime-security/scripts/install-falco.sh    # FAILED: line 12: helm: command not found
which helm                                    # empty — not a real PATH entry
helm version                                  # works interactively (via alias)
echo $PATH
ls /snap/bin/helm 2>&1                        # not there either
type helm                                     # helm is aliased to 'microk8s helm3'
cat > ~/.local/bin/helm << 'EOF'
#!/usr/bin/env bash
exec microk8s helm3 "$@"
EOF
chmod +x ~/.local/bin/helm
which helm                                    # now a real file
helm version                                  # still correct

# §6.1
bash stages/stage-6-runtime-security/scripts/install-falco.sh
kubectl get pods -n falco
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=200 | grep 'rules.d/clearledger_rules'

# §6.2
make demo-6
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=500 | grep 'Shell Spawned'

# §6.4 — note: Scenario 4 was also (accidentally) run once here, BEFORE netpol existed,
# while book prose was being pasted into the terminal — result was a false-positive-looking
# "BLOCKED (expected): HTTP Error 404: Not Found" (a 404 actually means the connection
# succeeded, just hit a missing route — not a real block). Not meaningful; redone correctly below.
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policices.yaml   # typo, path not found
kubectl apply -f infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml
kubectl get networkpolicy -n clearledger
curl -s http://clearledger.local/auth/health | jq .
curl -s http://clearledger.local/notifications/health | jq .
kubectl get networkpolicy -n clearledger
curl -s -o /dev/null -w "%{http_code}\n" http://clearledger.local/
kubectl get pods -n clearledger --field-selector=status.phase!=Running
LEDGER_POD=$(kubectl get pods -n clearledger -l app=ledger-service --no-headers \
  | awk '$2=="2/2" && $3=="Running" {print $1; exit}')
kubectl exec -n clearledger "$LEDGER_POD" -c ledger-service -- python3 -c "
import urllib.request
try:
    urllib.request.urlopen('http://notification-service/', timeout=5)
    print('UNEXPECTED: connection succeeded')
except Exception as e:
    print('BLOCKED (expected):', e)
"

# §6.6
make check-6

# Snapshot (known Multipass-only limitation, confirmed not a real problem)
make snapshot STAGE=6
make snapshots
```
