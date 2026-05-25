# Kubernetes API audit logs (ClearLedger)

Falco observes **syscalls inside pods**. The API server audit log records **who did what to cluster resources** (`kubectl exec`, `Secret` reads, `delete` calls). For SOC2 / PCI evidence you usually need both.

## What to configure

1. **Audit policy** — `Policy` object listing which resources and verbs are logged and at which level (`Metadata`, `Request`, `RequestResponse`).
2. **Audit backend** — typically a log file on the control plane or a webhook shipping to your log stack.

Example policy fragment (tighten for production; widen carefully because `RequestResponse` logs request bodies):

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets", "serviceaccounts"]
  - level: Metadata
    resources:
      - group: ""
        resources: ["pods", "pods/exec"]
    verbs: ["create", "delete", "patch"]
  - level: Metadata
    omitStages: ["RequestReceived"]
```

## Lab environments

| Environment | Notes |
|-------------|--------|
| **MicroK8s** | Enable/configure API server audit via MicroK8s addon / `args` on the `kube-apiserver` static pod. See [MicroK8s documentation](https://microk8s.io/docs) for the version you run. |
| **EKS** | Use **control plane logging** to CloudWatch for `audit`, `api`, `authenticator`. This is the supported way to get API audit evidence on a managed plane. |
| **Self‑hosted / kubeadm** | Mount `--audit-policy-file` and `--audit-log-path` (or webhook) on `kube-apiserver`. |

## Ship to Loki (Stage 7)

Once audit logs land on a node path or CloudWatch:

- **File on node:** run Promtail / Grafana Agent with a `static_configs` job reading the audit log path (often requires a DaemonSet with hostPath mounts and coordination with how apiserver writes logs).
- **CloudWatch:** export to S3 or subscribe a Lambda / Firehose to push JSON into Loki, or query CloudWatch Logs Insights directly.

Suggested LogQL-style questions (labels depend on your scrape pipeline):

- Count `pods/exec` creates in the last hour.
- List `delete` on `namespaces` or high‑risk cluster-scoped resources.
- Flag `SubjectAccessReview` denials (often noisy — tune alerts).

This lab keeps a **policy sample** here for learning; wiring it to your exact control plane is cluster‑specific by design.
