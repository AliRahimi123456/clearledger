# Screenshot Guide

Take these screenshots after completing each stage.
Replace the placeholders in screenshots/ with your actual captures.
Then push to GitHub — the README embeds them automatically.

---

## Screenshot 1 — Web UI Dashboard (after Stage 0)

Setup:

```bash
# Register and create some transactions first
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@clearledger.io","password":"Demo1234"}' \
  | jq -r .access_token)

# Create a mix of transactions
curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":5000,"direction":"credit","description":"Salary"}' > /dev/null

curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":12000,"direction":"debit","description":"Equipment purchase"}' > /dev/null
```

Then open: http://clearledger.local

What to capture: The full dashboard with:

- A non-zero balance (ideally negative — looks more dramatic)
- At least 2 transactions in the history list
- 1 alert visible in the alerts panel (the $12,000 debit)

Why this screenshot matters: It proves you built a real application,
not just YAML files. A working UI with financial data is immediately
understandable to any interviewer or hiring manager.

Save as: screenshots/01-ui-dashboard.png

---

## Screenshot 2 — ArgoCD Synced and Healthy (after Stage 2)

Setup:

```bash
# Ensure ArgoCD is synced
argocd app sync clearledger
```

Open: https://argocd.local

What to capture: The ArgoCD application detail page showing:

- App name: clearledger
- Sync Status: Synced (green checkmark)
- Health Status: Healthy (green heart)
- The resource tree showing pods, services, deployments

Why this screenshot matters: ArgoCD is one of the most recognized
DevOps tools on the market. Showing it working with your app
communicates GitOps competency instantly.

Save as: screenshots/02-argocd-synced.png

---

## Screenshot 3 — Kyverno Blocking a Root Container (after Stage 4)

Setup:

```bash
# Run this command and capture the terminal output
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: root-test
  namespace: clearledger
spec:
  containers:
    - name: test
      image: nginx:alpine
EOF
```

What to capture: The terminal showing the red error output:

```
Error from server: admission webhook "validate.kyverno.svc" denied the request:
Root containers are blocked in clearledger namespace.
Set securityContext.runAsNonRoot: true
```

Make the terminal window large enough to read clearly.
Use a dark terminal theme if possible.

Why this screenshot matters: This is the difference between saying
"I know about policy as code" and proving it. The error message is
concrete evidence. Most engineers cannot produce this screenshot.

Save as: screenshots/03-kyverno-block.png

---

## Screenshot 4 — Falco CRITICAL Alert (after Stage 6)

Setup:

```bash
# Trigger the alert first
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- /bin/sh -c "id && exit" 2>/dev/null || true
```

Then open: http://falco.local

What to capture: The Falco Sidekick UI showing:

- A CRITICAL severity event
- Rule name: "Shell Spawned in ClearLedger Container"
- The pod name and timestamp

Why this screenshot matters: Runtime security is the most impressive
layer of the stack because it requires the most operational depth.
A screenshot proving Falco caught you exec'ing into your own pod
demonstrates you understand the attack surface, not just the tooling.

Save as: screenshots/04-falco-alert.png

---

## Screenshot 5 — Grafana Security Dashboard (after Stage 7)

Open: http://grafana.local
Navigate to: Dashboards → ClearLedger — Security Event Timeline

What to capture: The full dashboard showing at least one panel with data.
Ideally the timeline shows the Falco alert from Screenshot 4.

Why this screenshot matters: Security observability is the layer most
homelab projects skip. A Grafana dashboard with real security data
is the visual proof that you go beyond CI/CD into operational security.

Save as: screenshots/05-grafana-security.png

---

## Screenshot 6 — Pipeline All Green (after Stage 3)

Open: github.com/YOUR_USERNAME/clearledger/actions

What to capture: A completed pipeline run showing all jobs green:

- ✓ Secrets Scan (Gitleaks)
- ✓ SAST (Semgrep)
- ✓ IaC Scan (Checkov)
- ✓ Build + Scan auth-service (Trivy)
- ✓ Build + Scan ledger-service (Trivy)
- ✓ Build + Scan notification-service (Trivy)
- ✓ Build + Scan frontend (Trivy)
- ✓ Update Manifests → ArgoCD Syncs

Why this screenshot matters: Most engineers can write a pipeline.
Six security gates all passing on real application code is different.
This is the screenshot that says "I understand what a DevSecOps
pipeline actually looks like."

Save as: screenshots/06-pipeline-green.png

---

## Screenshot 7 — ClearLedger on AWS (Stage 8 only, optional)

After running: bash stages/stage-8-aws-migration/scripts/aws-spinup.sh

Open the ALB URL printed at the end of the script.

What to capture: The ClearLedger UI running at an AWS ALB URL
(something like http://clearledger-alb-xxx.eu-west-1.elb.amazonaws.com)
with the URL bar visible in the browser.

Why this screenshot matters: Cloud migration is a checkbox in most
DevOps job descriptions. A working URL proves yours is real.

Remember to destroy after: bash stages/stage-8-aws-migration/scripts/aws-destroy.sh

Save as: screenshots/07-aws-browser.png
