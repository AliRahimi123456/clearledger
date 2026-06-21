# Stage 8 — Three ways to get secrets into pods

ClearLedger uses **different secret delivery patterns** in homelab vs AWS.

## At a glance

| Pattern | Where | How the pod gets secrets |
|---|---|---|
| **1. Vault agent** | Homelab Stages 5–7 | Sidecar → files `/vault/secrets/*` |
| **2. ESO** | AWS default deploy | SM → K8s Secret → `secretKeyRef` / env |
| **3. CSI Driver** | AWS §8.5 exercise | SM → CSI volume → files `/mnt/secrets/*` |

All AWS paths use **IRSA** — no static AWS keys in the cluster.

---

## 1. Vault (homelab)

Manifests: `infra/manifests/*/deployment.yaml` with `vault.hashicorp.com/agent-inject` annotations.

---

## 2. ESO (default on AWS)

- Operator: `helm install external-secrets` (IRSA on ESO ServiceAccount)
- CRs: `manifests/external-secrets.yaml`
- Deployments: `manifests/deployments/auth-service.yaml` (env from K8s Secret)

Verify: `kubectl get externalsecret -n clearledger` → `SecretSynced=True`

---

## 3. CSI Driver (installed by `make aws-up`; exercise in LAB-GUIDE §8.5)

- Install: `scripts/install-csi-secrets.sh` (also step 11 of `aws-spinup.sh`)
- CRs: `manifests/csi/*-spc.yaml` (SecretProviderClass)
- Deployment swap: `deployments/auth-service-csi.yaml` (file mounts via IRSA on **app** SA)

Verify:

```bash
kubectl get secretproviderclass -n clearledger
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
# After §8.5 deploy swap:
kubectl exec -n clearledger deploy/auth-service -c auth-service -- ls /mnt/secrets
```

Why both ESO and CSI in one lab:
- **ESO** — default GitOps path, secrets visible as K8s objects (easy debug)
- **CSI** — production file-mount path, secrets not stored in etcd

See [LAB-GUIDE.md §8.5](../../../docs/LAB-GUIDE.md#85--hands-on-csi-driver-file-mounts).
