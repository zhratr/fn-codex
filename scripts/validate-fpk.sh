#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-${ROOT_DIR}/fpk}"
if [[ "${SOURCE}" == "--source" ]]; then SOURCE="${2:?--source requires a directory}"; fi

for required in manifest config/privilege config/resource cmd/main wizard/install ICON.PNG ICON_256.PNG; do
  [[ -e "${SOURCE}/${required}" ]] || { echo "missing ${required}" >&2; exit 1; }
done

python3 - "${SOURCE}/config/privilege" "${SOURCE}/config/resource" "${SOURCE}/app/ui/config" <<'PY'
import json, sys
for filename in sys.argv[1:]:
    with open(filename, encoding="utf-8") as handle:
        json.load(handle)
    print(f"valid json: {filename}")
PY

for script in "${SOURCE}/cmd/"* "${SOURCE}/wizard/"*; do
  [[ -f "${script}" ]] || continue
  bash -n "${script}"
done

grep -q '^appname=fn-codex$' "${SOURCE}/manifest"
grep -q '^platform=\(x86_64\|arm64\)$' "${SOURCE}/manifest"
file "${SOURCE}/ICON.PNG" "${SOURCE}/ICON_256.PNG"
if command -v fnpack >/dev/null 2>&1; then
  echo "fnpack detected: ${fnpack}"
else
  echo "fnpack not installed here; skipping fnOS-native build validation"
fi
echo "FPK source validation passed"
