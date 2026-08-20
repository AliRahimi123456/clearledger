# Stage 1 — CI Pipeline (GitHub Actions + Self-Hosted Runner)

**Goal (from the book):** A `git push` builds images, scans them, pushes to Docker Hub, and
updates image tags in `clearledger-infra` — automatically. I still deploy manually
(`kubectl`) until Stage 2 (GitOps/ArgoCD) takes over deployment itself.

**Status: ✅ Done.** First fully green pipeline run confirmed end-to-end on 2026-08-11:
secrets scanned, SAST/IaC passed, all 4 images built + scanned clean + published to Docker
Hub, and `clearledger-infra` received an automated commit from "GitHub Actions Bot." This
took a genuinely long debugging session — six distinct real issues, documented below in the
order they were hit, since each is a legitimate lesson.

---

## Already done, ahead of time (carried over from Stage 0 prep)

- Docker Hub: all 4 image repos exist (`clearledger-auth-service`, `clearledger-ledger-service`,
  `clearledger-notification-service`, `clearledger-frontend`) under `rahimi123`.
- `clearledger-infra` GitHub repo created (empty).
- GitHub fine-grained PAT generated, scoped to `clearledger-infra`, Contents: Read and write.
- Docker Hub access token generated, Read & Write scope.
- GitHub Actions repository secrets set on `clearledger`, verified against
  `.github/workflows/ci.yaml` directly (not guessed): `DOCKER_USERNAME`, `DOCKER_PASSWORD`,
  `INFRA_REPO_TOKEN`. See `01-stage-0-raw-kubernetes.md` for the full story of getting these
  right (first attempt used wrong names).

Full readiness checklist per `stages/stage-1-ci-pipeline/README.md`:
- [x] `make check-0` passes
- [x] Docker Hub: four `clearledger-*` repositories
- [x] GitHub account; repos + PAT ready
- [x] Self-hosted runner installed and connected, with the `clearledger` label the workflow
      requires (see below for the full story — took several attempts)

---

## What's actually new in this stage

The book's default path (Mac + Multipass) installs the GitHub Actions self-hosted runner
**inside the Multipass VM**, so it can reach the local Kubernetes cluster and local Docker
daemon. I don't have a Multipass VM — my equivalent is the **WSL2 Ubuntu-20.04 distro**,
which already has Docker (via Desktop's WSL integration) and `kubectl` (via the wrapper I
built in Stage 0). The runner should install and run there instead.

Watch for any book instruction referencing "the VM" or a prompt like `ubuntu@clearledger` —
translate that to "my WSL2 shell" (`rahimighaznawi@LAPTOP-C6AI4REL:...$`), same translation
rule as Stage 0.

---

## Self-hosted runner — installed and running (2026-08-11)

Used GitHub's own official flow (`clearledger` repo → Settings → Actions → Runners → New
self-hosted runner → Linux/x64) rather than the book's exact text, since that section got
cut off mid-sentence both times it was pasted (character limit). GitHub generates the same
standard commands regardless, so nothing was lost.

**Installed in `~/actions-runner`** (home directory, not inside the `clearledger` git repo —
this is separate tooling, not app source):
```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.336.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.336.0/actions-runner-linux-x64-2.336.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.336.0.tar.gz
```

**Gotcha 1 — expired registration tokens.** The first `./config.sh --url ... --token ...`
attempt failed with a `404 Not Found` from GitHub's registration API. Cause: registration
tokens are short-lived (~1 hour), and enough time had passed since generating it
(mid-conversation, screenshot-to-command gap) that it expired. Fix each time this happened
(it happened repeatedly throughout this process): go back to the same GitHub Runners page,
which generates a **fresh** token on every visit, and use that one immediately.

**Gotcha 2 — the actually-important one: missing custom label.** First successful
registration used all defaults (accepted every interactive prompt, including "additional
labels" — left blank). Runner came up fine, showed `Idle` on GitHub, service installed and
running correctly. **But this was wrong** — before triggering anything, checked the actual
`.github/workflows/ci.yaml` and found every single job (all 9) specifies:
```yaml
runs-on: [self-hosted, clearledger]
```
My runner only had the auto-detected labels (`self-hosted`, `Linux`, `X64`) — no custom
`clearledger` label. Had this gone untriggered-until-later, every pipeline run would have
hung forever in "Waiting for a runner to pick up this job," since no registered runner would
match the required label combination. Caught by reading the workflow file before triggering
anything, per the book's own "read first before you run" principle.

**Fixing the label took several tries.** The `--labels clearledger` flag kept getting
dropped when re-typing the `config.sh` command by hand (easy to do — it's a long line).
Attempting `--replace` on an existing registration also failed outright ("Cannot configure
the runner because it is already configured"). Attempting `./config.sh remove` to start
clean then hit repeated `404`s too (same expired-token issue as Gotcha 1, compounding).
Eventually one registration attempt *without* `--labels` succeeded again by accident (typo),
creating a naming conflict on the next real attempt — `config.sh` then looped forever asking
"A runner exists with the same name / Would you like to replace? (Y/N)" → default-answered
N → asked again → infinite loop, had to `Ctrl+C` out of it.

**What actually fixed it:** stopped fighting the CLI `remove`/`--replace` flags entirely.
Deleted the stale runner directly from GitHub's web UI instead (Settings → Actions → Runners
→ "..." menu → Remove) — confirmed "Runner successfully deleted" / "There are no runners
configured." Then, with a genuinely clean slate on GitHub's side:
```bash
rm -f .runner .credentials .credentials_rsaparams   # clear local registration state too
./config.sh --url https://github.com/AliRahimi123456/clearledger --token <FRESH_TOKEN> --labels clearledger
```
This time the exact full command (with `--labels clearledger` actually present) was run
verbatim, no naming conflict since GitHub's side was empty. Succeeded cleanly.

**Installed as a systemd service** (not run in the foreground via `./run.sh`, which would tie
up a terminal and die when closed) — this is the WSL2 equivalent of the book's Multipass
approach, and works the same way since WSL2 has systemd enabled (from the Stage 0 setup):
```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```
**Verified on GitHub's Runners page** (more trustworthy than local output, since one earlier
`config.sh` run silently didn't display the labels-confirmation line): `LAPTOP-C6AI4REL` shows
all four labels — `self-hosted`, `Linux`, `X64`, `clearledger` — status `Idle`. Matches the
workflow's `runs-on: [self-hosted, clearledger]` requirement exactly.

**Lesson for later stages:** always double-check custom `runs-on` labels (or any other
workflow-specific requirement) *before* configuring a runner interactively — re-registering
after the fact is much more error-prone than getting it right in the first `config.sh` call.

**Note for later:** `scripts/runner-vm-state.sh` (what `make check-1`/`make runner-status`
actually call) is hard-wired to `multipass exec` throughout — it will report `no-multipass`
and always fail for this setup, same pattern as `vm-snapshot.sh` and `setup-hosts.sh`. Runner
health needs to be checked manually instead:
```bash
sudo systemctl status actions.runner.AliRahimi123456-clearledger.LAPTOP-C6AI4REL.service
```

---

## The actual pipeline structure (read from `.github/workflows/ci.yaml` before triggering)

9 jobs, sequential gates:
```
secrets-scan (Gitleaks)
   ├─→ sast (Semgrep)         ─┐
   └─→ iac-scan (Checkov)     ─┴─→ prepare-scanners (Trivy/Grype/Cosign install)
                                         └─→ build-images
                                                └─→ scan-images (Trivy/Grype — blocks on CVEs)
                                                       └─→ publish-images (push + optional Cosign sign)
                                                              └─→ update-manifests (commits new tags to clearledger-infra)
                                                                     └─→ dast (only if ENABLE_DAST=true, off by default)
```
`publish-images` references `secrets.COSIGN_PRIVATE_KEY`/`COSIGN_PASSWORD`, which I haven't
set up — checked `scripts/ci-publish-image.sh` directly and confirmed it degrades gracefully
(`⚠ COSIGN_KEY not set — skip sign/attest`, exits 0) rather than failing. Signing is properly
introduced in a later stage; fine to proceed without it now.

## First pipeline trigger (2026-08-11)

Found genuine uncommitted work already sitting in the repo to use as the trigger — the four
`DOCKER_USERNAME → rahimi123` edits made during Stage 0's manual deploy (`sed -i`, never
committed). Committed and pushed:
```bash
git add stages/stage-0-raw-kubernetes/infra/manifests/
git commit -m "chore: set Docker Hub username in Stage 0 deployment manifests"
git push
```

**Gotcha 1 — git identity not set.** First commit attempt failed: `Please tell me who you
are`. Never configured globally in this WSL2 environment before. Fixed:
```bash
git config --global user.name "Ali Madad"
git config --global user.email "ali.1996rahimiourzgani@gmail.com"
```
(Real name deliberately chosen over the GitHub handle `AliRahimi123456` — matches how real
engineering teams show authorship in commit history.)

**Gotcha 2 — no push credentials for `clearledger` itself.** `git push` prompted for a
username/password — GitHub doesn't accept account passwords for git operations, needs a PAT.
The only PAT that existed (`clearledger-ci`) was scoped to `clearledger-infra` only, for CI's
own use — nothing was scoped to push to `clearledger` from a human terminal. Generated one
more fine-grained PAT: name `clearledger-push`, repository `clearledger`, **Contents: Read
and write**. Used GitHub username (`AliRahimi123456`) + this token (as the password) at the
`git push` prompt. Succeeded: `a9e40b5..935bff6  main -> main`.

Commit `935bff6` pushed to `main` — this is what actually fired the workflow
(`on: push: branches: [main]`).

---

## Gotcha 3 — the workflow was Disabled the whole time

First push (`935bff6`) produced **zero runs of the actual `ci.yaml` workflow**. Went to the
Actions tab and found the workflow named "ClearLedger DevSecOps Pipeline (GitHub)" listed with
a **"Disabled"** tag — only a completely different workflow, `ci-aws.yaml` ("CI — AWS (ECR +
OIDC)"), had run. GitHub disables workflows automatically on forks in some cases; whatever the
cause, fix was simple: Actions → click the workflow → banner said "This workflow was disabled
manually" → **Enable workflow** button.

## Gotcha 4 — an empty commit doesn't trigger a `paths`-filtered workflow

After enabling it, pushed an empty commit (`git commit --allow-empty`) to re-trigger — **still
zero runs of `ci.yaml`.** Root cause: `ci.yaml` has `paths-ignore: [stage-8-aws-migration/**]`.
GitHub Actions has a documented quirk — path-filtered workflows do not trigger at all for a
push with **zero changed files**. Meanwhile `ci-aws.yaml` has no path filter, so it fired both
times regardless (its jobs just skip internally since `CLEARLEDGER_CI_TARGET != 'aws'`). Fix:
made a real, substantive change instead — added a note to `CHANGELOG.md` — and pushed that.
This finally triggered `ci.yaml` for real, confirmed by seeing it "Queued" in the Actions list.

## Gotcha 5 — every CI step using `sudo` failed (no TTY for a service)

First real run got exactly one job in before dying: `Secrets Scan (Gitleaks)` failed installing
Gitleaks — `sudo: a terminal is required to read the password`. Same root cause as two earlier
Stage 0 incidents (MicroK8s install, `microk8s enable rbac`): the GitHub Actions runner runs as
a background **systemd service** with no TTY attached, and several pipeline steps use `sudo`
(installing Gitleaks, Semgrep, Checkov, kustomize...). Fixed once, permanently, by granting the
runner's own user passwordless sudo (standard/expected practice for a personal self-hosted CI
runner, not a shared production box):
```bash
sudo visudo
# added at the end of the file:
rahimighaznawi ALL=(ALL) NOPASSWD:ALL
```
Verified: `sudo -n true && echo "passwordless sudo works"`. Re-ran the job — passed.

## Gotcha 6 — real CVEs found by the scan gates (expected, not a bug)

Once past Gotcha 5, the pipeline actually built and scanned images for the first time — and
correctly **failed** the `scan-images` gate on genuine findings. This is the gate working as
designed, not something broken. Two separate scanners, two separate findings, two separate fixes:

**Trivy** (`scan-images` → "Trivy scan all images") flagged `msgpack 1.1.2` (HIGH,
GHSA-6v7p-g79w-8964) and `setuptools 70.3.0` (HIGH, CVE-2025-47273) inside `auth-service`.
Investigated with `docker run --rm <image> pip show msgpack` (→ "not found") and `find / -iname
"vendor.txt"` — root cause: both are **bundled inside pip's own internal vendored
dependencies** (`pip/_vendor/msgpack/...`), not actual installed application packages.
`requirements.txt` already correctly pins `setuptools>=78.1.1` (satisfied — 84.0.0 is the real
installed copy). Added both to `.trivyignore`, with reasoning comments, matching the file's
existing format/precedent (`CVE-2026-7210` was already there for an analogous reason).

**Grype** (`scan-images` → "Auth SBOM + Grype") is a *separate* scanner with its own database —
`.trivyignore` doesn't apply to it; there's a dedicated `.grype.yaml`. Reproduced locally:
```bash
syft clearledger-auth-service:<sha> -o spdx-json=/tmp/sbom-auth.json
grype sbom:/tmp/sbom-auth.json --fail-on high --only-fixed
```
Found three HIGH-severity **CPython interpreter** CVEs (`CVE-2026-11940`, `CVE-2026-15308`,
`CVE-2026-11972`) — not application or dependency issues at all, genuine bugs in Python 3.13.15
itself, each fixable only by upgrading to an unstable Python 3.15 alpha/beta release. Exact same
category as the one exception already in `.grype.yaml` (`CVE-2026-7210`: "beta CPython in
production is not acceptable"). Added all three with `reason: fix-requires-prerelease`,
matching the existing entry's format. Verified locally (re-ran the same `grype` command — no
error, only Medium/Low findings remained, below the `--fail-on high` threshold) before pushing.

## Gotcha 7 — re-running an old page cancels the new run (concurrency group)

`ci.yaml` has:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```
Pushing a fix while still sitting on an *old* failed run's page and clicking "Re-run jobs"
there repeatedly **cancelled the genuinely new run** that the push had already triggered (both
share the same workflow+branch concurrency group). Cost real time twice before recognizing the
pattern. **Lesson: after pushing a fix, always navigate to the fresh run via the workflow's own
run list (or the direct API-confirmed URL) — never click "Re-run" on a stale, already-open run
page.** Confirmed the real run each time via a direct API check:
```bash
curl -s "https://api.github.com/repos/AliRahimi123456/clearledger/actions/runs?per_page=5" \
  | grep -E '"head_sha"|"name"|"conclusion"|"html_url".*runs/[0-9]'
```

## Gotcha 8 — `clearledger-infra` was a genuinely empty repo

Final blocker: `update-manifests` job failed at "Checkout infra repo" — `/usr/bin/git failed
with exit code 128`. Checked `curl -s https://api.github.com/repos/.../clearledger-infra` →
`404` (repo is Private, so unauthenticated API can't see it — a red herring at first). The real
answer: opened it in the browser and saw GitHub's "Quick setup" screen — the repo had **zero
commits**, so no `main` branch existed yet for `actions/checkout` to check out. Fixed by
creating one file (`README.md`) directly via GitHub's web UI, committed straight to `main`.
Re-ran the failed job only (not the whole pipeline) — checkout succeeded, and the rest of the
job (rsync manifests, `kustomize edit set image`, `git commit && git push`) completed cleanly,
landing a real commit from "GitHub Actions Bot" in `clearledger-infra`.

---

## Portfolio checkpoint

**Screenshot saved:** `setup-journal/screenshots/stage1-pipeline-green.png` — full job list
from run #3 (commit `010236b`), all real gates green: Secrets Scan, SAST, IaC Scan, Prepare
scanners, Build images, Scan images, Publish images, Update Manifests → GitHub. (`DAST` shows
grey/not-run — expected, off by default until `ENABLE_DAST=true`.) This is technically listed
as "Screenshot 6" in `SCREENSHOT-GUIDE.md` and labeled "after Stage 3" there — but since this
repo's actual `ci.yaml` bundles all those gates from Stage 1 onward rather than introducing
them progressively, it was genuinely earned at this point, not faked early.

**Manual checkpoint** (in place of `make check-1`, which will always report the runner as
missing on this setup — see the runner section above, same root cause as `vm-snapshot.sh` and
`setup-hosts.sh` being Multipass-only):
- [x] Runner shows `Idle` on GitHub's Runners page, with all 4 correct labels
      (`self-hosted`, `Linux`, `X64`, `clearledger`)
- [x] `systemctl status actions.runner....service` shows `active (running)`, `enabled`
- [x] A full pipeline run completed with every real gate green (Secrets/SAST/IaC/Build/
      Scan/Publish/Update Manifests)
- [x] `clearledger-infra` received a real automated commit from "GitHub Actions Bot" with
      updated image tags

## Final verified state

`clearledger-infra` now has 2 commits (the manual README + the CI bot's manifest update) and a
real `manifests/` folder. Docker Hub has 4 freshly-built, scanned, published images tagged with
the triggering commit SHA. This closes Stage 1's goal exactly as stated: *"every push to GitHub
automatically builds images, pushes them to Docker Hub, and updates image tags in
clearledger-infra."* Cluster itself is untouched by any of this (still running what Stage 0 put
there) — that gap (infra repo updates, cluster doesn't) is intentional per the book, and is
exactly what Stage 2 (GitOps/ArgoCD) closes next.

---

## Full command reference — every terminal command run today, in order

All commands below run inside WSL2 (`wsl -d Ubuntu-20.04`, then `cd` into `clearledger`)
unless noted otherwise. Token/SHA values are redacted/generic here — see the narrative
sections above for context on each.

**Readiness check (§1 "Am I ready?"):**
```bash
export DOCKER_USERNAME=rahimi123
make check-0
echo "$DOCKER_USERNAME"
curl -s -o /dev/null -w "%{http_code}" http://clearledger.local/auth/health
```

**Self-hosted runner — download, extract:**
```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.336.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.336.0/actions-runner-linux-x64-2.336.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.336.0.tar.gz
```

**Runner registration (several attempts before the label stuck — see Runner section above):**
```bash
./config.sh --url https://github.com/AliRahimi123456/clearledger --token <TOKEN>
./config.sh remove
rm -f .runner .credentials .credentials_rsaparams
./config.sh --url https://github.com/AliRahimi123456/clearledger --token <TOKEN> --labels clearledger
```

**Runner as a systemd service, and how to check it without sudo:**
```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
systemctl status actions.runner.AliRahimi123456-clearledger.LAPTOP-C6AI4REL.service --no-pager
pgrep -af Runner.Listener
```

**Git identity + first commit/push (Gotchas 1-2):**
```bash
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"
git status
git config --global user.name "Ali Madad"
git config --global user.email "ali.1996rahimiourzgani@gmail.com"
git add stages/stage-0-raw-kubernetes/infra/manifests/
git commit -m "chore: set Docker Hub username in Stage 0 deployment manifests"
git push
git config --global credential.helper 'cache --timeout=14400'
```

**Empty-commit trigger attempt, then the real fix (Gotchas 3-4):**
```bash
git commit --allow-empty -m "ci: trigger pipeline now that workflow is enabled"
git push
# (edited CHANGELOG.md by hand — see repo)
git add CHANGELOG.md
git commit -m "docs: note personal progress through Stage 0/1"
git push
```

**Passwordless sudo for the runner (Gotcha 5):**
```bash
sudo visudo
# added line: rahimighaznawi ALL=(ALL) NOPASSWD:ALL
sudo -n true && echo "passwordless sudo works"
```

**Investigating the Trivy CVEs locally (Gotcha 6, part 1):**
```bash
docker images | grep clearledger-auth-service
which trivy || ls ~/.local/bin/trivy
export PATH="$HOME/.local/bin:$PATH"
trivy image --severity CRITICAL,HIGH --ignore-unfixed clearledger-auth-service:<SHA>
docker run --rm clearledger-auth-service:<SHA> pip show msgpack
docker run --rm clearledger-auth-service:<SHA> sh -c "find / -iname 'setuptools-*' -maxdepth 8"
docker run --rm clearledger-auth-service:<SHA> sh -c "pip --version; find / -iname vendor.txt; find / -path '*_vendor*msgpack*' -o -path '*_vendor*setuptools*'"
```

**`.trivyignore` fix — edit, verify, ship:**
```bash
nano .trivyignore
cat .trivyignore
trivy image --severity CRITICAL,HIGH --ignore-unfixed clearledger-auth-service:<SHA>   # confirm Total: 0
git add .trivyignore
git commit -m "fix: ignore CVEs bundled in pip's internal vendored deps, not app dependencies"
git push
```

**Investigating the Grype CVEs locally, then `.grype.yaml` fix (Gotcha 6, part 2):**
```bash
syft clearledger-auth-service:<SHA> -o spdx-json=/tmp/sbom-auth.json
grype sbom:/tmp/sbom-auth.json --fail-on high --only-fixed
nano .grype.yaml
cat .grype.yaml
grype sbom:/tmp/sbom-auth.json --fail-on high --only-fixed   # confirm no HIGH+ error
git add .grype.yaml
git commit -m "fix: ignore Python interpreter CVEs with prerelease-only fixes (Grype)"
git push
```

**Confirming which run was real vs. cancelled (Gotcha 7) — run from Windows/Git Bash, not WSL:**
```bash
curl -s "https://api.github.com/repos/AliRahimi123456/clearledger/actions/runs?per_page=5" \
  | grep -E '"head_sha"|"name"|"conclusion"|"html_url".*runs/[0-9]'
```

**`clearledger-infra` empty-repo fix (Gotcha 8):** done via GitHub's web UI (create `README.md`
directly on `main`), no terminal commands needed for the fix itself — verified after via the
repo page showing 2 commits and a `manifests/` folder.

---

## Consolidated script (all of the above as one block)

Everything from this session combined into a single runnable reference. **Not meant to be
re-run on this machine** — Stage 1 is already done, and re-running the runner registration
would just tear down working state. This is for standing up the same setup on a *new* machine
from scratch. A few lines are genuinely interactive (marked below) and can't be scripted away:
`sudo visudo`/`sudo` password prompts, `git push` asking for username+token, `./config.sh`'s
own Q&A, and `nano` edits (shown as the content to add, not the keystrokes).

```bash
# --- one-time environment ---
export DOCKER_USERNAME=rahimi123
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"

# --- git identity (once per machine) ---
git config --global user.name "Ali Madad"
git config --global user.email "ali.1996rahimiourzgani@gmail.com"
git config --global credential.helper 'cache --timeout=14400'

# --- self-hosted runner: download + extract ---
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.336.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.336.0/actions-runner-linux-x64-2.336.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.336.0.tar.gz

# --- runner registration — INTERACTIVE: needs a fresh token from
#     github.com/AliRahimi123456/clearledger/settings/actions/runners/new,
#     and the --labels flag MUST be included or every CI job hangs forever
#     ("runs-on: [self-hosted, clearledger]" won't match a runner without it) ---
./config.sh --url https://github.com/AliRahimi123456/clearledger --token <FRESH_TOKEN> --labels clearledger
# (answers Enter/default to every prompt: runner group, runner name, labels, work folder)

# --- runner as a persistent systemd service ---
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status

# --- passwordless sudo for the runner user — REQUIRED, CI steps use sudo
#     and the runner has no TTY to answer a password prompt ---
sudo visudo
# add this exact line at the end of the file, save, exit:
#   rahimighaznawi ALL=(ALL) NOPASSWD:ALL
sudo -n true && echo "passwordless sudo works"

# --- clearledger-infra: MUST have at least one commit before CI's checkout
#     step will succeed. If it's a fresh empty repo, create one file via
#     GitHub's web UI (Quick setup → "creating a new file") before pushing. ---

# --- .trivyignore / .grype.yaml — already correct in this repo; only needed
#     again if new CVEs show up in future scans. Verify locally first: ---
export PATH="$HOME/.local/bin:$PATH"
cd "/mnt/c/Users/Ali Madad/OneDrive/Documents/FCC-Folder/devsecops-platform/clearledger"
trivy image --severity CRITICAL,HIGH --ignore-unfixed clearledger-auth-service:<TAG>
syft clearledger-auth-service:<TAG> -o spdx-json=/tmp/sbom-auth.json
grype sbom:/tmp/sbom-auth.json --fail-on high --only-fixed
# if either finds something legitimate (not exploitable / fix unavailable),
# add it to .trivyignore or .grype.yaml with a reasoning comment, matching
# the existing entries' format, then:
git add .trivyignore .grype.yaml
git commit -m "fix: <describe the specific CVE and why it's a false positive/accepted risk>"
git push   # INTERACTIVE: username + PAT token as password

# --- trigger the pipeline: needs a REAL file change (empty commits don't
#     trigger ci.yaml's paths-ignore filter), and the workflow must show
#     as Enabled (not Disabled) on the Actions tab first ---
git add <changed-file>
git commit -m "<real change>"
git push

# --- after pushing, ALWAYS find the new run via the API or the workflow's
#     own run list — never click "Re-run" on an old open run page, it
#     cancels the genuinely new run via the concurrency group ---
curl -s "https://api.github.com/repos/AliRahimi123456/clearledger/actions/runs?per_page=5" \
  | grep -E '"head_sha"|"name"|"conclusion"|"html_url".*runs/[0-9]'
```
