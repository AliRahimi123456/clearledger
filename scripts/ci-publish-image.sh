#!/usr/bin/env bash
# Tag, push, and Cosign-sign a built image. Optional SLSA provenance attestation.
# Usage: ci-publish-image.sh <local-tag> <registry-image> [provenance-name]
set -euo pipefail

LOCAL_TAG="${1:?local tag required}"
REGISTRY_IMAGE="${2:?registry image required}"
PROVENANCE_NAME="${3:-}"

docker tag "${LOCAL_TAG}" "${REGISTRY_IMAGE}"
docker push "${REGISTRY_IMAGE}"

if [[ -z "${COSIGN_KEY:-}" ]]; then
  echo "⚠ COSIGN_KEY not set — skip sign/attest for ${REGISTRY_IMAGE}"
  exit 0
fi

export PATH="${HOME}/.local/bin:${PATH}"
echo "${COSIGN_KEY}" > /tmp/cosign.key

cosign sign --key /tmp/cosign.key --tlog-upload=false "${REGISTRY_IMAGE}" \
  || echo "⚠ cosign sign skipped"

if [[ -n "${PROVENANCE_NAME}" && -n "${GITHUB_SHA:-}" ]]; then
  export PROVENANCE_SHA="${GITHUB_SHA}"
  export PROVENANCE_REPO="${GITHUB_REPOSITORY:?}"
  export PROVENANCE_REF="${GITHUB_REF:?}"
  export PROVENANCE_SVC="${PROVENANCE_NAME}"
  python3 << 'PYEOF'
import json, os
from datetime import datetime, timezone
e = os.environ
sha_digest = {"sha1": e["PROVENANCE_SHA"]}
subject = {"name": e["PROVENANCE_SVC"], "digest": sha_digest}
config_source = {
    "uri": "git+https://github.com/" + e["PROVENANCE_REPO"] + "@" + e["PROVENANCE_REF"],
    "digest": {"sha1": e["PROVENANCE_SHA"]},
    "entryPoint": ".github/workflows/ci.yaml"
}
provenance = {
    "_type": "https://in-toto.io/Statement/v0.1",
    "predicateType": "https://slsa.dev/provenance/v0.2",
    "subject": [subject],
    "predicate": {
        "builder": {"id": "https://github.com/" + e["PROVENANCE_REPO"] + "/actions"},
        "buildType": "https://github.com/actions/runner@v2",
        "invocation": {"configSource": config_source},
        "metadata": {
            "buildStartedOn": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "reproducible": False
        }
    }
}
json.dump(provenance, open("/tmp/provenance.json", "w"), indent=2)
PYEOF
  cosign attest --key /tmp/cosign.key --predicate /tmp/provenance.json \
    --type slsaprovenance --tlog-upload=false "${REGISTRY_IMAGE}" \
    || echo "⚠ cosign attest skipped"
fi

rm -f /tmp/cosign.key /tmp/provenance.json
