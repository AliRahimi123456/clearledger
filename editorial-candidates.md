# Editorial Candidates — Audience × Search × Specificity

Ranking rule: **publish priority is not technical specificity**.

A broad, searchable problem with strong evidence can outrank a sharper but narrower lab collision.

Scores per candidate:

| Dimension | Scale |
|---|---|
| **Audience surface** | 5 broad one-tool → 1 supporting detail only |
| **Searchable problem** | 5 people Google/ask-AI the symptom → 1 manufactured curiosity |
| **Tech specificity** | from source mine (named artifacts in repo) |
| **Diag/Decision** | 5 strong split or forced trade-off → 1 thin |

**Publish priority** ≈ weighted blend favoring audience + search first, then diag/decision, then specificity, then evidence quality (all below are repo-proven).

---

## Rescored publish queue

### Rank 1 — GitHub Actions: Online runner, job still queued

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **5** | **5** | 9 | 5 |

**SOURCE:** `.github/workflows/ci.yaml` (`runs-on: [self-hosted, clearledger]`); `docs/troubleshooting.md`
**SUBJECT:** Label set matching vs Online status
**STOPS:** recognizes exact problem
**QUESTION:** Why does an Online self-hosted runner leave jobs on “Waiting for a runner…” when `runs-on` requires an extra custom label?
**MUST INCLUDE:** `runs-on: [self-hosted, clearledger]` · label ≠ display name · Settings → Labels
**RUIN:** “check your runner configuration”
**HOOK:** Runner Online. Job waiting. Matching is labels `[self-hosted, clearledger]`, not the runner name.

**Why #1:** Maximum surface + exact searchable symptom. Spec is enough; demand is huge.

---

### Rank 2 — Argo CD: `Repository not found` for a repo that exists

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **5** | 9 | 5 |

**SOURCE:** troubleshooting ComparisonError; Stage 2 private `clearledger-infra`
**SUBJECT:** Private GitHub 404 wording + Argo credentials / wrong Application URL
**STOPS:** needs to diagnose symptom
**QUESTION:** Why does Argo report `ComparisonError: Repository not found` when the repo opens in the browser?
**MUST INCLUDE:** private infra · PAT / `argocd repo add` · App `repoURL` still `YOUR_GITHUB_USERNAME` · `repo list` Successful ≠ App URL correct
**RUIN:** “check credentials” without GitHub’s private-repo error string
**HOOK:** Browser opens the infra repo. Argo says Repository not found. Unauthenticated access to a private GitHub repo returns that string — and a Successful credential entry does not fix an Application still pointing at the placeholder owner.

**Why high:** Two common tools; error text is Googled constantly.

---

### Rank 3 — IRSA: annotation present, identity still node role

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **5** | 10 | 5 |

**SOURCE:** `terraform/iam.tf`; IRSA runbook; SA annotations
**SUBJECT:** Proving Pod IRSA vs node instance profile
**STOPS:** needs to diagnose symptom
**QUESTION:** What proves IRSA is live, and which `:sub` / `serviceAccountName` mismatches leave `get-caller-identity` on the node role?
**MUST INCLUDE:** `get-caller-identity` · `eks.amazonaws.com/role-arn` · `StringEquals` `:sub` · Pod SA
**RUIN:** “check trust policy” without ARN class proof
**HOOK:** Annotation looks right. From the Pod, identity is still the EC2 instance profile until `:sub` and `serviceAccountName` match.

---

### Rank 4 — GitHub Actions OIDC: AssumeRoleWithWebIdentity denied

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **5** | 9 | 5 |

**SOURCE:** `iam.tf` GHA ECR role; `ci-aws.yaml` `environment: production`; troubleshooting
**SUBJECT:** OIDC `:sub` must include `environment:production` / real `github_owner`
**STOPS:** needs to diagnose symptom
**QUESTION:** Why does ECR publish fail with `Not authorized to perform sts:AssumeRoleWithWebIdentity` when the IAM role exists?
**MUST INCLUDE:** `repo:OWNER/clearledger:environment:production` · job `environment: production` · `YOUR_GITHUB_USERNAME` leftover · `AWS_ACTIONS_ROLE_ARN`
**RUIN:** “OIDC is hard”
**HOOK:** Role exists. Workflow uses OIDC. AssumeRole still denied — trust `:sub` is `repo:OWNER/clearledger:environment:production`, and placeholder owners fail forever.

**Note:** Sibling to #3 (Pod IRSA vs Actions OIDC). Same AWS story, different searchable error. Publish as separate pieces weeks apart.

---

### Rank 5 — Kubernetes RBAC: empty “deny” Role

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **5** | **4** | 10 | 5 |

**SOURCE:** `infra/manifests/rbac/rbac.yaml` (`clearledger-deny-secrets`, `rules: []`)
**SUBJECT:** RBAC is allow-only
**STOPS:** disagrees with claim / wants mechanism
**QUESTION:** What does an empty ClusterRole named deny-secrets enforce after another binding grants Secrets?
**MUST INCLUDE:** `rules: []` · RoleBinding to `default` · `kubectl auth can-i` before/after
**RUIN:** interview slogan without `can-i`
**HOOK:** ClusterRole `clearledger-deny-secrets` has `rules: []`. Bind a secrets Role. `can-i get secrets` becomes yes.

**Why above Cosign:** One-tool RBAC surface + eternal interview/misconfig traffic. Spec remains 10.

---

### Rank 6 — Terraform: `lifecycle.ignore_changes` on secret values

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **5** | **4** | 8 | 5 |

**SOURCE:** `stages/stage-8-aws-migration/terraform/secrets.tf`
**SUBJECT:** Create placeholders, refuse to own rotations
**STOPS:** faces same decision
**QUESTION:** Why bootstrap SM secrets with placeholders, then ignore `secret_string` so plan never reverts rotated values?
**MUST INCLUDE:** `ignore_changes = [secret_string]` · `PLACEHOLDER_RDS` / `CHANGE_ME_BEFORE_APPLY` · recovery window 7d · who writes real RDS URL
**RUIN:** “don’t put secrets in Terraform” sermon
**HOOK:** Terraform creates the secret with a placeholder, then `ignore_changes` on `secret_string`. Later rotations must not be reverted by plan.

**Why climbed:** Pure Terraform surface; searchable lifecycle question; prior ranking buried it under Stage-8 specificity.

---

### Rank 7 — Vault + SA: `automountServiceAccountToken` vs inject

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **5** | 10 | 5 |

**SOURCE:** bootstrap vs Stage 5 auth Deployment
**SUBJECT:** CIS automount off vs Vault K8s login
**STOPS:** faces same decision
**QUESTION:** Why does `automountServiceAccountToken: false` cause `permission denied` on `auth/kubernetes/login`?
**MUST INCLUDE:** field flip · `vault-agent-init` log · token path · CIS 5.1.6
**RUIN:** “trade-offs exist”
**HOOK:** CIS wants automount false. Vault needs the projected SA token. Keep both → init dies on `auth/kubernetes/login`.

---

### Rank 8 — Docker Hub: DNS bit pair vs IPv6 unreachable

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **5** | 9 | 5 |

**SOURCE:** CI Network diagnostic; troubleshooting DNS + IPv6
**SUBJECT:** Three Hub reachability failure classes
**STOPS:** needs to diagnose symptom
**QUESTION:** How do `host_dns`/`container_dns` and AAAA `network is unreachable` split one Hub failure?
**MUST INCLUDE:** bit pair · `1 0` vs `0 0` · `curl -4`/`curl -6` · `gai.conf` / `disable_ipv6`
**RUIN:** one script fixes all three
**HOOK:** Hub pull fails. Read `host_dns`/`container_dns` first. If those pass and the log shows `[2600:…]: network is unreachable`, you are not in DNS.

**Note:** Multipass context is example environment; problem class is Docker/Linux networking — keep that framing.

---

### Rank 9 — Argo CD install: annotations Too long 262144

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **5** | 8 | 4 |

**SOURCE:** troubleshooting Argo ApplicationSet CRD
**SUBJECT:** Client-side apply annotation size vs large CRD
**STOPS:** recognizes exact problem
**QUESTION:** Why does plain `kubectl apply` fail on `applicationsets.argoproj.io` with Too long: 262144?
**MUST INCLUDE:** CRD name · byte limit · `last-applied-configuration` · `--server-side --force-conflicts`
**RUIN:** “just use SSA” without the error
**HOOK:** Install dies on `applicationsets.argoproj.io`: annotations Too long (262144). Plain apply stuffed the CRD into `last-applied-configuration`.

**Form:** Short technical note. High search traffic on exact error.

---

### Rank 10 — Argo CD: Synced but selfHeal “not working” (resources never watched)

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **4** | 9 | 5 |

**SOURCE:** troubleshooting drift demo; Application `path: manifests`
**SUBJECT:** Incomplete rendered resources vs broken selfHeal
**STOPS:** needs to diagnose symptom
**QUESTION:** Why can `kubectl set image` leave the App Synced with no revert if Deployments are absent from rendered resources?
**MUST INCLUDE:** `argocd app resources | grep Deployment` · kustomization listing · Synced ≠ watching
**RUIN:** “selfHeal is broken” as thesis
**HOOK:** Live image changed. Argo Synced. SelfHeal did not fail — those Deployments were never in the Application’s rendered resources.

---

### Rank 11 — Argo CD: Synced + Progressing / `DATABASE_URL is not set`

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **4** | 8 | 5 |

**SOURCE:** troubleshooting red pods; Stage 2 decision tree
**SUBJECT:** Sync Status vs Health; wrong desired state (Vault annotations too early / missing `secretKeyRef`)
**STOPS:** needs to diagnose symptom
**QUESTION:** Why can Sync be Synced while health stays Progressing with `DATABASE_URL is not set`?
**MUST INCLUDE:** Sync vs Health · `grep vault.hashicorp` vs `secretKeyRef` · Stages 2–4 contract
**RUIN:** “Synced ≠ healthy” as the whole post
**HOOK:** Sync Synced. Health Progressing. Auth: `DATABASE_URL is not set`. Sync applied the wrong desired state (Vault before Stage 5, or lost `secretKeyRef`).

---

### Rank 12 — Cosign/Kyverno: unsigned admitted → ImagePullBackOff vs deny

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **3** | **4** | 10 | 5 |

**SOURCE:** `require-signed-images.yaml`; troubleshooting signature silent
**SUBJECT:** `verifyImages` registry string vs pull failure
**STOPS:** needs to diagnose symptom
**QUESTION:** Under Enforce/Fail, why does one unsigned path admit then ImagePullBackOff while another denies with `verify-cosign-signature`?
**MUST INCLUDE:** `index.docker.io/*/clearledger-*` · `docker.io` unmatched · unpushed tag · deny text · `cosign verify`
**RUIN:** “policies fail silently”
**HOOK:** Same unsigned intent. Match `index.docker.io/*/clearledger-*` → deny. Else → Pod then ImagePullBackOff.

**Why dropped from old #1:** Spec perfect; audience is Kyverno/`verifyImages` feature depth. Still publish — after broader AWS/Actions/RBAC/Argo authentication pieces. Beginners meet ImagePullBackOff constantly; Kyverno string match is the specialized part.

---

### Rank 13 — Vault proof: delete Secrets, login still works

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **3** | 9 | 5 |

**SOURCE:** Stage 5 delete-after-`2/2`; `_read_secret`; `/vault/secrets`
**SUBJECT:** etcd Secret removal after file inject
**STOPS:** wants mechanism / faces decision
**QUESTION:** What pair of observations proves login no longer depends on Kubernetes Secrets?
**MUST INCLUDE:** wait `2/2` · `get secret` · `ls /vault/secrets` · login 200 · delete-too-early CrashLoop
**RUIN:** “Vault is better”
**HOOK:** `auth-service-secret` gone from `get secret`. Login still returns a token. Both required.

**Search softer** (people rarely type the proof). **Teaching demand high.** Schedule after searchable AWS/Argo pieces; excellent portfolio/LinkedIn technical walkthrough.

---

### Rank 14 — Bitnami `kubectl` ImagePullBackOff (Kyverno cleanup)

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **5** | 9 | 4 |

**SOURCE:** `kyverno/values.yaml`; troubleshooting
**SUBJECT:** Cleanup/hooks pull fail ≠ admission dead
**STOPS:** needs to diagnose symptom
**QUESTION:** When kyverno NS shows ImagePullBackOff on `bitnami/kubectl:1.28.5`, is the webhook down — and what disables that path?
**MUST INCLUDE:** `cleanupJobs.enabled: false` · `bitnamilegacy/kubectl` · chart 3.2.8 · check admission-controller Ready separately
**RUIN:** “Kyverno broken” from cleanup pods
**HOOK:** ImagePullBackOff on `bitnami/kubectl` is cleanup/hooks. Admission-controller can still be Ready — lab values disable those jobs.

**Search:** Exact image pull failures were (and still are) heavily queried after Bitnami Hub changes.

---

### Rank 15 — Falco WARNING vs NetworkPolicy allow (Vault/OTel)

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **3** | 10 | 5 |

**SOURCE:** Falco outbound rule; deferred netpol
**SUBJECT:** Detect allowlist ≠ CNI allowlist
**STOPS:** needs to diagnose symptom
**QUESTION:** Why does netpol-allowed Vault/OTel traffic still Falco WARN?
**MUST INCLUDE:** Falco DNS allow names · netpol :8200/:4317 · WARNING vs drop
**RUIN:** “detection ≠ prevention” thesis
**HOOK:** Netpol allows Vault. Falco still WARNs — outbound allowlist never listed `vault`.

---

### Rank 16 — External Secrets vs CSI vs Vault file mount (etcd presence)

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **4** | 10 | 5 |

**SOURCE:** Stage 8 secrets-patterns; ESO/CSI; `_read_secret`
**SUBJECT:** Where secrets live after “leaving hardcoded Secrets”
**STOPS:** faces same decision
**QUESTION:** For the same reader code, what differs in etcd under Vault files vs ESO vs CSI — and which is Stage 8 default?
**MUST INCLUDE:** etcd Secret yes/no · `/vault/secrets` · `/mnt/secrets` + `DATABASE_URL_FILE` · ESO default
**RUIN:** anti-etcd slogan
**HOOK:** Same `_read_secret`. Vault: files. ESO: Secrets return to etcd. CSI: `/mnt/secrets`. Default here is still ESO.

---

### Rank 17 — CSI: `tokenRequests[0].audience=sts.amazonaws.com`

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **3** | **4** | 9 | 4 |

**SOURCE:** `install-csi-secrets.sh`
**SUBJECT:** CSI + IRSA projected token audience
**STOPS:** needs to diagnose symptom
**QUESTION:** Why does the mount fail until Helm sets tokenRequests audience `sts.amazonaws.com`?
**MUST INCLUDE:** audience field · `enableSecretRotation` · IRSA on app SA · error text if known
**RUIN:** “remember IRSA for CSI”
**HOOK:** SPC and IRSA look right. Mount missing until `tokenRequests[0].audience=sts.amazonaws.com`.

**Search rises if the piece leads with the exact driver/mount error string.**

---

### Rank 18 — NetworkPolicy blocks ingress (wrong NS selector)

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **4** | 8 | 4 |

**SOURCE:** deferred netpol; Stage 6 troubleshooting
**SUBJECT:** default-deny + ingress namespace selector
**STOPS:** needs to diagnose symptom
**QUESTION:** After default-deny, why 502 when allow selects `kubernetes.io/metadata.name: ingress`?
**MUST INCLUDE:** default-deny · NS selector · generalize beyond MicroK8s name
**RUIN:** lab-only ingress name rant
**HOOK:** Default-deny on. Ingress 502. Allow NS label does not match the controller’s namespace.

**Frame as:** netpol allow from wrong ingress controller NS — MicroK8s `ingress` is the example.

---

### Rank 19 — Kyverno PolicyException `ruleNames` mismatch

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **3** | **3** | 10 | 5 |

**SOURCE:** `postgres-root-exception`; live rule names; stage-4 copy drift
**SUBJECT:** Exception keyed to exact rule names
**STOPS:** needs to diagnose symptom
**QUESTION:** Why can an applied PolicyException fail to skip the intended rule?
**MUST INCLUDE:** exact `ruleNames` · rename after Vault · live ClusterPolicy dump
**RUIN:** “exceptions are dangerous”
**HOOK:** Exception applied. Root still denied. `ruleNames` ≠ live rules.

**High for Kyverno specialists; later in public queue.**

---

### Rank 20 — JWT overlap: `NEW\nOLD`, sign first / verify any

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **3** | **3** | 9 | 5 |

**SOURCE:** `rotate-secret.sh`; `_load_jwt_secrets` / `create_token` / `decode_token`
**SUBJECT:** File overlap rotation without restart
**STOPS:** faces decision / wants mechanism
**QUESTION:** How does multiline JWT secret enable verify of old tokens while signing with only the new first line?
**MUST INCLUDE:** `NEW\nOLD` · `secrets[0]` · verify loop · ~65s · no restart
**RUIN:** glue to DB drop
**HOOK:** File is two lines. Sign with line 1; verify accepts either; wait ~65s for agent refresh; Deployment does not restart.

---

### Rank 21 — Falco UI: postgres Sensitive File flood vs Shell Spawned

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **3** | **4** | 8 | 4 |

**SOURCE:** Stage 6 troubleshooting; SCREENSHOT-GUIDE
**SUBJECT:** Finding the real alert under Critical noise
**STOPS:** needs to diagnose symptom
**QUESTION:** Where is Shell Spawned when UI is Critical Sensitive File on postgres-0?
**MUST INCLUDE:** Sensitive File · Shell Spawned · log grep · exec trigger
**RUIN:** “Falco is noisy”
**HOOK:** UI Critical Sensitive File on postgres. Grep logs for `Shell Spawned` on auth-service.

---

### Rank 22 — Checkov: `--soft-fail` kubernetes vs hard-fail Dockerfiles

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **3** | 9 | 4 |

**SOURCE:** `ci.yaml` `iac-scan`
**SUBJECT:** Which framework is merge-blocking
**STOPS:** faces decision
**QUESTION:** Green iac-scan — did K8s harden, or only Dockerfiles?
**MUST INCLUDE:** `--framework kubernetes --soft-fail` · Dockerfile hard-fail HIGH/CRITICAL · skip `Dockerfile.dev`
**RUIN:** “green ≠ secure” as title energy
**HOOK:** Checkov ran. Job exited 0. Kubernetes used `--soft-fail`; Dockerfile HIGH/CRITICAL block merges.

---

### Rank 23 — DB user rotation: create-before-drop

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **4** | **4** | 8 | 5 |

**SOURCE:** `rotate-db-credentials.sh`
**SUBJECT:** Stateful credential order
**STOPS:** faces decision
**QUESTION:** Why create `clearledger_v2`, flip Vault URL, health-check, then drop/rename?
**MUST INCLUDE:** ordered steps · health · contrast mention only vs JWT
**RUIN:** “be careful with databases”
**HOOK:** Create `clearledger_v2`, point Vault at it, confirm health, then drop the old user. Drop-first cuts live connections.

**Audience/search solid; slightly less unique source fingerprint than Vault automount.** Keeps mid-queue.

---

### Rank 24 — Litmus runners vs Kyverno Enforce namespace

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **2** | **2** | 9 | 4 |

**SOURCE:** ChaosEngines in `litmus`
**SUBJECT:** Schedule chaos outside Enforce NS
**STOPS:** faces decision (chaos+policy teams)
**QUESTION:** Why Engine NS `litmus` while `appns: clearledger`?
**LAB-HEAVY.** Publish for niche chaos/security audience only.

---

### Rank 25 — kube-bench regression baseline

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **2** | **2** | 10 | 4 |

**SOURCE:** `run-kube-bench.sh`; baseline JSON
**SUBJECT:** Regression gate vs absolute FAIL counts
**Platform/CIS retainers.** Not a broad DevOps lead.

---

### Rank 26 — `CLEARLEDGER_CI_TARGET`

| Audience | Search | Spec | Diag/Dec |
|---:|---:|---:|---:|
| **1** | **1** | 10 | 4 |

**SOURCE:** `ci.yaml` / `ci-aws.yaml`
**Repo-local routing.** Supporting detail inside an OIDC/AWS CI piece (#4), not a lead.

---

## Priority matrix (summary)

| Pub # | Candidate | Aud | Sea | Spec | Prev mistake |
|---:|---|---:|---:|---:|---|
| 1 | Actions runner labels | 5 | 5 | 9 | Ranked mid despite max demand |
| 2 | Argo private repo “not found” | 4 | 5 | 9 | Under-promoted |
| 3 | IRSA identity proof | 4 | 5 | 10 | OK previously |
| 4 | GHA OIDC AssumeRole | 4 | 5 | 9 | Under-promoted vs Pod IRSA |
| 5 | RBAC empty deny | 5 | 4 | 10 | Overshadowed by Cosign |
| 6 | TF ignore_changes secrets | 5 | 4 | 8 | Buried as Stage-8 niche |
| 7 | automount vs Vault | 4 | 5 | 10 | OK |
| 8 | host_dns / IPv6 Hub | 4 | 5 | 9 | OK |
| 9 | Argo CRD 262144 | 4 | 5 | 8 | Dismissed as tip; search gold |
| 10 | Argo not watching Deployments | 4 | 4 | 9 | Missing early |
| 11 | Synced + wrong desired state | 4 | 4 | 8 | Framed as meta Synced≠Healthy |
| 12 | Cosign index.docker.io match | 3 | 4 | 10 | **Over-ranked as #1 on spec alone** |
| 13 | Delete Secrets proof | 4 | 3 | 9 | High teach, softer search |
| 14 | Bitnami kubectl pull | 4 | 5 | 9 | Merged into Kyverno essay wrongly |
| … | specialized / lab | ≤3 | ≤3 | high | Spec-led inflation |

---

## Write order (next 10) under this model

1. Runner labels (Actions)
2. Argo “Repository not found”
3. IRSA `get-caller-identity`
4. GHA OIDC AssumeRole `:sub`
5. RBAC `rules: []`
6. Terraform `ignore_changes` on secrets
7. Vault automount
8. Hub DNS vs IPv6
9. Argo CRD 262144 (short)
10. Cosign admit vs ImagePullBackOff *(spec showcase, not opener)*

---

## Still supporting-only

`ENABLE_ARGOCD_SYNC` · Cosign CI soft-skip alone · schedule-without-kube-bench · Grafana zero metrics alone · disk doctor as commodity lead · `CLEARLEDGER_CI_TARGET` as lead

---

## Hooks (top 10 only)

1. Runner Online. Job Waiting. Labels must include `clearledger` — Online is not eligibility.
2. Browser opens the infra repo. Argo: Repository not found. Private GitHub + missing/wrong credentials (or Application still on `YOUR_GITHUB_USERNAME`).
3. Annotation set. From the Pod, `get-caller-identity` still shows the node instance profile.
4. IAM role exists. `AssumeRoleWithWebIdentity` denied — `:sub` needs `repo:OWNER/clearledger:environment:production`.
5. ClusterRole deny-secrets has `rules: []`. Bind a secrets Role → `can-i` yes.
6. TF creates SM secret with placeholder, then `ignore_changes = [secret_string]` so rotations aren’t reverted.
7. automount false for CIS + Vault inject → `permission denied` on `auth/kubernetes/login`.
8. Hub fail: check `host_dns`/`container_dns`; AAAA unreachable is not DNS.
9. Argo install: `applicationsets.argoproj.io` annotations Too long (262144) — need server-side apply.
10. Unsigned image path: match `index.docker.io/*/clearledger-*` → Cosign deny; else → often ImagePullBackOff.
