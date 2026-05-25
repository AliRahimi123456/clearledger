# Troubleshooting Reference

Common problems encountered during the lab, with exact diagnostic commands and fixes.

---

## Cluster / VM Issues

### VM not starting

```bash
multipass list
# Check the state column — should show "Running"

multipass start clearledger

# If that fails, delete and recreate:
multipass delete clearledger
multipass purge
./scripts/setup-cluster.sh
```

### kubectl cannot connect

```bash
# Re-export the kubeconfig
multipass exec clearledger -- microk8s config > ~/.kube/clearledger-config
export KUBECONFIG=~/.kube/clearledger-config

kubectl get nodes
# Should show: clearledger   Ready
```

---

## Pod Issues

### Pod stuck in Pending

```bash
kubectl describe pod POD_NAME -n clearledger
# Look for: "Insufficient memory" or "Insufficient cpu"
# Fix: reduce resource requests in the deployment

# Look for: "0/1 nodes are available"
kubectl get nodes
kubectl describe node clearledger
# Check conditions at the bottom — is memory pressure indicated?
```

### Pod stuck in CrashLoopBackOff

```bash
kubectl logs POD_NAME -n clearledger
kubectl logs POD_NAME -n clearledger --previous

# Common causes:
# - Database not ready yet (wait for postgres readiness probe)
# - Wrong DATABASE_URL (check secret values)
# - Vault not configured yet (check vault-agent-init logs)
kubectl logs POD_NAME -n clearledger -c vault-agent-init
```

### readOnlyRootFilesystem causing failures

```bash
# If the app writes temp files, add an emptyDir volume:
# In deployment.yaml, add to volumes:
volumes:
  - name: tmp
    emptyDir: {}
# And to the container's volumeMounts:
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

### Image pull failures from Docker Hub

```bash
# Confirm the Deployment references Docker Hub images
kubectl get deployment auth-service -n clearledger \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

# Verify the image tag exists in Docker Hub (web UI)
#   hub.docker.com → repositories → clearledger-auth-service → tags

# If you're hitting Docker Hub rate limits, try again later or authenticate pulls.
```

---

## Kyverno Issues

### Kyverno blocking a deployment you expect to pass

```bash
# See the exact policy that blocked it
kubectl get events -n clearledger --sort-by='.lastTimestamp' | tail -20

# Check which policies are active and in what mode
kubectl get clusterpolicy

# Temporarily switch a policy to Audit to diagnose:
kubectl patch clusterpolicy disallow-root-containers \
  --type merge \
  -p '{"spec":{"validationFailureAction":"Audit"}}'
# Remember to switch back to Enforce after diagnosing
```

### PolicyReport showing violations

```bash
kubectl get policyreport -n clearledger
kubectl describe policyreport -n clearledger

# Each violation shows: resource, policy, rule, message
# Fix the resource or create a PolicyException if the exemption is legitimate
```

---

## Vault Issues

### Vault agent not injecting secrets

```bash
# Check init container logs (runs at pod startup before the main container)
kubectl logs POD_NAME -n clearledger -c vault-agent-init

# Common errors:
# "permission denied" → service account not bound to a Vault role
# "connection refused" → Vault is not running or not reachable

# Verify the Vault role is configured correctly
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/auth-service

# Verify the service account exists (created with infra/manifests/rbac/rbac.yaml)
kubectl get serviceaccount auth-service -n clearledger
```

### Vault pod not starting

```bash
kubectl logs vault-0 -n vault
kubectl describe pod vault-0 -n vault

# In dev mode, Vault should start immediately
# If sealed, unseal manually:
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-0 -- vault operator unseal
```

### Secrets not appearing in /vault/secrets

```bash
# Verify Vault has the secret at the expected path
kubectl exec -n vault vault-0 -- vault login root-dev-token
kubectl exec -n vault vault-0 -- vault kv get clearledger/auth-service

# Verify the annotation path matches the actual Vault path
# deployment.yaml annotation:
#   vault.hashicorp.com/agent-inject-secret-database_url: "clearledger/data/auth-service"
# This must match the kv-v2 path format: clearledger/data/<path>
```

---

## AWS / EKS (Stage 8)

<a id="irsa-not-working-runbook"></a>

### IRSA not working — pod using node role instead of service role

Symptom: `aws sts get-caller-identity` (from `kubectl run ... --image=amazon/aws-cli`
with your workload ServiceAccount) shows the **EC2 instance profile** ARN for the
node, not `assumed-role/<your-irsa-role>/...`.

**1. Verify the ServiceAccount has the correct IRSA annotation**

```bash
kubectl get sa auth-service -n clearledger -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
```

**Expected:** non-empty ARN matching `terraform output -raw auth_service_irsa_role_arn`.

**If empty:** apply `stages/stage-8-aws-migration/manifests/clearledger-serviceaccounts.yaml`
after substituting ARNs (see file header). If you use GitOps, commit the resolved YAML.

**2. Verify the IAM role trust policy lists the correct OIDC provider ARN**

```bash
aws iam get-role --role-name clearledger-auth-service \
  --query 'Role.AssumeRolePolicyDocument' --output json | jq .
```

**Expected:** `Principal.Federated` equals `arn:aws:iam::<account-id>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<cluster-oidc-id>`.

**If wrong:** re-run `terraform apply` for `stages/stage-8-aws-migration/terraform` — the
provider is created with the EKS cluster.

**3. Verify `StringEquals` on `:sub` matches the exact namespace + ServiceAccount**

In the same trust JSON, find `oidc.eks...:sub` → must be exactly:

`system:serviceaccount:clearledger:auth-service`

**If it says `ledger-service` or another namespace:** Terraform `iam.tf` trust
`values` do not match this SA — fix the role or the Kubernetes SA name.

**4. Confirm the OIDC provider exists in IAM**

```bash
aws iam list-open-id-connect-providers --output text
```

**Expected:** an ARN containing your EKS cluster OIDC issuer ID.

**If missing:** EKS control plane was not wired for IRSA — `terraform apply` must
complete successfully (see `aws_iam_openid_connect_provider.eks` in Terraform).

**5. Confirm the Pod uses the annotated ServiceAccount (not `default`)**

```bash
kubectl get pod -n clearledger -l app=auth-service \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.serviceAccountName}{"\n"}{end}'
```

**Expected:** second column is `auth-service`.

**If `default`:** patch the Deployment `serviceAccountName` and restart.

---

## ArgoCD Issues

### Application stuck in OutOfSync

```bash
argocd app sync clearledger --force
argocd app get clearledger

# Check for resource conflicts
kubectl get events -n clearledger --sort-by='.lastTimestamp'

# Check if the infra repo is reachable
argocd repo list
```

### selfHeal reverting your manual changes

This is working as designed. To make a legitimate change:
1. Edit the manifest in the infra Git repo
2. Commit and push
3. ArgoCD syncs automatically

To temporarily pause selfHeal for incident response:
```bash
argocd app set clearledger --self-heal=false
# Make your emergency changes
# Then re-enable:
argocd app set clearledger --self-heal=true
```

---

## Falco Issues

### Falco not detecting events

```bash
kubectl logs -n falco daemonset/falco | grep -i error

# Check if the eBPF driver is loaded
kubectl exec -n falco \
  $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- falco --version

# Verify custom rules are loaded
kubectl exec -n falco \
  $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- cat /etc/falco/clearledger_rules.yaml
```

### Falco UI showing no alerts

```bash
# Verify Falcosidekick is running
kubectl get pods -n falco | grep sidekick

# Check Falcosidekick logs
kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick

# Manually trigger a test alert
kubectl exec -n clearledger \
  $(kubectl get pod -n clearledger -l app=auth-service -o name | head -1) \
  -- /bin/sh
# This should appear in the Falco UI within seconds
```

---

## Networking Issues

### Services not reachable via domain name

```bash
# Verify /etc/hosts entries exist
cat /etc/hosts | grep clearledger

# Verify the VM IP hasn't changed (it can change after restart)
VMIP=$(multipass info clearledger | grep IPv4 | awk '{print $2}')
echo "Current VM IP: $VMIP"

# If the IP changed, re-run setup-hosts.sh after removing old entries
sudo sed -i '' '/clearledger.local/d' /etc/hosts
./scripts/setup-hosts.sh
```

### Network policies blocking legitimate traffic

```bash
# Temporarily remove the default-deny policy to test
kubectl delete networkpolicy default-deny-all -n clearledger

# Test connectivity
curl -s http://clearledger.local/auth/health

# Re-apply when done testing
kubectl apply -f infra/manifests/netpol/network-policies.yaml
```

---

## General Debugging Workflow

When something is broken:

1. **Check pod status:** `kubectl get pods -n clearledger`
2. **Check events:** `kubectl get events -n clearledger --sort-by='.lastTimestamp'`
3. **Check logs:** `kubectl logs POD_NAME -n clearledger`
4. **Check description:** `kubectl describe pod POD_NAME -n clearledger`
5. **Check the stage README** — the current stage's README describes exactly what should be running
