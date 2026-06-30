#!/usr/bin/env bash
# Copy infra/cosign.pub (gitignored locally) into Kyverno policy YAMLs.
# Run after cosign generate-key-pair in Stage 3, before kubectl apply -f infra/policies/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUB="${ROOT}/infra/cosign.pub"
PLACEHOLDER='PASTE_YOUR_COSIGN_PUBLIC_KEY_HERE'

if [[ ! -f "${PUB}" ]]; then
  echo "✗ ${PUB} not found. Generate keys (Stage 3): cosign generate-key-pair && cp cosign.pub infra/cosign.pub"
  exit 1
fi

KEY_BLOCK="$(cat "${PUB}")"
export KEY_BLOCK PLACEHOLDER ROOT

python3 <<'PY'
import os, pathlib

root = pathlib.Path(os.environ["ROOT"])
key = os.environ["KEY_BLOCK"].strip()
placeholder = os.environ["PLACEHOLDER"]
targets = list((root / "infra/policies").glob("*.yaml"))
targets += list((root / "stages/stage-4-admission-control/infra/policies").glob("*.yaml"))

for path in targets:
    text = path.read_text()
    if placeholder not in text and "BEGIN PUBLIC KEY" in text:
        continue
    if placeholder in text:
        path.write_text(text.replace(placeholder, key + "\n"))
        print(f"✓ {path.relative_to(root)}")
    elif "publicKeys:" in text and key.splitlines()[1] not in text:
        print(f"⚠ {path.relative_to(root)} has publicKeys but does not match infra/cosign.pub — edit manually")
PY

echo "Done. Re-apply on cluster: kubectl apply -f infra/policies/"
