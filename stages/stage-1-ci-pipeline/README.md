# Stage 1 — CI Pipeline (GitHub Actions + Self-Hosted Runner)

**Goal:** A `git push` builds images, pushes to Docker Hub, and updates tags in `clearledger-infra` — you still deploy manually.

## Am I ready?

Run before starting:

```bash
make check-0
echo "$DOCKER_USERNAME"    # must not be empty or "your-username"
curl -s -o /dev/null -w "%{http_code}" http://clearledger.local/auth/health
```

- [ ] Docker Hub: four `clearledger-*` repositories
- [ ] GitHub account; repos + PAT ready
- [ ] ~2–4 hours for runner install + first green pipeline

**Done when:** `make check-1` passes **and** you confirmed the five items in LAB-GUIDE §1.6 (infra secrets on GitHub, CI updated tags, cluster unchanged, runner idle).

## Full walkthrough

→ **[docs/LAB-GUIDE.md § Stage 1](../../docs/LAB-GUIDE.md#stage-1--ci-pipeline-github-actions--self-hosted-runner)** — infra repo, self-hosted runner in the VM, GitHub secrets, first pipeline run, §1.6 checkpoint.

## Hands-on checkpoint

- `clearledger-infra` on GitHub with `secretKeyRef` deployments + `secret.yaml` files
- CI updated `kustomization.yaml` image tags; cluster **still on Stage 0 tag** (deployment gap — intentional)
- Workflow green on GitHub; runner **Idle**
- `make check-1` green

## What you can now claim

> **CI removes your laptop from the build process** — every push produces signed, scanned artifacts tied to a commit, while Git (not kubectl) holds the desired image tag.

---

## Reference

| Repo | Holds |
|---|---|
| `clearledger` | App code, Dockerfiles, `.github/workflows/` |
| `clearledger-infra` | Kubernetes manifests only — CI updates image tags here |

Manifest source for Stage 1.3: `infra/manifests/` (replace `YOUR_DOCKERHUB_USERNAME` before first push).

**CI network DNS:** if builds fail on `server misbehaving` or `Could not resolve host`, run `scripts/configure-vm-network.sh` — macOS: from repo root (Multipass); Linux/WSL: `--inside-vm` on the MicroK8s host. See [troubleshooting.md § CI build fails: DNS](../../docs/troubleshooting.md#ci-build-fails-dns-server-misbehaving-or-could-not-resolve-host).

**Trivy scan failure:** if **Scan images** fails, read the CVE table (not the version notice at the bottom) — [LAB-GUIDE §3.5](../../docs/LAB-GUIDE.md#35--when-a-scan-fails-on-a-cve-you-didnt-inject).

---

## → Next: [Stage 2 — GitOps](../stage-2-gitops/README.md)
