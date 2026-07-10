# ClearLedger DevSecOps: Interview Prep Sheet

Questions interviewers actually ask. Answers they actually want to hear.

---

## Table of Contents

- [How to Use This](#how-to-use-this)
- [Universal Questions](#universal-questions-every-interview-every-level)
  - [Walk me through your ClearLedger project](#q-walk-me-through-your-clearledger-project)
  - [Why did you choose this tool over X?](#q-why-did-you-choose-this-tool-over-x)
  - [What would you do differently?](#q-what-would-you-do-differently-if-you-built-this-again)
- [Stage-Specific Questions](#stage-specific-questions)
- [Stage 0: Kubernetes Fundamentals](#stage-0--kubernetes-fundamentals)
  - [StatefulSet vs Deployment for Postgres](#q-what-is-a-statefulset-and-why-did-you-use-it-for-postgres-but-not-for-your-app-services)
  - [Why UID 999 for Postgres vs UID 1000 for app pods?](#q-why-did-your-postgres-pod-run-as-uid-999-but-your-app-pods-ran-as-uid-1000)
  - [readOnlyRootFilesystem: what breaks and how did you handle it?](#q-what-does-readonlyrootfilesystem-true-break-and-how-did-you-handle-it)
- [Stage 1: CI Pipeline](#stage-1--ci-pipeline)
  - [Why a self-hosted runner?](#q-why-a-self-hosted-runner-instead-of-githubs-cloud-runners)
  - [Why update Git instead of running kubectl directly?](#q-your-ci-pipeline-updates-a-manifest-file-in-git-rather-than-running-kubectl-directly-why)
- [Stage 2: ArgoCD / GitOps](#stage-2--argocd--gitops)
  - [What does selfHeal actually mean?](#q-argocd-has-selfheal-true-in-your-config-what-does-that-actually-mean-in-practice-and-when-would-you-turn-it-off)
  - [How do you handle secrets in the infra repo?](#q-how-do-you-handle-secrets-in-the-infra-repo-that-argocd-watches)
- [Stage 3: Security Pipeline](#stage-3--security-pipeline)
  - [Trivy failed a build — what do you do?](#q-trivy-failed-a-build-in-your-pipeline-walk-me-through-exactly-what-you-do-next)
  - [What is an SBOM and why does it matter?](#q-what-is-an-sbom-and-why-does-it-matter-in-2026)
  - [Gitleaks found a secret — what do you actually do?](#q-gitleaks-found-a-secret-in-your-repo-the-ci-blocked-the-push-what-do-you-actually-do)
  - [Map your pipeline to DORA](#q-a-european-fintech-asks-you-to-map-their-devsecops-pipeline-to-dora)
- [Stage 4: Kyverno (Admission Control)](#stage-4--kyverno-admission-control)
  - [Enforce vs Audit mode](#q-what-is-the-difference-between-kyvernos-enforce-and-audit-mode-and-when-do-you-use-each)
  - [How do you handle a legitimate UID exception?](#q-a-statefulset-for-a-legitimate-database-needs-to-run-as-a-specific-uid-that-your-kyverno-policy-blocks-how-do-you-handle-that)
- [Stage 5: HashiCorp Vault](#stage-5--hashicorp-vault)
  - [How does Vault's Kubernetes auth method work?](#q-what-is-vaults-kubernetes-auth-method-and-how-does-it-work-mechanically)
  - [What happens when the Vault token expires mid-flight?](#q-what-happens-to-a-running-pod-if-the-vault-token-expires-mid-flight)
- [Stage 6: Falco (Runtime Security)](#stage-6--falco-runtime-security)
  - [Shell spawned at 2am — walk through your response](#q-falco-fires-an-alert-at-2am-shell-spawned-in-your-ledger-service-container-walk-me-through-your-response)
  - [How does Falco detect threats?](#q-how-does-falco-detect-threats-what-is-the-performance-overhead)
- [Stage 7: Observability](#stage-7--observability)
  - [How do you make dashboards actionable?](#q-security-dashboards-are-nice-how-do-you-make-them-actionable-rather-than-decorative)
- [Stage 8: AWS Migration](#stage-8--aws-migration)
  - [What changes between homelab and production EKS?](#q-what-changes-between-your-homelab-setup-and-a-production-eks-deployment)
  - [How do you handle multi-environment deployments?](#q-how-would-you-handle-multi-environment-deployments-devstaging-prod-with-this-architecture)
- [Questions to Ask the Interviewer](#the-closer--questions-to-ask-the-interviewer)
- [The One Rule](#the-one-rule)

---

## How to Use This

Every question below has three parts:

- **What they are really testing**: the interviewer's actual intent
- **Weak answer**: what most candidates say (what gets you rejected)
- **Strong answer**: what closes the offer

Do not memorize the strong answers. Internalize the logic. If you can explain
*why* in your own words under pressure, you own it. If you recite it, they
will feel it immediately.

---

## Universal Questions (Every Interview, Every Level)

---

### Q: Walk me through your ClearLedger project.

**What they are really testing:**
Do you understand what you built, or did you follow instructions?
Can you explain it to a non-engineer and an engineer equally well?

**Weak answer:**
"I built a Kubernetes cluster with ArgoCD, Kyverno, Falco, Vault, and Prometheus.
It's a three-service fintech app with a full DevSecOps pipeline."

That is a list of tools. It tells the interviewer nothing about judgment or understanding.

**Strong answer:**
"ClearLedger is a fintech transaction ledger — three FastAPI services handling
auth, transactions, and notifications. The app itself is straightforward.
The interesting part is how I built the security architecture around it.

I structured it in stages deliberately. Stage 0 is raw kubectl — no automation.
I did that on purpose so I could feel the pain of manual deployments before
solving it. By the time I got to ArgoCD in Stage 2, I understood exactly what
problem it was solving because I had lived the alternative.

The security pipeline runs Gitleaks for secrets, Semgrep for SAST, Trivy for
container CVEs, Checkov for IaC misconfigurations, and Cosign for image signing
— all before ArgoCD ever sees a manifest. Then Kyverno enforces policy at
admission, Vault handles secret injection at runtime, and Falco watches syscalls
inside running pods.

The thing I am most proud of is that the pipeline fails correctly. Each gate
produces a specific error that tells you exactly what is wrong and where. That
is as important as the happy path."

---

### Q: Why did you choose this tool over X?

Examples: "Why Kyverno over OPA Gatekeeper?" / "Why Falco over Aqua?" /
"Why Vault over AWS Secrets Manager?"

**What they are really testing:**
Did you evaluate options or just pick what a tutorial used?

**Kyverno vs OPA Gatekeeper:**
"Both enforce policy at admission. I chose Kyverno because its policies are
written in Kubernetes-native YAML — the same format as the resources they govern.
Gatekeeper uses Rego, which is a separate policy language with its own learning
curve. For a team that is mostly Kubernetes-fluent but not Rego-fluent, Kyverno
is lower friction. That matters for adoption. The best security policy is one
the team will actually maintain. If I were on a team with existing Rego investment
or complex policy logic that benefits from Rego's expressiveness, Gatekeeper
would be the better call."

**Falco vs commercial runtime security:**
"Falco is eBPF-based, open source, and kernel-level — it sees everything.
Commercial tools like Aqua or Sysdig have better UIs and managed threat intel
feeds, but they come with significant cost and vendor lock-in. For a homelab
and for teaching the concepts, Falco gives you direct access to the rules engine
so you understand what is actually being detected. In production at scale, the
calculus changes — the managed threat intelligence of a commercial tool can
outweigh the cost if your team is small."

**HashiCorp Vault vs AWS Secrets Manager:**
"Vault is cloud-agnostic. Secrets Manager is AWS-specific. I built the homelab
with Vault specifically so the Stage 8 migration to AWS would demonstrate
portability — you can swap Vault for Secrets Manager via External Secrets
Operator without changing the application code. In a real greenfield AWS-only
project, I would default to Secrets Manager for simplicity. Vault makes sense
when you have multi-cloud or on-prem workloads, or when you need dynamic secrets
— Vault can generate short-lived database credentials on demand, which Secrets
Manager cannot."

---

### Q: What would you do differently if you built this again?

**What they are really testing:**
Self-awareness. Engineers who cannot critique their own work cannot grow.

**Strong answer:**
"Two things.

First, network policies. I applied them in Stage 6 but I would put them in
Stage 0. Default-deny-all should be the starting point, not something you
retrofit. Retrofitting network policies in a running system means you are
discovering implicit service dependencies by breaking them. That is the wrong
order.

Second, secrets. In Stage 0 I intentionally used plaintext K8s Secrets to
demonstrate the problem before solving it in Stage 5. That was good pedagogy
but bad practice. In a real project I would never let plaintext secrets exist
in the cluster for any period of time, even temporarily. The lesson would be:
Vault from day one, even in development."

---

## Stage-Specific Questions

---

## STAGE 0 — Kubernetes Fundamentals

---

### Q: What is a StatefulSet and why did you use it for Postgres but not for your app services?

**What they are really testing:**
Do you understand Kubernetes primitives or did you copy manifests?

**Strong answer:**
"A StatefulSet gives each pod a stable, persistent identity: a consistent
hostname, ordinal index, and persistent volume that follows the pod across
restarts. That matters for Postgres because the data on disk must survive
pod restarts and the database needs a stable hostname for client connections.

My app services use Deployments because they are stateless. Any replica is
interchangeable. If a pod dies and restarts on a different node, it connects
to the same Postgres and Redis — it doesn't need to carry any state itself.
Giving stateless services a StatefulSet would add operational complexity
with no benefit."

---

### Q: Why did your Postgres pod run as UID 999 but your app pods ran as UID 1000?

**What they are really testing:**
Did you actually write those security contexts or paste them blindly?

**Strong answer:**
"The Postgres official image creates and uses a postgres system user with UID 999
internally. If I set runAsUser to 1000, Postgres would fail to start because
the process would not have permission to write to the data directory, which is
owned by UID 999. The official image documents this.

My FastAPI services have no such constraint — I chose UID 1000 as a convention
for application users. The important thing in both cases is that neither runs
as root. The specific UID matters less than confirming it is non-zero and
that it owns the files the process needs to write."

---

### Q: What does readOnlyRootFilesystem: true break, and how did you handle it?

**What they are really testing:**
Have you actually run these manifests, or did you just write them?

**Strong answer:**
"A read-only root filesystem means the container cannot write anywhere except
explicitly mounted volumes or emptyDir mounts. Applications that write temp
files, logs to disk, or create sockets in /tmp will break silently or crash.

For the FastAPI services, I had to verify that uvicorn does not write to the
filesystem at runtime — it logs to stdout, which is correct. No temp file
writes. The one thing that needs a writable path is the Vault agent sidecar,
which writes the injected secrets to /vault/secrets. That path is an emptyDir
volume, not the root filesystem, so the policy holds.

If I had a service that needed to write temp files, I would add an emptyDir
volume at /tmp rather than relaxing the read-only constraint."

---

## STAGE 1 — CI Pipeline

---

### Q: Why a self-hosted runner instead of GitHub's cloud runners?

**What they are really testing:**
Did you understand the network constraint, or did you just copy a tutorial?

**Strong answer:**
"GitHub's cloud runners have no visibility into my local lab network — they
cannot reach the MicroK8s cluster or the local Docker daemon inside the VM.
The self-hosted runner solves that by living inside the same VM. It connects
outbound to GitHub to pick up jobs, then executes everything locally where
it can reach the cluster.

This is also the pattern used in production for pipelines that need to reach
internal resources — a private cluster, an on-prem registry, or a VPC that
isn't publicly reachable. The self-hosted runner is the standard solution for
hybrid CI environments."

---

### Q: Your CI pipeline updates a manifest file in Git rather than running kubectl directly. Why?

**What they are really testing:**
Do you actually understand GitOps or can you just spell it?

**Strong answer:**
"This is the GitOps contract. When CI runs kubectl directly, two things
break down.

First, you have two sources of truth: what CI last deployed, and what
is in Git. They can diverge. Someone does a hotfix with kubectl apply
and the next CI run overwrites it. Or someone rolls back via Git but
the cluster is already running the newer version. You spend time
reconciling drift.

Second, you lose the audit trail. When Git is the source of truth,
every deployment is a commit. You know who changed what, when, and
why — the commit message is the change log. kubectl commands leave no
paper trail in the repository.

When CI updates the manifest in Git and ArgoCD syncs the cluster to Git,
Git and the cluster are always the same. ArgoCD's job is to maintain that
equivalence. If they drift — someone runs kubectl manually — ArgoCD
notices and reverts. The contract is enforced automatically."

---

## STAGE 2 — ArgoCD / GitOps

---

### Q: ArgoCD has selfHeal: true in your config. What does that actually mean in practice and when would you turn it off?

**What they are really testing:**
Deep understanding, not surface-level configuration.

**Strong answer:**
"selfHeal: true means ArgoCD continuously compares the live cluster state
against the desired state in Git. Any deviation — a manual kubectl edit,
a ConfigMap change via the dashboard, a replica count adjustment — gets
reverted on the next sync cycle, typically within three minutes.

In practice it means the cluster becomes immutable by policy. The only
way to change anything is through Git. That is exactly what you want in
a production fintech environment where change control is a compliance
requirement.

When would I turn it off? During an incident. If I need to make an
emergency hotfix directly on the cluster — scale up a deployment, add
an env var, change a resource limit — selfHeal would fight me. Standard
practice is to pause ArgoCD sync for the affected application during
incident response, make the emergency change, then commit the same change
to Git and re-enable sync. You never leave the cluster and Git diverged
permanently."

---

### Q: How do you handle secrets in the infra repo that ArgoCD watches?

**What they are really testing:**
Secret management awareness — a major fintech interview topic.

**Strong answer:**
"You do not put secrets in the infra repo. Ever. Not even encrypted.

The infra repo contains references to secrets, not the secrets themselves.
In Stage 5 of my project, the deployment manifests contain Vault annotations
that tell the Vault agent sidecar which secret paths to read at pod startup.
The actual credentials live in Vault.

For teams using Kubernetes Secrets, the pattern is Sealed Secrets or
External Secrets Operator. Sealed Secrets encrypts the secret with a
cluster-specific key so only that cluster can decrypt it — you can commit
the encrypted blob to Git safely. External Secrets Operator pulls from
an external store like AWS Secrets Manager, Azure Key Vault, or Vault and
creates the K8s Secret dynamically. The secret value never touches Git.

The red line: if I can read a credential by looking at the Git repo,
the secret management is broken."

---

## STAGE 3 — Security Pipeline

---

### Q: Trivy failed a build in your pipeline. Walk me through exactly what you do next.

**What they are really testing:**
Can you actually operate this tooling, not just configure it?

**Strong answer:**
"First I look at the Trivy output to understand the finding. It shows the
CVE ID, the package, the installed version, the fixed version, and the
severity. For a CRITICAL or HIGH finding, I need to know three things:
is there a fix available, is it actually exploitable in my context, and
what is the remediation path.

If there is a fixed version: I update the base image or the dependency
and rebuild. That is usually 80% of cases.

If the finding is in the base image with no fix yet: I check whether
the CVE is actually reachable in my container — if it's in a library
I don't use, or requires local access on a system where I have no shell,
the practical risk is different from the theoretical risk. I can add a
Trivy ignore file (.trivyignore) with the CVE ID and a documented
justification. That ignore file is code-reviewed and committed to Git —
it's an explicit decision, not a silent suppression.

If the finding is unfixable and exploitable: I escalate. In a fintech
context that triggers a risk acceptance process — someone with authority
has to sign off on the known risk. I document it, monitor it, and revisit
when a fix is available.

What I do not do is lower the severity threshold in the pipeline to make
the build go green. That defeats the purpose."

---

### Q: What is an SBOM and why does it matter in 2026?

**What they are really testing:**
Supply chain security awareness — a top-of-mind topic for fintech since EO 14028.

**Strong answer:**
"SBOM (Software Bill of Materials) is a machine-readable inventory of every
component in a software artifact: libraries, dependencies, their versions,
their licenses, and their known vulnerabilities.

In 2026 it matters for two reasons.

Regulatory: US Executive Order 14028 and subsequent CISA guidance require
SBOMs for software sold to the US federal government. The EU Cyber Resilience
Act has similar requirements taking effect for European markets. For a fintech
company with government or enterprise customers, producing an SBOM is becoming
a contractual requirement.

Operational: When a critical CVE drops — like Log4Shell in 2021 — the first
question is 'do we use this?' Without an SBOM, you spend days grepping
repositories. With an SBOM generated per build, you run grype against the SBOM
file and have the answer in seconds. You know exactly which services are
affected, which versions, and you can prioritize patching.

In my pipeline, Syft generates the SBOM at build time and Grype scans it for
known vulnerabilities as a separate step. Both artifacts are stored alongside
the image. The SBOM is signed with the same Cosign key as the image."

---

### Q: Gitleaks found a secret in your repo. The CI blocked the push. What do you actually do?

**What they are really testing:**
Incident response knowledge — leaking a secret is a real incident.

**Strong answer:**
"Blocking the push is step one. But the secret is already in the git history
even if it didn't make it to the remote. That is the real problem.

Step one: rotate the secret immediately. Assume it is compromised. The credential
is invalidated before I do anything else. This is non-negotiable in fintech —
rotation first, investigation second.

Step two: remove it from git history. git filter-repo or BFG Repo Cleaner can
rewrite the commit history to remove the file or replace the secret value with
a placeholder. This requires a force push to the remote and all contributors
pulling the new history.

Step three: post-incident review. How did the secret end up in the code? Was
there a pre-commit hook that should have caught it locally before the push?
Pre-commit hooks with Gitleaks running locally catch this before CI does.

Step four: add a pre-commit hook to prevent recurrence. The CI scan is the
safety net. The pre-commit hook is the first line of defense. Both should run."

---

### Q: A European fintech asks you to map their DevSecOps pipeline to DORA.
Walk me through how ClearLedger satisfies each pillar.

**What they are testing:**
Domain knowledge — do you know what DORA is and can you connect
technical controls to regulatory requirements?

**Strong answer:**
"DORA has five pillars. I can map ClearLedger to each.

Pillar 1 (ICT Risk Management): Trivy and Checkov systematically
identify ICT risks before deployment. Kyverno and RBAC enforce
mitigations at runtime. Vault protects secrets — a core ICT risk
vector in fintech.

Pillar 2 (Incident Management): Falco detects incidents in real time.
Alertmanager routes notifications. Loki and K8s audit logs provide the
post-incident analysis trail DORA requires. Every alert has a documented
runbook annotation.

Pillar 3 (Resilience Testing): DAST tests in the pipeline validate
that the running application handles BOLA attacks, JWT manipulation,
and negative amounts correctly. kube-bench runs the CIS benchmark.
Falco break-and-detect scenarios are documented tests.

Pillar 4 (Third-Party Risk): Syft generates SPDX SBOMs for every
build — a machine-readable inventory of every third-party component.
Grype scans them. Cosign verifies third-party image integrity.

Pillar 5 (Information Sharing): The SBOM is in SPDX-JSON format —
the machine-readable format CISA recommends for interoperability.
The compliance dashboard provides an auditable security posture record.

The key insight for DORA: it does not require new tools. It requires
understanding which existing controls satisfy which requirements and
generating evidence that they work. That evidence — the pipeline
artifacts, the Grafana dashboards, the kube-bench reports — is what
a DORA audit actually looks for."

---

## STAGE 4 — Kyverno (Admission Control)

---

### Q: What is the difference between Kyverno's Enforce and Audit mode, and when do you use each?

**What they are really testing:**
Operational judgment — this is a common fintech interview question.

**Strong answer:**
"Enforce mode blocks the resource from being created if it violates the policy.
The API server returns an error. Nothing is deployed.

Audit mode allows the resource to be created but records the violation in a
PolicyReport. The deployment succeeds, the violation is logged.

The right rollout sequence is always Audit first, then Enforce.

When you introduce a new policy to an existing cluster, you do not know what
is already running that would violate it. If you set Enforce immediately, you
block legitimate workloads. Audit mode lets you see the blast radius — how
many existing resources would fail this policy — before you enforce it.

In my project, I started Enforce from day one because I was building from
scratch. Every resource I created had to comply from the beginning. In a real
migration to a cluster with existing workloads, I would run Audit for two weeks,
fix the violations in the manifests, confirm the PolicyReport is clean, then
switch to Enforce.

The worst thing you can do is leave a policy in Audit mode permanently. Audit
mode is not security. It is observation. It needs a defined timeline to Enforce
or it is security theater."

---

### Q: A StatefulSet for a legitimate database needs to run as a specific UID that your Kyverno policy blocks. How do you handle that?

**What they are really testing:**
Policy exceptions — real world is not always clean.

**Strong answer:**
"Kyverno supports policy exceptions. I would create a PolicyException resource
that grants a specific workload an exemption from a specific rule, with explicit
documentation of the reason.

```yaml
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: postgres-root-exception
  namespace: clearledger
spec:
  exceptions:
    - policyName: disallow-root-containers
      ruleNames: [check-runAsNonRoot]
  match:
    any:
      - resources:
          kinds: [Pod]
          namespaces: [clearledger]
          names: [postgres-*]
```

That exception is code-reviewed, committed to Git, and goes through the same
ArgoCD pipeline as everything else. It is an explicit documented decision, not
a silent policy weakening.

The alternative — weakening the policy to allow all StatefulSets to run as root
— is wrong. You would be creating a broad exception to fix a narrow problem.
Exceptions should be as specific as possible. This exception applies only to
the postgres pods in the clearledger namespace."

---

## STAGE 5 — HashiCorp Vault

---

### Q: What is Vault's Kubernetes auth method and how does it work mechanically?

**What they are really testing:**
Do you understand the trust chain, not just the configuration?

**Strong answer:**
"The Kubernetes auth method establishes a trust relationship between Vault and
the Kubernetes API server. Here is the trust chain step by step.

When a pod starts, Kubernetes automatically mounts a service account JWT token
at /var/run/secrets/kubernetes.io/serviceaccount/token. This is a cryptographically
signed token that proves the pod's identity to the Kubernetes API server.

The Vault agent sidecar takes that token and presents it to Vault's
auth/kubernetes/login endpoint along with the role name it wants.

Vault calls the Kubernetes TokenReview API to validate the JWT — it asks the
Kubernetes API server 'is this token valid, and does it belong to the service
account and namespace I expect?'

If the validation passes, Vault issues a Vault token scoped to the policies
attached to that role. The sidecar uses that Vault token to read the secrets
the app needs and writes them to /vault/secrets as files.

The key security property: the pod never has a Vault token hardcoded. It earns
a time-limited Vault token at startup by proving its Kubernetes identity.
If the pod's service account is not bound to a Vault role, it gets nothing."

---

### Q: What happens to a running pod if the Vault token expires mid-flight?

**What they are really testing:**
Operational depth — resilience and failure modes.

**Strong answer:**
"The Vault agent sidecar handles token renewal automatically. It runs
continuously in the pod alongside the app container and renews the Vault token
before it expires. The default TTL in my setup was one hour with the sidecar
renewing at the two-thirds mark — 40 minutes.

For the secret files themselves, the sidecar can be configured to re-read the
secret from Vault when the token is renewed and update the file if the value
has changed. This enables secret rotation without pod restart — the app reads
the file fresh on each use rather than caching the value in memory at startup.

Where this breaks down: if the Vault server itself becomes unavailable after
the pod has started, the existing secret files remain intact and the app
continues to function — the secrets are already on disk. But if the pod
restarts during a Vault outage, the sidecar cannot authenticate and the pod
will fail to start. This is why Vault high availability — using Raft storage
with multiple Vault nodes — is critical for production fintech. A single Vault
node is a single point of failure for your entire deployment pipeline."

---

## STAGE 6 — Falco (Runtime Security)

---

### Q: Falco fires an alert at 2am. Shell spawned in your ledger-service container. Walk me through your response.

**What they are really testing:**
Incident response process — this is a senior-level question in any DevSecOps interview.

**Strong answer:**
"First — contain before you investigate. The instinct is to start investigating
immediately, but containment comes first in fintech. If an attacker has a shell
inside a pod that touches financial data, every second of continued access is
additional risk.

Containment: isolate the pod from the network immediately by applying a
NetworkPolicy that denies all ingress and egress to that specific pod.
Do not delete the pod — you lose evidence. Isolate it.

```bash
kubectl label pod AFFECTED_POD incident=isolated
```

With a NetworkPolicy that denies traffic to pods with that label, the pod
is network-isolated but still running. Processes are paused, filesystem
is intact.

Preserve evidence: capture the pod state before anything else.

```bash
kubectl exec AFFECTED_POD -- ps aux > evidence/processes.txt
kubectl exec AFFECTED_POD -- netstat -an > evidence/connections.txt
kubectl logs AFFECTED_POD > evidence/logs.txt
```

Investigate: check what the shell did. Falco logs tell you the process
name, the user, the command line. Check for:
- What files were accessed or modified
- What network connections were made (data exfiltration?)
- What processes were spawned from the shell

The Falco alert telling me a shell was spawned is the start, not the end.
I need to know what the shell did.

Notify: in fintech, a potential breach has regulatory notification requirements.
The security and compliance team is in the loop from the moment I confirm
the alert is not a false positive.

Post-incident: how did the attacker get a shell? Command injection via the
API? A compromised dependency that exec'd a shell? The root cause determines
whether this is a code fix, a dependency update, or a policy change."

---

### Q: How does Falco detect threats? What is the performance overhead?

**What they are really testing:**
Technical depth on the tool, not just knowing it exists.

**Strong answer:**
"Falco uses eBPF — extended Berkeley Packet Filter — to attach probes to
kernel system calls. Every syscall that a process makes — file opens, network
connections, process forks, privilege changes — passes through the eBPF probe.
Falco evaluates the syscall against its rules engine in kernel space before
it completes.

The overhead depends on the number of rules and the syscall volume of your
workloads. In typical web service workloads — like ClearLedger — eBPF overhead
is 3-8% CPU on the node running Falco. That is the modern eBPF driver. The
older kernel module driver had higher overhead and required kernel headers.

At high syscall volumes — hundreds of thousands of events per second per node —
the overhead increases. You tune for this by making Falco rules more specific
rather than broad. A rule that fires on every open_read is more expensive than
one that fires on open_read where fd.name is /etc/shadow. The specificity of
the condition reduces the evaluation cost.

The tradeoff: broader rules catch more, cost more. Narrower rules are cheaper
but might miss novel attack patterns. In fintech I would start narrow and
specific, tune based on actual alert volume, and use the commercial Falco
threat rules feed for broader coverage rather than writing overly broad
custom rules."

---

## STAGE 7 — Observability

---

### Q: Security dashboards are nice. How do you make them actionable rather than decorative?

**What they are really testing:**
Operational maturity — a lot of teams have dashboards that nobody looks at.

**Strong answer:**
"A dashboard without an alert threshold is a report. It shows you what happened.
It does not help you when something is happening.

Every security metric in my Grafana setup has a defined alert condition in
Prometheus Alertmanager. The Kyverno violation panel alerts if violations
exceed 5 in a 10-minute window — that suggests something is actively trying
to deploy non-compliant workloads. The Falco CRITICAL alert panel pages
immediately — no threshold, any CRITICAL alert is an incident.

The second piece is runbooks. Each alert links to a runbook that describes
exactly what to do when it fires. Not 'investigate the issue' — specific:
which kubectl commands to run, what to look for, who to notify, what to
preserve as evidence. The alert is the trigger. The runbook is the response.

The third piece is review cadence. Weekly, I look at the policy violation
trend. If violations are increasing, something in the development process
is changing. That is a conversation with the team before it becomes an
incident. Security metrics should drive team behavior, not just record it."

---

## STAGE 8 — AWS Migration

---

### Q: What changes between your homelab setup and a production EKS deployment?

**What they are really testing:**
Real-world awareness. Can you translate homelab experience to production?

**Strong answer:**
"The architecture does not change. The infrastructure underneath it does.
The tools — ArgoCD, Kyverno, Falco, Prometheus — run identically on EKS.
I chose them specifically for that portability.

What actually changes:

Image registry: from the local MicroK8s registry to ECR. This means
configuring IRSA — IAM Roles for Service Accounts — so the EKS nodes
can pull from ECR without storing AWS credentials anywhere. The node
IAM role gets the ECR pull permission. No credentials to manage.

Secrets: from self-hosted Vault to either Vault on EKS or AWS Secrets
Manager via External Secrets Operator. The application code does not
change — it still reads from /vault/secrets or from a K8s Secret.
The source of that secret changes.

Ingress: from the MicroK8s nginx ingress to the AWS Load Balancer Controller
with an ALB. The ingress manifest annotations change. The service definitions
do not change.

Storage: from the MicroK8s hostpath storage class to EBS-backed PersistentVolumes
via the EBS CSI driver. The PVC definitions do not change.

Networking: from /etc/hosts domains to Route53 records pointing at the ALB.
TLS terminates at the ALB with an ACM certificate rather than a self-signed cert.

What I learned in the homelab that applies directly: every kubectl command,
every Helm chart, every Kyverno policy, every Falco rule, every ArgoCD
application definition. All of it is identical. The cloud is just the
infrastructure underneath."

---

### Q: How would you handle multi-environment deployments (dev/staging/prod) with this architecture?

**What they are really testing:**
Scaling the architecture — a natural senior follow-up.

**Strong answer:**
"Two approaches depending on team size and risk tolerance.

The first is Kustomize overlays in the infra repo. You have a base directory
with shared manifests, and overlay directories per environment that patch
the differences — replica counts, resource limits, image tags, feature flags.
ArgoCD has one Application per environment pointing at the corresponding
overlay path. Same Git repo, different paths.

```
infra/
  base/
    deployment.yaml
    service.yaml
  overlays/
    dev/
      kustomization.yaml    # patches: replicas=1, image=:dev-tag
    staging/
      kustomization.yaml    # patches: replicas=2, image=:staging-tag
    prod/
      kustomization.yaml    # patches: replicas=3, image=:prod-tag
```

The second is separate infra repos per environment. More operational overhead,
but cleaner separation — production manifests are never in the same repo as
development manifests. Better for compliance in regulated industries where
you need to demonstrate that prod changes go through a separate approval process.

In both cases, promotion is a Git operation. A pull request merges the
staging image tag into the prod overlay. The PR is the change control record.
The reviewer approval is the release gate. ArgoCD syncs when the PR merges.
No one runs kubectl in production directly."

---

## The Closer — Questions to Ask the Interviewer

Ask one or two. These signal you think operationally, not just architecturally.

- "How does your team currently handle the gap between what your pipelines allow
  and what the cluster actually enforces at admission time?"

- "What does your incident response process look like when your runtime security
  tool fires a CRITICAL alert in production?"

- "How do you manage secret rotation across your services without downtime?"

- "What is your current SBOM posture, and do your enterprise customers require one?"

---

## The One Rule

If an interviewer asks something you genuinely do not know:

*"I haven't encountered that specific scenario, but here is how I would approach it..."*

Then reason through it using what you do know. An interviewer who sees you apply
sound reasoning to an unfamiliar problem learns more about you than one who sees
you recite a memorized answer. The project gave you the mental models. Trust them.
