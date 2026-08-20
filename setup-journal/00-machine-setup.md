# ClearLedger Machine Setup Journal

Personal notes on every tool installed for the ClearLedger DevSecOps lab, why it's needed,
and what I actually did on this machine. Kept outside `clearledger/` since it's not part
of the lab repo itself — just my own reference.

**My setup path:** WSL2-native MicroK8s (not Multipass). My machine has 15.8 GB RAM,
below the lab's recommended 24 GB. Multipass would run a full separate VM (via Hyper-V) on
top of Windows, which is heavier. Instead, MicroK8s runs directly inside my existing
**Ubuntu-20.04 WSL2** distro — no second layer of virtualization, since Docker Desktop
already uses WSL2 as its backend. The lab's own scripts explicitly support this
("Linux, or Windows via WSL2/Ubuntu" path in `scripts/configure-vm-network.sh`).

---

## Checkpoint discipline (every ✋ Hands-on checkpoint, every stage)

At every hands-on checkpoint in the book:

1. Run the command it gives.
2. Compare my output against the book's "Expected" output.
3. If it doesn't match, fix it before continuing — don't stack unverified steps.
4. Once `make check-N` passes for that stage, snapshot before moving on.

**Snapshotting — do NOT use `make snapshot STAGE=N`.** That target is hard-wired to Multipass
(`scripts/vm-snapshot.sh` calls the `multipass` CLI directly and exits with "multipass not
found" otherwise) — it will not work on this WSL2-native setup. Use the WSL2 equivalent
instead, which captures the entire distro (MicroK8s state, all deployed resources, container
images) at that point in time:

```powershell
wsl --export Ubuntu-20.04 "C:\Users\Ali Madad\clearledger-snapshots\stageN.tar"
```

To restore one later (⚠ destructive — replaces my *current* Ubuntu-20.04 entirely):
```powershell
wsl --unregister Ubuntu-20.04
wsl --import Ubuntu-20.04 "C:\Users\Ali Madad\wsl-distros\Ubuntu-20.04" "C:\Users\Ali Madad\clearledger-snapshots\stageN.tar"
```

Each export is several GB and takes a couple of minutes — machine has 586GB+ free as of
2026-08-04, not a constraint. Snapshots saved so far live in
`C:\Users\Ali Madad\clearledger-snapshots\`.

---

## 1. Docker Desktop

**What it is:** The engine that builds, runs, and manages containers — the actual
`docker build` / `docker run` machinery, plus a GUI dashboard.

**Why the lab needs it:** ClearLedger's three microservices (`auth-service`,
`ledger-service`, `notification-service`) and the frontend are each packaged as Docker
images. I build these images locally, push them to Docker Hub, and Kubernetes pulls
them from there to run as pods. Without Docker, there's nothing to build or push.

**What I did:**
- Downloaded and installed via **Per-user install** (no admin password needed, installs to
  `%LOCALAPPDATA%\Programs\DockerDesktop`).
- Enabled **WSL Integration** for `Ubuntu-20.04` in Settings → Resources → WSL Integration,
  so the `docker` command works both in Windows terminals *and* inside the WSL2 Ubuntu shell
  I'm using for everything else.
- Verified with `docker run hello-world` — confirms the Docker daemon (background service)
  is reachable and can pull images from Docker Hub.

**Key fact:** Docker Desktop on Windows doesn't run containers natively on Windows — it
runs a lightweight Linux VM under the hood (via WSL2) and containers actually execute there.
That's why WSL2 integration matters.

---

## 2. WSL2 (Windows Subsystem for Linux) + Ubuntu-20.04

**What it is:** A real Linux kernel running inside a lightweight, tightly-integrated VM on
Windows. Not an emulator — actual Ubuntu, with near-native performance and shared
networking/filesystem access with Windows.

**Why the lab needs it:** MicroK8s (the Kubernetes distribution this lab uses) only runs on
Linux. The lab's default instructions launch a *separate* Ubuntu VM via Multipass to get a
Linux environment. Since Windows already has WSL2, I'm using that existing Ubuntu
environment instead — it's already Linux, already had Docker integration, and avoids a
second VM eating RAM.

**What I did:**
- Discovered I already had `Ubuntu-20.04` installed under WSL2.
- Hit a snag: I didn't remember the password for the Linux user account
  (`rahimighaznawi`) inside that distro — needed for every `sudo` command.
- **Fixed it** without reinstalling anything, using a WSL-specific trick: logged in as
  `root` (Windows can always do this, no password needed: `wsl -d Ubuntu-20.04 -u root`),
  then ran `passwd rahimighaznawi` from inside root to set a fresh password.
- New password for this WSL user: `clearledger1` (change it later if I want something
  stronger — this is a local dev machine account, not a production credential).

**Useful commands going forward:**
```bash
wsl -d Ubuntu-20.04          # enter your Ubuntu shell from Windows
wsl -d Ubuntu-20.04 -u root  # enter as root (emergency/admin access, no password needed)
exit                         # leave the WSL shell, back to Windows terminal
```

---

## 3. `apt update` / `apt upgrade`

**What it is:** Ubuntu's package manager. `update` refreshes the *list* of available
package versions from Ubuntu's servers; `upgrade` actually installs newer versions of
packages I already have.

**Why the lab needs it:** A stale package index means `apt install` can fail to find
packages, pull broken/outdated versions, or hit dependency conflicts. Standard first step
before installing anything new on a fresh or long-unused Linux system (this WSL distro had
190 pending updates).

---

## 4. `jq`

**What it is:** A command-line JSON processor — lets me pretty-print, filter, and extract
fields from JSON in the terminal.

**Why the lab needs it:** ClearLedger's APIs return JSON (e.g. login returns
`{"access_token": "..."}`). The lab's example commands pipe `curl` output through `jq` to
read it, e.g. extracting just the `access_token` field to reuse in the next request:
```bash
TOKEN=$(curl ... | jq -r .access_token)
```
Without `jq`, I'd be manually parsing raw JSON text.

---

## 5. `make`

**What it is:** A build-automation tool that runs predefined commands ("targets") from a
`Makefile`. I run `make setup`, `make stage-0`, etc., and it runs whatever script is
defined under that name.

**Why the lab needs it:** The entire lab is orchestrated through `make` — every stage,
health check, and teardown is a `make` target (see `clearledger/Makefile`). It's the single
entry point so I don't need to remember dozens of raw script paths.

---

## 6. `git`

**What it is:** Version control — tracks file changes, lets me clone repos, commit, push,
branch.

**Why the lab needs it:** ClearLedger *is* two Git repos: `clearledger` (app code + CI
pipeline) and `clearledger-infra` (Kubernetes manifests, watched by ArgoCD). GitOps — the
core concept of Stage 2 — means the cluster's desired state lives in Git, and ArgoCD syncs
the cluster to match it. I can't do this lab without Git fundamentals: clone, commit,
push.

*(Already installed on my Windows side via Git Bash; installing it again here inside
WSL2/Ubuntu, since that's now the environment doing the actual work — cloning the repo,
running `make`, etc.)*

---

## 7. `curl`

**What it is:** A command-line tool for making HTTP requests.

**Why the lab needs it:** Used constantly to test the running app directly — registering a
user, logging in, checking balances — by hitting the API endpoints directly, the same way a
frontend or another service would. E.g.:
```bash
curl -s -X POST http://clearledger.local/auth/register -d '{"email":"...","password":"..."}'
```

---

## 8. `python3`

**What it is:** The Python interpreter.

**Why the lab needs it:** Some of the lab's helper scripts (like
`scripts/configure-vm-network.sh`, which I'll run in a later step) use small embedded
Python snippets to safely edit JSON config files (e.g. Docker's `daemon.json`) without
corrupting them via naive text edits.

---

## 9. MicroK8s

**What it is:** A lightweight, single-package Kubernetes distribution from Canonical
(the company behind Ubuntu). This *is* the Kubernetes cluster the whole lab runs on —
everything from Stage 0 onward deploys into this.

**Why the lab needs it:** Kubernetes is the platform the whole app runs on. MicroK8s is
the "batteries included but minimal" way to get a real, spec-compliant Kubernetes cluster
running on a single machine (as opposed to a multi-node production cluster), which is
exactly right for a homelab.

**What I did:**
- Installed via `sudo snap install microk8s --classic --channel=1.29/stable`.
- Hit a snag: `snap install` requires **systemd** running as PID 1 inside WSL2, which
  wasn't enabled by default. Fixed by adding `[boot]\nsystemd=true` to `/etc/wsl.conf`,
  then fully restarting WSL from Windows with `wsl --shutdown` (this restarts *all* WSL
  distros, not just Ubuntu) and reopening the Ubuntu shell.
- Hit a second snag: running the install via `sudo` in the interactive terminal hung
  indefinitely with zero progress for 15+ minutes, even though networking and snapd were
  both healthy (verified by installing a small test snap, `hello-world`, which completed
  in seconds). Running the exact same install directly as `root` (bypassing `sudo`
  entirely) completed normally in about a minute — something specific to that `sudo`
  session was the problem, not the machine or network.
- Added my Linux user to the `microk8s` group (`sudo usermod -aG microk8s $USER`, then
  `newgrp microk8s`) so `kubectl`/`microk8s` commands don't need `sudo` for every call.
- Enabled the addons the lab requires: `dns`, `helm`, `helm3` (enabled automatically on
  install for this MicroK8s version), plus `ingress` and `storage` (enabled manually —
  `ingress` runs the NGINX ingress controller that routes `*.local` hostnames to the
  right service; `storage` provides a default StorageClass so pods can request persistent
  volumes).
- Set up shell aliases in `~/.bashrc` so `kubectl` and `helm` "just work" without typing
  `microk8s` in front:
  ```bash
  alias kubectl='microk8s kubectl'
  alias helm='microk8s helm3'
  ## 01. first confirming if the alias actually exists by running this commands

  "grep alias ~/.bashrc"
  ## 02. confirming if alias active in hte current shell: by running the command:
  "type kubectl"
  "type helm"


  ## 3. actually running the commands to see if the status is ready by running this commands:
  "kubectl get nodes"
  ```
- Verified with `kubectl get nodes` — one node, `laptop-c6ai4rel`, status `Ready`.

---

## 10. The CRLF / line-ending fix

**What happened:** `clearledger`'s shell scripts (e.g. `scripts/configure-vm-network.sh`)
failed immediately with errors like `$'\r': command not found` and
`invalid option name` when run inside WSL2's Bash.

**Why:** The repo was originally cloned using **Windows Git Bash**, whose Git install
defaults to `core.autocrlf=true` — meaning every text file gets its line endings
converted from Unix-style (`LF`, a single `\n`) to Windows-style (`CRLF`, `\r\n`) on
checkout. Bash scripts are parsed line-by-line and choke on that trailing `\r` character —
it looks like part of the command to the shell.

**Fix (applies to the whole repo, not just one file):**
```bash
git config core.autocrlf false   # stop converting line endings on checkout
git config core.eol lf           # always use Unix-style line endings here
git rm --cached -r . -q          # untrack everything...
git reset --hard                 # ...then re-checkout everything fresh, LF this time
```
This only rewrites how files sit on disk to match what's already committed — nothing
about my actual work or Git history changes.

**Lesson for later:** if I ever re-clone this repo (or the `clearledger-infra` repo)
from a Windows terminal, I need to run those same three `git config`/`git reset` lines
again immediately after cloning, before running anything under `scripts/` or `stages/`.

---

## 11. `configure-vm-network.sh --inside-vm`

**What it is:** A script the lab repo ships specifically for hosts like ours — Windows/WSL2
running MicroK8s directly (as opposed to the default Mac + Multipass setup). It pins DNS
resolvers for both the host (`systemd-resolved`) and the Docker daemon.

**Why the lab needs it:** Without a pinned, reliable DNS resolver, pulling container images
from Docker Hub or cloning from GitHub can intermittently fail — especially inside WSL2,
which inherits DNS settings that don't always play well with corporate networks, VPNs, or
flaky resolvers. This script forces both the OS and Docker to use known-good public
resolvers (Cloudflare `1.1.1.1`, Google `8.8.8.8`) and then verifies it actually works by
resolving `github.com`, `registry-1.docker.io`, `files.pythonhosted.org`, and
`archive.ubuntu.com` — both from the host and from *inside* a test container.

**What I did:** Ran `bash scripts/configure-vm-network.sh --inside-vm` from inside the
`clearledger` repo (WSL2 Ubuntu shell). All five verification checks passed.

---

## 12. `/etc/hosts` entries (Windows side)

**What it is:** A plain-text file (`C:\Windows\System32\drivers\etc\hosts`) that lets me
manually map a hostname to an IP address, overriding normal DNS lookup for just my
machine.

**Why the lab needs it:** The app and its dashboards are reached via friendly names —
`clearledger.local`, `argocd.local`, `grafana.local`, `vault.local`, `falco.local` — instead
of raw IPs or `localhost:port`. Kubernetes' ingress controller routes incoming requests to
the right service based on which hostname was requested, so my machine needs to know
those `.local` names should go to my cluster.

**What I did — one deviation from the README worth remembering:** the README's default
instructions point these hostnames at the Multipass VM's IP address. I'm not using
Multipass — MicroK8s runs inside WSL2 instead. I confirmed WSL2's **localhost
forwarding** works (a background test server inside WSL2 was reachable from Windows via
`127.0.0.1` with no extra config), so I originally pointed every hostname at **`127.0.0.1`**
instead of a WSL2-internal IP.

**Why that mattered (in theory):** WSL2's internal IP address changes every time it restarts
(it's DHCP-assigned from an internal virtual switch), which would silently break these
hostnames after every reboot if I'd hardcoded that IP. `127.0.0.1` never changes, so in
theory this survives reboots without any maintenance.

**⚠ SUPERSEDED (2026-08-04):** `127.0.0.1` forwarding turned out to be broken for port 80
specifically on this machine — see the "Known issue: browser can't reach *.local via
127.0.0.1" section further down for the full diagnosis (likely McAfee-related, unconfirmed).
The hosts file currently points all five `.local` names at the WSL2 VM's **current** IP
instead (`172.20.125.104` as of tonight), which means the tradeoff described above is now
reversed — this **does** need re-doing after every WSL/machine restart. Check the "Known
issue" section for the fix command when `.local` stops loading in a browser again.

Requires admin rights to edit (`C:\Windows\System32\drivers\etc\hosts` is a protected
system file), so this step ran from an elevated ("Run as Administrator") PowerShell window.

**Gotcha hit along the way:** the hosts file already had other entries (McAfee-related, likely
added by antivirus software) and the last existing line had no trailing newline. `Add-Content`
appended my new lines directly onto the end of that last line instead of starting a fresh
line, merging `mssplus.mcafee.com` and `127.0.0.1  clearledger.local` into one garbled line —
which would have made `clearledger.local` silently resolve to the wrong IP (`0.0.0.1`, the
McAfee entry's address) instead of `127.0.0.1`. Fixed with a targeted find-and-replace that
split the merged line back into two proper lines. **Lesson:** always double check a hosts file
(or any config file with `Add-Content`) after appending to it — a missing trailing newline is
an easy, silent way to corrupt an existing entry.

---

## Known issue: browser can't reach *.local via 127.0.0.1 (parked, not blocking)

**Symptom:** `curl http://clearledger.local` works fine from inside WSL2, and `make check-0`
/ `health-check.sh` pass end-to-end — but a Windows browser hitting `http://clearledger.local`
gets `ERR_CONNECTION_REFUSED`. Confirmed the issue is specifically WSL2's automatic
"localhost forwarding" (Windows `127.0.0.1` → WSL2) silently not relaying **port 80**
specifically: a throwaway test server on port 8099 forwarded fine, port 80 did not, even
after a full `wsl --shutdown` + restart. Windows Firewall has no rule explaining it, and
there's no port-80 exclusion range reserved by HTTP.SYS.

**Suspected cause, not confirmed:** McAfee (Total Protection, trial expired) is installed
and running several background services. Its actual Firewall Core service (`mfefire`) is
already stopped, so classic "McAfee firewall blocks port 80" isn't quite it — but other
McAfee services (`mfevtp`, `mfemms`, `McAPExe`, `PEFService`) are running and **refuse to
stop even from an elevated/Administrator PowerShell** ("Cannot open service" — McAfee's own
tamper-protection blocking the stop request), so the hypothesis couldn't be cleanly tested.
Root cause is still unconfirmed.

**Workaround in use (until root cause is found or McAfee — expired trial — is uninstalled):**
point the `.local` hostnames at the WSL2 VM's current IP instead of `127.0.0.1`. Get the
current IP with `wsl -d Ubuntu-20.04 -- hostname -I` (first address shown), then in an
**elevated** PowerShell:
```powershell
$hosts = 'C:\Windows\System32\drivers\etc\hosts'
(Get-Content $hosts) -replace '^127\.0\.0\.1(\s+(clearledger|argocd|grafana|vault|falco)\.local)$', '<CURRENT_IP>$1' | Set-Content $hosts -Encoding ASCII
```
**Downside:** this IP is DHCP-assigned and changes on WSL/machine restart, so this has to be
re-run after each restart if I want the browser view. Not needed for `make check-N` health
checks or any terminal/curl work — only matters for actually loading the UI in a browser.

---

## Testing the API from the terminal (login → token → authenticated request)

**Where to run this:** inside the WSL2 Ubuntu shell (`wsl -d Ubuntu-20.04` from Windows, or
just keep typing if my prompt already shows `rahimighaznawi@LAPTOP-C6AI4REL:...$`) — not
Windows PowerShell.

Most ClearLedger API endpoints (creating transactions, checking balance, etc.) require a
JWT token from logging in first. Run these as **two separate steps**, line by line:

**Step 1 — log in and save the token to a variable** (paste this whole block as one piece —
the `\` at line-ends just means "continues on the next line," it's normal multi-line shell
syntax, not something to type literally):
```bash
TOKEN=$(curl -s -X POST http://clearledger.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"LearningDevSecOps1"}' \
  | jq -r .access_token)
```
This prints nothing — that's expected. It's silently saving my login token into `$TOKEN`
for the next command to use.

**Step 2 — use `$TOKEN` in an authenticated request.** Example: check balance —
```bash
curl -s http://clearledger.local/ledger/balance \
  -H "Authorization: Bearer $TOKEN" | jq
```
Example: create a transaction —
```bash
curl -s -X POST http://clearledger.local/ledger/transactions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"direction":"credit","amount":150000}' | jq
```
(`direction` must be `"credit"` or `"debit"` — the field is not called `"type"`, learned
that the hard way.) Any transaction ≥ $10,000 triggers a compliance alert automatically
(via Redis pub/sub to notification-service) — check it with:
```bash
curl -s http://clearledger.local/notifications/alerts | jq
```

**Test account used throughout this lab:** `student@example.com` / `LearningDevSecOps1`
(registered during Stage 0 testing — this is a demo account, not a real credential, fine to
keep reusing it).

**Common mistake to avoid:** don't type the literal `...` when it shows up in an explanation
elsewhere — it's shorthand for "the rest of the command goes here," not something to paste.
Typing `curl ...` literally fails with `curl: (6) Could not resolve host: ...` since curl
tries to look up a website actually named `...`.

---

## Still to come (not installed yet)

| Tool | What it's for |
|---|---|
| **GitHub + Docker Hub accounts** | GitHub hosts the two repos this lab uses (`clearledger` app code, `clearledger-infra` manifests) and runs the CI pipeline. Docker Hub is where built container images get pushed to and pulled from. |
| **pre-commit** | A Python tool that runs checks (secret scanning, YAML linting) automatically before every `git commit`, catching mistakes before they even leave my machine. |

This file will get updated as I finish each of these.
