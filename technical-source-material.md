# Technical Source Material

Extracted from ClearLedger repository artifacts, `docs/troubleshooting.md`, stage code, CI workflows, policies, Terraform, app secret-loading code, and prior lab-building chat transcripts (encoded failures: runner labels, IPv6 Hub, Kyverno Bitnami/probes, Vault sleep wipe, disk pressure, ArgoCRD annotation, netpol/DNS). Terminals at extract time had no active failure logs.

This file is extraction only: named configs, failure modes, enforcement decisions, and verification steps. Not a content plan.

---

## Highest-Specificity Findings

Ranked specificity 9–10.

---

### FINDING — Repo variable flips which CI pipeline is eligible

#### Source

`.github/workflows/ci.yaml`, `.github/workflows/ci-aws.yaml`

#### Exact artifact

GitHub Actions repository variable `vars.CLEARLEDGER_CI_TARGET`

#### What is configured

Homelab jobs: `if: … && vars.CLEARLEDGER_CI_TARGET != 'aws'` (and schedule exclusion on some jobs). Homelab `paths-ignore` includes `stages/stage-8-aws-migration/**`. AWS workflow jobs gate on `vars.CLEARLEDGER_CI_TARGET == 'aws'` and/or `workflow_dispatch`. Homelab uses `runs-on: [self-hosted, clearledger]` + Docker Hub; AWS uses GitHub-hosted + ECR + `environment: production`.

#### Observable behaviour

With `CLEARLEDGER_CI_TARGET=aws`, self-hosted Docker Hub jobs are skipped; AWS/ECR jobs run. Variable unset → opposite. Setting `aws` before Stage 8 OIDC/ECR exists leaves Stage 1–7 CI idle while AWS assume-role fails.

#### Technical reason

Mutual exclusion via one shared repo variable across two workflows with different runners and registries.

#### Verification

`gh variable list --repo OWNER/clearledger`; push to `main` and inspect which workflow jobs are skipped vs executed.

#### Closely confused with

Presence of both YAML files meaning both pipelines always run end-to-end.

#### Engineering question

If `CLEARLEDGER_CI_TARGET=aws` is set before EKS/OIDC trust exists, which failure appears first: skipped `ci.yaml` jobs, or `sts:AssumeRoleWithWebIdentity` denial in `ci-aws.yaml`?

#### Beginner relevance

One variable changes runner class, registry, and secrets model. Wrong timing stops green Stage 1–7 pipelines.

#### Specificity score

10

---

### FINDING — Scheduled “kube-bench” trigger has no kube-bench job

#### Source

`.github/workflows/ci.yaml`

#### Exact artifact

`on.schedule` cron `"0 6 * * 1"` with comment “Compliance scans (kube-bench)”; gate `if: github.event_name != 'schedule'` on early jobs including `secrets-scan` / `prepare-scanners`

#### What is configured

Weekly schedule starts the workflow. Jobs that seed the graph skip on `schedule`. No job named `kube-bench` (or equivalent) exists in this workflow. Local CIS is `stages/stage-4-admission-control/scripts/run-kube-bench.sh` / `make check-4`, not CI.

#### Observable behaviour

Monday 06:00 UTC run starts; gated jobs skip; run is effectively empty.

#### Technical reason

Reserved schedule + comment without an implementing job; `needs` cascade never reaches a compliance step.

#### Verification

Actions → filter scheduled runs; confirm skipped jobs and absence of kube-bench steps. `rg kube-bench .github/workflows/ci.yaml` finds only comments/`if` text.

#### Closely confused with

Weekly cron actually enforcing CIS via Actions.

#### Engineering question

Was kube-bench intended as a scheduled job here, or is the `schedule` trigger dead until a job is added?

#### Beginner relevance

A cron description in YAML is not evidence a control ran; look for a job name and steps.

#### Specificity score

10

---

### FINDING — Self-hosted runner must carry label `clearledger`, not only be Online

#### Source

`.github/workflows/ci.yaml`, `docs/troubleshooting.md` (“Job stays queued waiting for a runner”)

#### Exact artifact

`runs-on: [self-hosted, clearledger]`

#### What is configured

Every homelab gate job requires both labels. Matching is by label set, not by runner display name.

#### Observable behaviour

Job stays “Waiting for a runner…” while a runner is Online without custom label `clearledger`.

#### Technical reason

GitHub Actions schedules on required labels intersection.

#### Verification

Repo → Settings → Actions → Runners → Labels includes `clearledger`; re-run queued job.

#### Closely confused with

Online runner status implying eligibility; confusing runner name with label.

#### Engineering question

After registration, which exact labels does GitHub show versus what `runs-on` requires?

#### Beginner relevance

Online ≠ eligible. Missing one custom label queues forever.

#### Specificity score

10

---

### FINDING — Checkov soft-fail on Kubernetes, hard-fail on Dockerfiles

#### Source

`.github/workflows/ci.yaml` job `iac-scan`

#### Exact artifact

`checkov --directory infra/manifests --framework kubernetes --soft-fail`; Dockerfile scan `--skip-path app/frontend/Dockerfile.dev --soft-fail-on MEDIUM --hard-fail-on HIGH,CRITICAL`

#### What is configured

K8s Finding artifacts may be numerous while the job exits green. Dockerfile HIGH/CRITICAL fail the gate. `Dockerfile.dev` is never scanned.

#### Technical reason

Stage 1 treats cluster hardening as later Kyverno work; image build config is gated now.

#### Verification

Inspect Checkov artifacts; intentionally introduce MEDIUM vs HIGH in a Dockerfile and observe exit codes.

#### Closely confused with

“IaC scan passed” meaning Deployments meet CIS/securityContexts.

#### Engineering question

Which Checkov framework is merge-blocking when K8s is soft-fail and Dockerfile is hard-fail?

#### Beginner relevance

Green Checkov can mean only that Dockerfiles did not trip HIGH/CRITICAL.

#### Specificity score

10

---

### FINDING — Trivy gates all four images; Grype only gates auth with `--only-fixed`

#### Source

`.github/workflows/ci.yaml` jobs `build-images` / `scan-images`; `.grype.yaml`; `.trivyignore`

#### Exact artifact

`TRIVY_VERSION: "0.70.0"`; Trivy `--skip-db-update --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed` on all four tags; Grype only on Syft SBOM of auth: `grype … --fail-on high --only-fixed`; ignore `CVE-2026-7210` (reason in `.grype.yaml`: fix-requires-prerelease)

#### What is configured

Unfixed CVEs do not fail Trivy. Fixed HIGH+ on auth can fail Grype. Frontend always `docker build --no-cache`.

#### Observable behaviour

Ledger/notification can pass without a Grype step; auth fails Grype while others are green; Trivy “Version X available” notice can appear under exit 1 without causing it.

#### Technical reason

Build→scan split; ignore-unfixed / only-fixed shrink flaky OS/runtime noise; dual-scanner exemplar limited to auth; dual ignore files for one accepted CVE.

#### Verification

Artifact `image-scan-results`; force fixed HIGH on auth vs unfixed-only elsewhere; confirm notice is informational per troubleshooting.

#### Closely confused with

All four services being Grype-gated equally; Trivy version notice causing exit 1.

#### Engineering question

When CPython 3.15 GA ships, which two ignore files must change together to re-enable the gate for `CVE-2026-7210`?

#### Beginner relevance

Read which scanner step failed; absence of Grype on ledger is intentional in this workflow.

#### Specificity score

10

---

### FINDING — Publish can succeed without Cosign; Stage 4 Enforce is the hard stop

#### Source

`.github/workflows/ci.yaml` `publish-images`; `scripts/ci-publish-image.sh`; `infra/policies/require-signed-images.yaml`

#### Exact artifact

`cosign sign/attest … --tlog-upload=false`; missing `COSIGN_KEY` → skip sign/attest with exit 0; sign failures degraded with `|| echo "⚠ … skipped"`; frontend publish third arg provenance name `""`; ClusterPolicy `require-signed-images` `validationFailureAction: Enforce`, `failurePolicy: Fail`, `webhookTimeoutSeconds: 30`, placeholder `PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE`

#### What is configured

Lab Cosign is offline (no Rekor). CI signing is best-effort. Homelab Kyverno requires Cosign verify on `index.docker.io/*/clearledger-*` once a real pubkey is pasted.

#### Observable behaviour

Green publish without signatures; unsigned admit until Stage 4 policy configured; later admission denial naming `require-signed-images` / `verify-cosign-signature`.

#### Technical reason

Stage 1 prioritizes build-scan-push-Git handoff; admission Fail-closed is Stage 4.

#### Verification

`cosign verify --key infra/cosign.pub index.docker.io/$USER/clearledger-auth-service:$SHA` after green CI; `grep PASTE_YOUR infra/policies/require-signed-images.yaml`.

#### Closely confused with

Green Publish guaranteeing Stage 4 will admit all images.

#### Engineering question

If the Cosign secret is missing, is Stage 4 Fail-closed verify the first hard stop on unsigned images?

#### Beginner relevance

CI green and “signed” are not the same as admission enforcement.

#### Specificity score

10

---

### FINDING — `ENABLE_ARGOCD_SYNC` refresh is best-effort; CI updates Git, not necessarily the cluster

#### Source

`.github/workflows/ci.yaml` job `update-manifests`

#### Exact artifact

`vars.ENABLE_ARGOCD_SYNC == 'true'` step with `continue-on-error: true` and terminal `exit 0`; main-only manifest rsync + `kustomize edit set image` into `clearledger-infra` with `[skip ci]`

#### What is configured

Default Stage 1 path updates infra Git tags only. Optional Argo nudge never fails the job.

#### Observable behaviour

Infra repo tag changes; running Deployment image may stay old. Enabling sync without `argocd` namespace still yields job success with a warning.

#### Technical reason

Intentional deployment gap between Stage 1 and Stage 2 GitOps; CI must not fail on missing ArgoCD.

#### Verification

Leave variable unset; push; confirm cluster image JSONPath unchanged. Set variable without Argo → step warning, job success.

#### Closely confused with

Manifest update deploying the app.

#### Engineering question

After `ENABLE_ARGOCD_SYNC=true`, does a green `update-manifests` prove sync, or only a non-failing nudge?

#### Beginner relevance

Git image digests ≠ live pods until ArgoCD (or manual apply) reconciles.

#### Specificity score

10

---

### FINDING — Signature demo: `docker.io/` admit vs `index.docker.io/` deny; ImagePullBackOff ≠ policy

#### Source

`infra/policies/require-signed-images.yaml`; `docs/troubleshooting.md` (“Signature policy does not block unsigned images”)

#### Exact artifact

`imageReferences: index.docker.io/*/clearledger-*`; Kyverno 1.12 `verifyImages` matching behaviour documented in troubleshooting

#### What is configured

Canonical registry form is what the policy matches reliably. Missing/unsigned pushed tag used with bare `docker.io/...` can admit then fail at pull.

#### Observable behaviour

Pod created → maybe `ImagePullBackOff` (false negative for signature demo). Canonical unsigned ref → webhook denial text naming `require-signed-images`.

#### Technical reason

`verifyImages` match string + fail-closed webhook vs runtime pull failure (different planes).

#### Verification

Push `…:unsigned-test`; apply Pod with `index.docker.io/…`; expect deny. `cosign verify` expecting “no signatures found”.

#### Closely confused with

`ImagePullBackOff` meaning Cosign policy worked; admission deny vs pull fail.

#### Engineering question

After pasting `cosign.pub`, does denial still fail when the image string is `docker.io/` not `index.docker.io/`?

#### Beginner relevance

Wrong registry string makes verification appear broken when the rule never matched.

#### Specificity score

10

---

### FINDING — Homelab Cosign Enforce/Fail vs ECR Audit/Ignore

#### Source

`infra/policies/require-signed-images.yaml`; `infra/policies/require-signed-images-ecr.yaml`

#### Exact artifact

Homelab: `validationFailureAction: Enforce`, `failurePolicy: Fail`. ECR: `validationFailureAction: Audit`, `failurePolicy: Ignore`, refs `*.dkr.ecr.*.amazonaws.com/clearledger/{auth,ledger,notification}-service*` (`mutateDigest: false`; frontend omitted from refs in policy text)

#### What is configured

Stage 8 interim fail-open for ECR signing until enforce flip; Docker Hub policy remains Fail closed separately.

#### Observable behaviour

Unsigned ECR pods still admitted; webhook processing errors do not block ECR path.

#### Technical reason

Different ClusterPolicies for different registries and maturity of signing in that environment.

#### Verification

`kubectl get clusterpolicy require-signed-images require-signed-images-ecr -o yaml | grep -E 'validationFailureAction|failurePolicy'`

#### Closely confused with

Homelab Enforce applying to ECR digests.

#### Engineering question

When flipping ECR to Enforce/Fail, must `clearledger/frontend` be added to `imageReferences` because CI publishes it?

#### Beginner relevance

Audit≠Enforce; Ignore≠Fail. ECR does not inherit Docker Hub fail-closed settings from this repo.

#### Specificity score

10

---

### FINDING — PolicyException ruleNames must match live policy rules; stage-4 copy diverged

#### Source

`infra/policies/disallow-root.yaml`; `infra/policies/exceptions/postgres-root-exception.yaml`; `stages/stage-4-admission-control/infra/policies/disallow-root.yaml`

#### Exact artifact

ClusterPolicy `disallow-root-containers` rules `check-runAsNonRoot-containers` / `check-runAsNonRoot-initcontainers` (Vault agent name skip); PolicyException `postgres-root-exception` `ruleNames` listing those two; Stage-4 copy uses older single-rule shape without Vault skip

#### What is configured

Exception only skips infra rule names for `postgres-*` in `clearledger`. Applying stage-4 YAML after Vault can deny injectors; exception then targets wrong rule names.

#### Observable behaviour

Postgres roots allowed under infra policy + exception; Vault agent denied if old stage-4 policy applied.

#### Technical reason

PolicyException binds exact `policyName` + `ruleNames`; copies diverged after Stage 5 Vault update.

#### Verification

`kubectl get clusterpolicy disallow-root-containers -o yaml | grep -E 'name: check-'`; `kubectl get policyexception -n clearledger -o yaml`

#### Closely confused with

Stage folder policies being identical to `infra/policies/`.

#### Engineering question

Which path does the lab apply in §4.3—stage-4 copy or `infra/policies/`?

#### Beginner relevance

Exception YAML that “looks related” is a no-op if `ruleNames` do not match.

#### Specificity score

10

---

### FINDING — Kyverno chart pin + Bitnami image removal + loosened probes

#### Source

`stages/stage-4-admission-control/infra/kyverno/values.yaml`; `docs/troubleshooting.md`

#### Exact artifact

Helm chart **3.2.8** / Kyverno 1.12.x; `cleanupJobs.*.enabled: false`; hooks/`policyReportsCleanup` image `bitnamilegacy/kubectl:1.28.5`; `admissionController.livenessProbe.timeoutSeconds: 30`, `failureThreshold: 5` (~150s grace). Chart 3.6.4 on K8s 1.29 → CRD `selectableFields` error documented.

#### What is configured

Lab install is pinned and patched for MicroK8s single-node load and Bitnami public image removal.

#### Observable behaviour

Without values: `ImagePullBackOff` on `bitnami/kubectl:1.28.5`; tight default probes → Kyverno restart storm / TLS timeouts / sluggish API. Upgrade to 3.6.4 fails CRD patch.

#### Technical reason

Upstream chart image + probe defaults vs MicroK8s dqlite under probe churn; K8s API version gate for newer Kyverno CRDs.

#### Verification

Install with `-f …/kyverno/values.yaml --version 3.2.8`; `kubectl get pods -n kyverno` shows no cleanup ImagePullBackOff; RESTARTS stay low under load.

#### Closely confused with

“Helm upgrade to latest” being safe on MicroK8s 1.29; cleanup ImagePullBackOff meaning Kyverno cannot admit.

#### Engineering question

After a restart storm, is tearing down Litmus or reinstalling Kyverno with these values the smaller recovery?

#### Beginner relevance

Generic `helm install kyverno` fails in known ways on this lab’s pinned stack.

#### Specificity score

10

---

### FINDING — kube-bench regressions-only vs absolute FAIL counts

#### Source

`stages/stage-4-admission-control/scripts/run-kube-bench.sh`; `kube-bench-baseline.json`; `scripts/health-check.sh` / `make check-4`

#### Exact artifact

Job `kube-system/kube-bench` with MicroK8s args mount `/var/snap/microk8s/current/args`; baseline keys e.g. `"4.2.1": "FAIL"`; gate fails only when expected ≠ FAIL and current == FAIL

#### What is configured

Known MicroK8s CIS FAILs are allowed if baseline documents them. Absolute fail counts can be high while check PASSes.

#### Observable behaviour

`make check-4` fails only on new regressions; empty/broken baseline historically caused script/macOS pipefail failures (troubleshooting).

#### Technical reason

Unmanaged MicroK8s CIS noise filtered by regression comparison.

#### Verification

`bash stages/stage-4-admission-control/scripts/run-kube-bench.sh`; mutate a baseline PASS id to simulate regression.

#### Closely confused with

`make check-4` requiring zero kube-bench FAILs.

#### Engineering question

If control `4.2.6` flips PASS→FAIL, does check-4 fail even when other baseline FAILs remain?

#### Beginner relevance

Lab CIS FAIL is often expected; regression vs baseline is the automation gate.

#### Specificity score

10

---

### FINDING — ClusterRole `clearledger-deny-secrets` with `rules: []` does not deny Secret API

#### Source

`infra/manifests/rbac/rbac.yaml` (also stage-0 / stage-5 copies)

#### Exact artifact

ClusterRole `clearledger-deny-secrets` `rules: []`; RoleBinding `clearledger-default-deny-secrets` to SA `default` in `clearledger`

#### What is configured

Comments state Kubernetes RBAC is allow-only; empty role documents intent for default SA. Hard denial of Secret use needs admission (Kyverno). Workload Roles grant only `endpoints` get/list.

#### Observable behaviour

`kubectl auth can-i get secrets --as=system:serviceaccount:clearledger:default` remains “no” until another RoleBinding grants Secrets. Adding a secrets Role later succeeds despite “deny-secrets” naming.

#### Technical reason

RBAC additive allow; empty rules grant nothing but do not veto other bindings.

#### Verification

`kubectl auth can-i get secrets --as=system:serviceaccount:clearledger:default -n clearledger`; then bind a secrets Role and re-check.

#### Closely confused with

NetworkPolicy default-deny or Kyverno rule that rejects Secret API use.

#### Engineering question

What evidence does an auditor get from `rules: []` versus an admission policy that rejects Secret verb use?

#### Beginner relevance

A Role named “deny” can still leave Secrets reachable if anything else allows them.

#### Specificity score

10

---

### FINDING — Vault requires `automountServiceAccountToken: true`; bootstrap sets `false`

#### Source

`infra/manifests/auth-service/deployment.yaml`; `stages/stage-5-secrets-management/infra/manifests/auth-service/deployment.yaml`; CIS note in manifests/docs

#### Exact artifact

Bootstrap: `automountServiceAccountToken: false` + `secretKeyRef`. Stage 5: `automountServiceAccountToken: true` + Vault agent annotations (`agent-inject`, role `auth-service`, templates to `/vault/secrets/*`)

#### What is configured

Vault Kubernetes auth needs projected SA token. CIS 5.1.6 prefers disabling automount.

#### Observable behaviour

Vault annotations with automount false → agent login `permission denied`, secrets never appear, pod often `Init:0/1` / `1/2`. Leaving automount true without Vault expands token theft surface.

#### Technical reason

Feature dependency conflicts with hardening default.

#### Verification

Diff Stage 5 vs bootstrap Deployment; `kubectl logs … -c vault-agent-init`; `kubectl get pod -o yaml | grep automountServiceAccountToken`

#### Closely confused with

K8s RBAC Role granting Vault path access (Vault policy/role binding is separate).

#### Engineering question

Can projected SA token be scoped only to the vault-agent container instead of the whole pod?

#### Beginner relevance

CIS “disable token” and Vault injector both cite the same token path with opposite goals.

#### Specificity score

10

---

### FINDING — Falco outbound DNS allowlist ≠ NetworkPolicy egress allowlist

#### Source

`stages/stage-6-runtime-security/infra/falco/clearledger-rules.yaml`; `infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml`

#### Exact artifact

Falco rule `Unexpected Outbound Connection from ClearLedger`: allow `fd.sip.name in (postgres, redis, auth-service, ledger-service)` + `127.0.0.1`. Netpol auth egress: postgres `:5432`, vault NS `:8200`, monitoring `:4317`, DNS `:53`. Drivers: `modern_ebpf` via Helm values.

#### What is configured

Netpol can allow Vault/OTel while Falco still WARNs on those connections by name. Falco detects; NetworkPolicy blocks. Deferred netpol is not in initial ArgoCD tree.

#### Observable behaviour

After Stage 6.5/7.5, WARNING spam for vault/otel destinations; Scenario traffic blocked by netpol despite Falco “outbound” alerting on other paths.

#### Technical reason

Detection rule DNS name set incomplete vs CNI allowlist; different control planes (eBPF vs netpol).

#### Verification

`kubectl get networkpolicy -n clearledger`; Falco UI/logs for outbound WARNINGs; connect to vault `:8200` through allow and observe Falco still warn if name not in list.

#### Closely confused with

Falco WARNING meaning netpol blocked the packet; netpol presence because the YAML exists in the monorepo.

#### Engineering question

Should the Falco outbound rule include `vault`, `otel-collector`, and/or IP allowlists to match Stage 6–7.5 netpol?

#### Beginner relevance

False positives here are incomplete allowlist alignment, not a broken Falco install.

#### Specificity score

10

---

### FINDING — Three AWS secret delivery patterns; default remains ESO→etcd Secret

#### Source

`stages/stage-8-aws-migration/docs/secrets-patterns.md`; CSI SPC / `auth-service-csi.yaml`; ESO manifests; `install-csi-secrets.sh`

#### Exact artifact

Homelab Vault files `/vault/secrets/*`; AWS default ExternalSecret → K8s Secret → env (`refreshInterval: 1h`); CSI SPC `clearledger-auth-service-spc` → `/mnt/secrets` + `DATABASE_URL_FILE=/mnt/secrets/database_url`; CSI Helm `tokenRequests[0].audience=sts.amazonaws.com`; `enableSecretRotation=true`

#### What is configured

Same app `_read_secret` file-then-env. Kustomization may include ESO + SPC CRDs; CSI Deployment swap is manual. Warning: do not install CSI driver chart twice (AWS provider owns driver).

#### Observable behaviour

ESO: Secrets reappear in etcd. CSI: files only under `/mnt/secrets`. Missing `tokenRequests` → mount failure (“serviceAccount.tokens not provided”).

#### Technical reason

IRSA on app SA (CSI) vs IRSA on ESO operator SA; file vs env delivery.

#### Verification

`kubectl get externalsecret -n clearledger`; CSI `ls /mnt/secrets`; compare Deployment env vs file env vars.

#### Closely confused with

CSI automatically replacing ESO when Stage 8 is applied.

#### Engineering question

Why keep ESO as default when CSI avoids Secrets in etcd?

#### Beginner relevance

Migration is a delivery-path swap, not a rewrite of Python secret readers—if paths/`*_FILE` match.

#### Specificity score

10

---

### FINDING — IRSA `StringEquals` on `:sub` + Deny on peer Secrets Manager ARNs + permission boundary

#### Source

`stages/stage-8-aws-migration/terraform/iam.tf`; `manifests/clearledger-serviceaccounts.yaml`; `docs/troubleshooting.md` IRSA / OIDC runbooks

#### Exact artifact

Trust `StringEquals` `${oidc}:sub` = `system:serviceaccount:clearledger:auth-service` (etc.), audience `sts.amazonaws.com`; auth Allow GetSecret only auth ARN, Deny postgres+ledger ARNs; `permissions_boundary` denying `ec2:*`,`iam:*`,`s3:*`,`lambda:*`,`dynamodb:*`; GitHub Actions ECR role `sub` = `repo:${var.github_owner}/clearledger:environment:production`; SA annotation `eks.amazonaws.com/role-arn`

#### What is configured

Exact SA+namespace binding (comment: never `StringLike`). Wrong `github_owner` leaves placeholder trust subject.

#### Observable behaviour

Wrong annotation → node instance profile identity from `get-caller-identity`. Auth cannot read ledger SM secret. CI AssumeRoleWithWebIdentity denied if `:sub` is `YOUR_GITHUB_USERNAME`.

#### Technical reason

Pod identity via EKS OIDC; Deny + boundary shrink blast radius independently of Allow.

#### Verification

`aws sts get-caller-identity` from pod; `aws iam get-role` trust JSON; `terraform output` vs SA annotation.

#### Closely confused with

Node instance profile permissions equaling workload SM access.

#### Engineering question

Why is `StringEquals` required on `:sub` instead of `StringLike` for ServiceAccount binding?

#### Beginner relevance

IRSA misconfig shows up as “still using node role,” not as a Kubernetes RBAC error.

#### Specificity score

10

---

## Failure Modes

---

### FINDING — host_dns/container_dns bit pair distinguishes DNS vs Docker NAT failure

#### Source

`.github/workflows/ci.yaml` step `Network diagnostic (on build failure)`; `docs/troubleshooting.md`; `scripts/configure-vm-network.sh`

#### Exact artifact

`host_dns` / `container_dns` as `0|1` from `getent hosts registry-1.docker.io` on host vs `docker run alpine:3.20 getent`

#### What is configured

On build failure only: prints bit pair. Documented decode: `1 0` = Docker bridge/NAT broken; `0 0` = host resolver broken. Separate IPv6 path: AAAA `network is unreachable` despite working IPv4 (`gai.conf` precedence + `net.ipv6.conf.*.disable_ipv6=1`).

#### Observable behaviour

Failed build logs include the pair; IPv6 Hub failure is a different error string than `server misbehaving`.

#### Technical reason

Multipass DNS, Docker NAT, and unreachable IPv6 routes fail differently.

#### Verification

Fail a build or run the getent commands from troubleshooting; `curl -4` vs `curl -6` to Docker Hub from VM.

#### Closely confused with

One network script fixing DNS and IPv6 Hub failures as identical cases.

#### Engineering question

Given `host_dns=1 container_dns=0`, which layer do you debug first—systemd-resolved or Docker/MicroK8s NAT?

#### Beginner relevance

The CI failure footer encodes which network layer broke before you guess.

#### Specificity score

9

---

### FINDING — Disk pressure maps to Evicted/ImagePullBackOff/Pending while looking like app bugs

#### Source

`docs/troubleshooting.md` Disk health; `scripts/setup-cluster.sh` DISKSAFETY; `scripts/doctor.sh`; Makefile `doctor` / `reclaim`

#### Exact artifact

Kubelet `--container-log-max-size=10Mi`, `--container-log-max-files=3`, `--image-gc-high-threshold=80`, `--image-gc-low-threshold=60`; journald `SystemMaxUse=300M`; doctor `WARN_THRESHOLD=75` / `FAIL_THRESHOLD=90`; reclaim vacuums journal to 200M + unused image prune only

#### What is configured

Preventive caps on new VMs via `make setup`. Doctor non-zero exits on WARN/FAIL. Reclaim never touches PVC/TSDB.

#### Observable behaviour

Pods `Evicted`, disk-pressure taints, Helm timeouts, `No space left on device`. Doctor PASS/WARN/FAIL with PVC top-5 and Prometheus TSDB size.

#### Technical reason

Single-node 80 GB VM accumulates CI images, journald, Stage 7 metrics/logs.

#### Verification

`make doctor`; `make reclaim`; `df -h /` inside Multipass.

#### Closely confused with

App CrashLoop, ImagePull auth, or Pending due to CPU/memory requests only.

#### Engineering question

After WARN, does reclaim alone restore PASS if Prometheus retention is what filled the PVC?

#### Beginner relevance

Node disk symptoms present as pod failures; reclaim is not a metrics store shrinker.

#### Specificity score

9

---

### FINDING — Vault in-memory K8s auth lost after Mac sleep / Multipass hang

#### Source

`docs/troubleshooting.md` (“Mac reboot or sleep — auth/ledger pods sick”); Stage 5 `setup.sh` / `seed-vault-secrets.sh`

#### Exact artifact

`vault-agent-init` log `permission denied` on `auth/kubernetes/login`; recovery: re-run `setup.sh` + `seed-vault-secrets.sh` then delete auth/ledger pods

#### What is configured

Lab Vault often runs in non-persistent/dev-style mode for Stage 5; K8s auth binding is not durable across VM memory loss.

#### Observable behaviour

Auth/ledger `Unknown` or `Init:0/1`; postgres/frontend may still Run. `/auth/health` fails until rebind+seed.

#### Technical reason

Lost Vault Kubernetes auth config vs durable Postgres/git state.

#### Verification

`kubectl logs -n clearledger -l app=auth-service -c vault-agent-init --tail=10`; after recovery auth/ledger `2/2` and health 200.

#### Closely confused with

Need for full `make restore` snapshot as first step; Kyverno admission deny (different error plane).

#### Engineering question

What part of Vault state is durable in this lab install versus what must be re-seeded after sleep?

#### Beginner relevance

Documented recovery path is rebind+seed, not necessarily snapshot restore.

#### Specificity score

9

---

### FINDING — Auth lazy `create_all` after netpol vs import-time crash before `/health`

#### Source

`app/auth-service/main.py` (`_ensure_tables` comment); Stage 6 netpol apply order in troubleshooting/`make fix-65-prereqs`

#### Exact artifact

Comment: import-time `Base.metadata.create_all` crashed before `/health` when netpol briefly blocked postgres; tables now created on first DB use; engine reloads when Vault URL changes

#### What is configured

Readiness/liveness can succeed while DB path warms; netpol applied mid-life can still cause restart storms historically.

#### Observable behaviour

Post-netpol “random” auth restarts with older image/app patterns; current code keeps `/health` up.

#### Technical reason

Probe vs dependency ordering under default-deny egress.

#### Verification

Apply netpol; watch restart counts; confirm `/health` 200 before first DB write.

#### Closely confused with

OOMKill, Vault init failure, or ImagePullBackOff.

#### Engineering question

Should readinessProbe require DB connectivity explicitly once Vault+netpol are live?

#### Beginner relevance

Lab encodes a concrete probe-vs-dependency failure mode, not a fictional outage story.

#### Specificity score

8

---

### FINDING — Argo CD ApplicationSet CRD annotation too long on plain `kubectl apply`

#### Source

`docs/troubleshooting.md` (“Argo CD Install Fails: applicationsets Annotation Too Long”)

#### Exact artifact

Error `metadata.annotations: Too long: must have at most 262144 bytes` on `applicationsets.argoproj.io`; fix `kubectl apply --server-side --force-conflicts`

#### What is configured

Upstream Argo CD install requires server-side apply because last-applied-configuration annotation cannot hold the CRD.

#### Observable behaviour

Near-end of install: CRD invalid; partial resources may exist.

#### Technical reason

Client-side apply annotation size limit vs large CRD.

#### Verification

Reproduce with plain apply (lab warning) vs server-side apply; wait for `argocd-server` Ready.

#### Closely confused with

Generic YAML syntax error in Argo manifests.

#### Engineering question

After a partial client-side apply, which cleanup is required before server-side apply succeeds?

#### Beginner relevance

Install method (`--server-side`) is part of the control plane bring-up, not optional polish.

#### Specificity score

9

---

### FINDING — ChaosEngine in `litmus` because Kyverno Enforce blocks runners in `clearledger`

#### Source

`stages/stage-6.5-chaos-engineering/infra/chaos/*`; `litmus-rbac.yaml`; troubleshooting Stage 6.5

#### Exact artifact

ChaosEngines in namespace `litmus`, `appinfo.appns: clearledger`; SA `litmus-admin` ClusterRoleBinding to `cluster-admin`; pod-delete `PODS_AFFECTED_PERC=50`, `TOTAL_CHAOS_DURATION=30`

#### What is configured

Runners outside Kyverno-namespace match. Lab grants cluster-admin to chaos SA. Engines targeting clearledger for workloads.

#### Observable behaviour

Kyverno denies `*-runner` in clearledger. Health can stay 200 with 2 replicas during 50% delete. ChaosResult Error possible while health pass criteria still met (`run-chaos.sh`).

#### Technical reason

Admission namespace match vs resilience experiment scheduling; pass criteria combine HTTP + replica recovery.

#### Verification

`kubectl get chaosengine,chaosresult -n litmus`; try runner in clearledger → admit deny.

#### Closely confused with

Falco alerts on `kubectl exec` vs Litmus intentional pod delete.

#### Engineering question

Is `cluster-admin` for chaos SA acceptable for lab DORA evidence, or should a namespaced Role be written?

#### Beginner relevance

Optional stage; Kyverno success for apps and Litmus success for chaos use different namespaces by design.

#### Specificity score

9

---

## Configuration Behaviour

---

### FINDING — DAST opt-in and depends on live ingress; ZAP High+ jq gate

#### Source

`.github/workflows/ci.yaml` job `dast`; `stages/stage-3-security-gates/dast/zap-config.yaml`; `vars.ENABLE_DAST`

#### Exact artifact

`if: github.ref == 'refs/heads/main' && github.event_name == 'push' && vars.ENABLE_DAST == 'true' && …`; ZAP plan `errorLevel: "High"`; jq fails if High/Critical > 0; token inject via `ZAP_ACCESS_TOKEN_PLACEHOLDER`; base `http://clearledger.local`

#### What is configured

Unset → skipped. Self-hosted runner reaches lab ingress. Local `scripts/dast/smoke.sh` is a separate JWT oracle, not the CI job body.

#### Observable behaviour

Early ENABLE_DAST without Stage 2 reachability fails last job. Medium may warn depending on plan exit vs jq High+ gate.

#### Technical reason

DAST needs deployed HTTP surface; Stage 1 default is post-deploy optional.

#### Verification

Set variable after Argo healthy; inspect artifact `dast-reports`.

#### Closely confused with

`ENABLE_DAST` running `scripts/dast/smoke.sh` in Actions.

#### Engineering question

Does a ZAP Medium (warnExitValue 2) fail CI, or only the later jq High/Critical count?

#### Beginner relevance

Turning DAST on before the UI is live fails the last gate by reachability, not by app CVE.

#### Specificity score

10

---

### FINDING — `setup-hosts.sh` skips domains already present (stale Multipass IP)

#### Source

`scripts/setup-hosts.sh`; `scripts/ensure-kubeconfig.sh`; troubleshooting networking

#### Exact artifact

Hosts domains `clearledger.local`, `argocd.local`, `grafana.local`, `falco.local`, `litmus.local`, etc.; skip-if-present logic; kubeconfig `${KUBECONFIG:-~/.kube/${VM_NAME}-config}` rewritten from `microk8s config`

#### What is configured

Idempotent hosts without IP upsert. Kubeconfig refresh is a separate script.

#### Observable behaviour

After VM IP change: browser hits wrong IP; kubectl may fail on stale API server URL until `ensure-kubeconfig`.

#### Technical reason

Multipass DHCP/IP drift; hosts helper designed not to rewrite existing lines.

#### Verification

Compare `multipass info` IPv4 vs `/etc/hosts`; troubleshooting `sed` wipe then re-run setup-hosts; re-run ensure-kubeconfig.

#### Closely confused with

`setup-hosts.sh` always refreshing IP mappings.

#### Engineering question

After Multipass restart, which breaks first—kubectl (stale kubeconfig server) or browser (stale hosts IP)?

#### Beginner relevance

“Worked yesterday” often means IP/endpoint drift across two different fix scripts.

#### Specificity score

9

---

### FINDING — Frontend `/metrics` requires rebuilt images; stock panels stay at zero

#### Source

`stages/stage-7-observability/scripts/build-metrics-images.sh`; troubleshooting Stage 7 (“Request Rate panel empty”)

#### Exact artifact

Installer/dashboard PromQL `rate(http_requests_total[5m])`; stock Stage 1 images lack `/metrics` exporter until rebuild script

#### What is configured

Observability install alone does not emit app HTTP metrics.

#### Observable behaviour

Grafana Request Rate remains zero after Stage 7 install until rebuild+redeploy.

#### Technical reason

Instrumentation is an image/binary change, not a Helm values flip.

#### Verification

`bash stages/stage-7-observability/scripts/build-metrics-images.sh`; scrape metrics endpoint or watch PromQL.

#### Closely confused with

PrometheusOperator/ServiceMonitor mislabel as sole cause when app never exports the counter.

#### Engineering question

Which ServiceMonitor/PodMonitor selects the rebuilt auth/ledger metrics port after rebuild?

#### Beginner relevance

Empty dashboard panel can mean missing exporter, not only missing scrape config.

#### Specificity score

8

---

### FINDING — Pre-commit excludes Actions YAML from `check-yaml`; terraform_validate is manual stage

#### Source

`.pre-commit-config.yaml`

#### Exact artifact

`check-yaml` `exclude: ^\.github/workflows/`; `terraform_validate` `stages: [manual]`; gitleaks pin; hadolint-docker; `ruff` `files: ^app/`

#### What is configured

Local first line mirrors CI secrets scan rev; workflow YAML may pass pre-commit with syntax issues; terraform validate not on default commit.

#### Observable behaviour

Commit blocked on secrets/large files; bad workflow YAML may not fail check-yaml.

#### Technical reason

Actions YAML embeds shell that breaks strict YAML linters; terraform validate is expensive/opt-in.

#### Verification

`pre-commit run --all-files`; break workflow YAML vs app YAML intentionally.

#### Closely confused with

Pre-commit guaranteeing GitHub Actions YAML validity.

#### Engineering question

Which hook stage must be invoked to get `terraform_validate` before a Stage 8 PR?

#### Beginner relevance

Passing pre-commit ≠ valid CI workflow YAML.

#### Specificity score

9

---

## Security and Policy Decisions

---

### FINDING — SLSA provenance policy is Audit; Cosign signature policy is Enforce

#### Source

`infra/policies/verify-slsa-provenance.yaml`; `scripts/ci-publish-image.sh`

#### Exact artifact

ClusterPolicy `verify-slsa-provenance` `validationFailureAction: Audit`, attestation `predicateType: https://slsa.dev/provenance/v0.2`, condition `builder.id` `AnyIn` `https://github.com/*/clearledger/actions`; CI builder id `https://github.com/" + GITHUB_REPOSITORY + "/actions"`

#### What is configured

Signature ≠ provenance. Provenance Attestation check is separate and non-blocking in Audit.

#### Observable behaviour

Optional PolicyReport findings once key/attestations exist; Stage 4 core path not blocked by provenance alone.

#### Technical reason

Different predicate/prove surfaces in Kyverno verifyImages.

#### Verification

PolicyReports for `verify-slsa-provenance`; confirm fork `OWNER/clearledger` matches `*/clearledger/actions`.

#### Closely confused with

`require-signed-images` already proving build provenance.

#### Engineering question

Does `https://github.com/OWNER/clearledger/actions` satisfy `https://github.com/*/clearledger/actions` for your fork?

#### Beginner relevance

Signed image answers who signed; attestation answers how/where it was built.

#### Specificity score

9

---

### FINDING — JWT overlap rotation writes `NEW\nOLD`; DB rotation is create-before-drop

#### Source

`stages/stage-5-secrets-management/scripts/rotate-secret.sh`; `rotate-db-credentials.sh`; deferred `infra/deferred-by-stage/stage-5-secrets-management/vault/rotation-cronjob.yaml`

#### Exact artifact

JWT: `jwt_secret="${NEW}\n${OLD}"`, sleep **65s**, assert file prefix; DB: create `clearledger_v2` → update Vault URL → health → drop/rename; CronJob schedule `"0 2 1 * *"`, `concurrencyPolicy: Forbid`, deferred not auto-applied; Stage 7 alerts `SecretRotationOverdue*` on CronJob last schedule age 75d/90d

#### What is configured

App auth verifies any newline-separated secret, signs with first (`app/auth-service/main.py`). CronJob only exists after deliberate promote from deferred path; Kyverno hardens CronJob pods in clearledger.

#### Observable behaviour

JWT rotate without restart if agent refreshes. Wrong DB order → outage. CronJob absent → overdue alert may never fire usefully / CronJob missing.

#### Technical reason

Agent renewal cadence vs JWT TTL overlap; DB auth is stateful.

#### Verification

Scripts’ curl/`kubectl exec` checks; `kubectl get cronjob vault-secret-rotation -n clearledger`

#### Closely confused with

Rotation CronJob always present after Stage 5 README completion.

#### Engineering question

Does `SecretRotationOverdue*` fire if the CronJob was never applied (`kube_cronjob_status_last_schedule_time` absent)?

#### Beginner relevance

Documented lab exercises show rotation ordering failure modes without claiming a production outage.

#### Specificity score

9

---

### FINDING — Enforce policies match only namespace `clearledger` (CronJobs included)

#### Source

`infra/policies/drop-all-capabilities.yaml`, `disallow-privilege-escalation.yaml`, `require-resource-limits.yaml`; ArgoOutOfSync notes for `vault-secret-rotation`

#### Exact artifact

`validationFailureAction: Enforce`, `background: true`, match Pods in `clearledger` only; required `drop: [ALL]`, `allowPrivilegeEscalation: false`, requests+limits `"?*"`

#### What is configured

Any Job/CronJob pod in clearledger without hardening is denied—including rotation CronJob until hardened YAML used.

#### Observable behaviour

Argo OutOfSync / sync fail on unhardened CronJob; Litmus runners succeed in `litmus` NS.

#### Technical reason

Namespace-scoped admission applies to all Pod creators in that namespace.

#### Verification

`kubectl get clusterpolicy`; deploy unhardened Job in clearledger → deny; same in litmus → admit (absent other policies).

#### Closely confused with

Policies applying cluster-wide.

#### Engineering question

Why do ChaosEngine runners in `clearledger` fail admission while the same engine shape in `litmus` succeeds?

#### Beginner relevance

Admission guards every Pod shape in the namespace, not only Deployments.

#### Specificity score

9

---

### FINDING — Cosign key material is gitignored; only example pubkey committed

#### Source

`.gitignore`; `infra/cosign.pub.example`; CI `/tmp/cosign.key` from secret; lab embed scripts

#### Exact artifact

Ignore entries `cosign.key`, `cosign.pub`, `infra/cosign.pub`; example placeholder `MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE<YOUR_KEY_CONTENT_HERE>`

#### What is configured

Learner generates keys Stage 3; paste into policies; GitHub Secret holds private key for CI.

#### Observable behaviour

Fresh clone: no working verify key; Kyverno placeholder fails verify until embed.

#### Technical reason

Per-learner keys must not be in git history.

#### Verification

`git check-ignore cosign.key infra/cosign.pub`; `test -f infra/cosign.pub` on prepared lab machine.

#### Closely confused with

Repo containing a working lab Cosign pubkey.

#### Engineering question

How does `embed-cosign-pub-in-policies.sh` reconcile a gitignored pubkey with committed policy YAML?

#### Beginner relevance

Policy files with `PASTE_YOUR_…` are not ready for Enforce demos until keygen/embed.

#### Specificity score

9

---

## Networking and Scheduling

---

### FINDING — Netpol ingress NS selector is MicroK8s `ingress`, not `ingress-nginx`

#### Source

`infra/deferred-by-stage/stage-6-runtime-security/netpol/network-policies.yaml` (= stage-6 copy); troubleshooting Network policies / Stage 6

#### Exact artifact

`default-deny-all` + allow policies; ingress from NS selector `kubernetes.io/metadata.name: ingress`; monitoring egress `:4317`; vault `:8200`

#### What is configured

Deferred apply: early GitOps of default-deny breaks apps (README). Frontend egress remains deny (no allow) under default-deny egress.

#### Observable behaviour

Wrong ingress namespace label → 502 / no external traffic. Missing monitoring allow after OTEL → silent trace drop. Auth restarts after premature netpol → `make fix-65-prereqs`.

#### Technical reason

CNI default-deny + MicroK8s ingress controller namespace naming.

#### Verification

`kubectl get networkpolicy -n clearledger`; check NS labels; curl through ingress; test notification→postgres (blocked).

#### Closely confused with

Falco outbound WARNING meaning CNI blocked the packet.

#### Engineering question

Should manifests also allow namespace `ingress-nginx` for non-MicroK8s labs?

#### Beginner relevance

Desired netpol files in git ≠ enforced until Stage 6 apply; early apply can brick the app tree.

#### Specificity score

10

---

### FINDING — ALB Ingress does not strip prefixes; lab ALB is HTTP:80 only

#### Source

`stages/stage-8-aws-migration/manifests/ingress-aws.yaml`; `terraform/alb.tf`; aws Helm values disabling Grafana nginx ingress

#### Exact artifact

`ingressClassName: alb`, `target-type: ip`, `listen-ports: '[{"HTTP": 80}]'`, healthcheck `/health`; comment ALB does not strip path prefixes unlike nginx rewrite; AWS Grafana values `grafana.ingress.enabled: false` because ALB webhook rejects nginx IngressClass

#### What is configured

Path `/auth` → auth Service with full path forwarded. Homelab nginx rewrite semantics differ. HTTPS example needs `ACM_CERT_ARN` (not default).

#### Observable behaviour

Wrong health path → targets unhealthy. Homelab `clearledger.local` patterns fail on ALB hostname. Grafana only via port-forward on EKS with AWS values.

#### Technical reason

ALB ingress controller annotation-driven provisioning; ingress class and path semantics differ by environment.

#### Verification

`curl http://ALB_DNS/auth/health`; compare to MicroK8s nginx Ingress in `infra/manifests/ingress.yaml`.

#### Closely confused with

Copy-paste of homelab Ingress YAML onto EKS.

#### Engineering question

Do FastAPI apps need `root_path` adjustments for ALB prefix routing in this layout?

#### Beginner relevance

“Same Ingress” across environments is false here by class, annotations, and TLS posture.

#### Specificity score

9

---

### FINDING — ArgoCD `selfHeal: true` / `prune: true` with insecure server behind TLS ingress

#### Source

`stages/stage-2-gitops/argocd/clearledger-app.yaml`; `argocd-cmd-params.yaml`; troubleshooting drift/selfHeal/grpc-web

#### Exact artifact

Application syncPolicy `prune: true`, `selfHeal: true`; ConfigMap `server.insecure: "true"`, `server.grpc.web: "true"`; CLI `--grpc-web`

#### What is configured

Git is desired state. TLS terminates at nginx; server speaks HTTP behind it. Drift without recurse/kustomization can make demos no-op (troubleshooting).

#### Observable behaviour

Manual `kubectl set image` reverted after heal. CLI without `--grpc-web` warns / fails stream. Without cmd-params: redirect loops / stream 503.

#### Technical reason

GitOps reconcile loop + ingress TLS offload + grpc-web transport.

#### Verification

Edit live Deployment; wait for heal; `argocd app get clearledger --grpc-web`; confirm recurse + Deployment resources listed.

#### Closely confused with

Drift demo failure meaning selfHeal is broken (may be incomplete Application source/watch scope).

#### Engineering question

Is Synced+Progressing red tree a Git drift problem or a pod health problem after selfHeal?

#### Beginner relevance

ArgoCD reverting kubectl edits is the configured contract, not a bug.

#### Specificity score

9

---

## Verification Procedures

---

### FINDING — Prove Secrets gone from etcd while login still works (Vault path)

#### Source

Stage 5 README / LAB-GUIDE flow (delete app Secrets after inject); `app/auth-service/main.py` `_read_secret`

#### Exact artifact

`kubectl delete secret auth-service-secret ledger-service-secret` after inject; files `DATABASE_URL_FILE` / `JWT_SECRET_FILE` under `/vault/secrets`; verify login + `/auth/verify`

#### What is configured

Secret material moves from `secretKeyRef` to agent files. Postgres secret may remain.

#### Observable behaviour

`kubectl get secret` no longer lists app secrets; login still returns token; pods remain `2/2`.

#### Technical reason

Runtime reads files; etcd no longer holds those Secret objects after delete.

#### Verification

`kubectl get secret -n clearledger`; `kubectl exec … -- ls /vault/secrets`; curl login/verify.

#### Closely confused with

Deleting Secrets before seed/inject (CrashLoop / missing env).

#### Engineering question

How do you prove the running process no longer depends on Kubernetes Secrets after migrating to Vault files?

#### Beginner relevance

Absence of Secret objects + successful auth is the evidence pair; either alone is incomplete.

#### Specificity score

9

---

### FINDING — IRSA identity proof is `get-caller-identity` ARN class, not annotation presence alone

#### Source

`docs/troubleshooting.md` IRSA runbook; Stage 8 IAM/SAs

#### Exact artifact

`aws sts get-caller-identity` from workload SA; expect `assumed-role/<irsa-role>/…` not EC2 instance profile

#### What is configured

Five-step runbook: SA annotation → trust OIDC → `:sub` exact match → OIDC provider exists → Pod `serviceAccountName`

#### Observable behaviour

Annotation present but Pod on `default` SA → still node role. Wrong `:sub` → assume fails / falls back.

#### Technical reason

Credentials webhook injects only when Pod SA matches trusted subject.

#### Verification

Follow runbook commands in troubleshooting; compare `terraform output` role ARN to identity ARN.

#### Closely confused with

Non-empty `eks.amazonaws.com/role-arn` annotation alone proving IRSA works.

#### Engineering question

Which single mismatch still yields node role when the annotation ARN string is correct?

#### Beginner relevance

Prove assumed-role identity from inside the Pod, not only from YAML.

#### Specificity score

9

---

### FINDING — Health-check label for Kyverno is `app.kubernetes.io/component=admission-controller`

#### Source

`scripts/health-check.sh`; `docs/troubleshooting.md` (“Health check says Kyverno not running”)

#### Exact artifact

Correct label selector `app.kubernetes.io/component=admission-controller` vs historical wrong `app=kyverno`

#### What is configured

`make check-4` uses corrected selector in current script.

#### Observable behaviour

Older selector: “Kyverno not running” while pods are Running.

#### Technical reason

Helm chart label conventions ≠ generic `app=kyverno`.

#### Verification

`kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller`

#### Closely confused with

Kyverno actually down / CrashLoop.

#### Engineering question

Which label set does your health script query versus `kubectl get pods -n kyverno` default listing?

#### Beginner relevance

Automation can false-negative on label drift while the control plane pods are healthy.

#### Specificity score

8

---

## Environment and Architecture Changes

---

### FINDING — Bootstrap GitOps vs deferred Stage 5/6 controls (desired ≠ live)

#### Source

`infra/deferred-by-stage/README.md`; `infra/manifests/*`; Stage READMEs

#### Exact artifact

Argo source `infra/manifests/` retains early-stage `secretKeyRef` Secrets; deferred: Stage 5 rotation CronJob; Stage 6 NetworkPolicies—manual promote

#### What is configured

Ordering: Vault server and app stability before default-deny and rotation Job.

#### Observable behaviour

After Stage 1–4: secrets in etcd, no netpol, no rotation Job—advanced desired state present only as files under deferred/.

#### Technical reason

GitOps source of truth intentionally lags advanced stages until promote.

#### Verification

`kubectl get networkpolicy,secret,cronjob -n clearledger` vs deferred folder contents.

#### Closely confused with

“It’s in the clearledger monorepo so the cluster enforces it.”

#### Engineering question

What is the safest promote order for default-deny netpol relative to Vault inject and ingress labels?

#### Beginner relevance

Repo presence of a control is not cluster enforcement.

#### Specificity score

9

---

### FINDING — Terraform SM placeholders + `lifecycle.ignore_changes` on `secret_string`

#### Source

`stages/stage-8-aws-migration/terraform/secrets.tf`

#### Exact artifact

Secrets `${project}/postgres|auth-service|ledger-service`; initial JSON includes `CHANGE_ME_BEFORE_APPLY` / `PLACEHOLDER_RDS`; `ignore_changes = [secret_string]`; `recovery_window_in_days = 7`

#### What is configured

TF bootstraps objects; runtime rotation ownership moves outside Terraform. Destroy delayed by recovery window.

#### Observable behaviour

If PLACEHOLDER never replaced, apps get non-routable DB URLs. Later `terraform plan` does not revert rotated values.

#### Technical reason

Separate create-time bootstrap from continuous secret lifecycle.

#### Verification

Update SM outside TF; `terraform plan` shows no secret_string restore; confirm app can connect after manual patch.

#### Closely confused with

Vault KV remaining source of truth on AWS (replaced by SM).

#### Engineering question

Who writes the real RDS endpoint into `database_url` after apply—script or console—in your Stage 8 path?

#### Beginner relevance

Manual step remains after automation; `ignore_changes` encodes that ownership handoff.

#### Specificity score

8

---

### FINDING — Integration Compose uses plaintext env secrets (no Vault/CSI/netpol/Falco)

#### Source

`docker-compose.integration.yml`

#### Exact artifact

`JWT_SECRET=test-jwt-secret-key-for-local-integration`; `DATABASE_URL=postgresql://clearledger:clearledger@postgres:5432/clearledger`; frontend `Dockerfile.dev` `3000:8080`

#### What is configured

Same service binaries, Stage-0-style secret delivery, path routing for frontend E2E.

#### Observable behaviour

Healthchecks pass without K8s security stack.

#### Technical reason

Local integration proves app behavior, not hardened runtime posture.

#### Verification

`docker compose -f docker-compose.integration.yml up --build -d`; hit `:3000`.

#### Closely confused with

Cluster Stage 5+ secret posture.

#### Engineering question

Should compose inject `*_FILE` mounts to exercise Vault/CSI code paths?

#### Beginner relevance

Local green compose ≠ clearance of K8s admission/runtime controls.

#### Specificity score

8

---

### FINDING — AWS CI path filters vs always-build-all homelab CI

#### Source

`.github/workflows/ci-aws.yaml` (`dorny/paths-filter@v3`); `.github/workflows/ci.yaml`

#### Exact artifact

Path filters `app/{auth,ledger,notification,frontend}-service/**`; `force_all` workflow_dispatch; publish `environment: production` + `secrets.AWS_ACTIONS_ROLE_ARN`; AWS DAST if `vars.AWS_DAST_BASE_URL != ''` (health curls, not full ZAP)

#### What is configured

Docs-only commits skip rebuild graph. Homelab builds all four without equivalent path filter.

#### Observable behaviour

README-only commit: AWS build skipped. Force rebuild all four. Wrong OIDC fails at assume-role before scan.

#### Technical reason

Cost/time-aware rebuild; OIDC replaces self-hosted Docker Hub auth.

#### Verification

Change only a README → confirm build skipped; `workflow_dispatch` force_all → publish all.

#### Closely confused with

Homelab and AWS CI being the same pipeline shape.

#### Engineering question

If only `stages/stage-8-aws-migration/**` changes with `CLEARLEDGER_CI_TARGET=aws`, does anything rebuild?

#### Beginner relevance

AWS CI is thinner: path filters + ALB smoke, not the full ZAP suite.

#### Specificity score

9

---

## Possible Duplicates

Findings that share the same underlying technical mechanism:

| Mechanism | Findings that rely on it |
|---|---|
| GitHub Actions `if:` / repo `vars.*` gating | `CLEARLEDGER_CI_TARGET`, `ENABLE_ARGOCD_SYNC`, `ENABLE_DAST`, schedule skip without kube-bench job |
| Soft vs hard enforcement (evidence vs block) | Checkov soft-fail K8s; Cosign CI skip; ECR Audit/Ignore; SLSA Audit; Trivy ignore-unfixed / Grype only-fixed |
| Admission vs runtime vs network control planes | Kyverno Enforce; Falco detect; NetworkPolicy block; “deny-secrets” RBAC empty rules |
| Registry string / identity string exact match | `index.docker.io` vs `docker.io`; IRSA `:sub` StringEquals; GitHub OIDC `repo:owner/clearledger:environment:production` |
| Desired state in git vs live cluster | Deferred netpol/CronJob; Stage 1 infra update without Argo; Argo selfHeal; ESO default vs CSI swap |
| Multipass lab topology drift | Stale kubeconfig, stale `/etc/hosts`, Docker DNS vs host DNS, IPv6 Hub, disk Evicted |
| Namespace-scoped policy blast radius | clearledger Enforce CronJobs/Litmus runners; ChaosEngines in `litmus` |
| Secret delivery path differences | secretKeyRef → Vault files → ESO env → CSI `/mnt/secrets`; `_read_secret` / hardcoded ledger `/vault/secrets` |
| Probe / ordering under dependency loss | Kyverno liveness churn; auth lazy `create_all` vs netpol; Vault init after pod-delete chaos |

---

## Articles / docs as source archive (no packaging)

Mechanisms documented as durable runbooks (not hypothetical marketing narratives):

| Doc | Technical mechanisms archived |
|---|---|
| `docs/troubleshooting.md` | Runner labels, IPv6 Hub, DNS bit pair, Kyverno Bitnami/probes/selectableFields, Cosign URL false negative, Argo SSA CRD, Vault sleep wipe, IRSA/OIDC, disk doctor/reclaim, Falco UI vs postgres Sensitive File noise |
| `docs/kubernetes-audit-logging.md` | Sample RequestResponse audit on Secrets/SA; Falco vs API audit dual evidence; not auto-applied on MicroK8s |
| `docs/compliance-mapping.md` | Control → stage mapping (Vault, Falco, netpol, IRSA); lab retention claims |
| `stages/stage-8-aws-migration/docs/secrets-patterns.md` | Vault vs ESO vs CSI table; IRSA / tokenRequests |
| Stage READMEs + LAB-GUIDE | Stage ordering constraints and verification checklists |

---

## Products / customer-problem extract (stages as lab products)

| Product surface | Recurring customer-class problems encoded in repo |
|---|---|
| Stage 1 CI (self-hosted) | Queued forever (labels); Docker GID; DNS/IPv6; soft gates misread as full hardening |
| Stage 2 GitOps | CRD annotation limit; selfHeal; recurse/kustomization drift demo no-op; git update ≠ pods |
| Stage 4 Kyverno | Bitnami ImagePullBackOff; probe restart storm; wrong image URL false negative; kube-bench baseline |
| Stage 5 Vault | automount trade-off; seed missing; sleep wipe; CronJob vs Enforce; empty RBAC “deny” |
| Stage 6 Falco + netpol | Outbound FP vs netpol allow; deferred deny; ingress NS name; postgres Sensitive File noise |
| Stage 6.5 Litmus | Runner NS vs Kyverno; cluster-admin blast radius; ChaosResult Error vs health 200 |
| Stage 7 Observability | Metrics image rebuild; Loki query overload; Grafana ingress class on AWS |
| Stage 8 AWS | IRSA trust; OIDC github_owner placeholder; ESO vs CSI; ALB path/TLS; CI target flip |

No separate commercial product ZIP or marketing-article pack was present in this workspace beyond the lab stages and `docs/`.
