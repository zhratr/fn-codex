#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-${ROOT_DIR}/fpk}"
if [[ "${SOURCE}" == "--source" ]]; then SOURCE="${2:?--source requires a directory}"; fi

for required in manifest config/privilege config/resource app/server/server.js app/ui/config app/ui/index.html app/ui/app.js app/ui/styles.css app/ui/images/icon_64.png app/ui/images/icon_256.png cmd/main cmd/install_init wizard/install ICON.PNG ICON_256.PNG; do
  [[ -e "${SOURCE}/${required}" ]] || { echo "missing ${required}" >&2; exit 1; }
done

python3 - "${SOURCE}/config/privilege" "${SOURCE}/config/resource" "${SOURCE}/app/ui/config" <<'PY'
import json, sys
for filename in sys.argv[1:]:
    with open(filename, encoding="utf-8") as handle:
        json.load(handle)
    print(f"valid json: {filename}")
PY

for script in "${SOURCE}/cmd/"*; do
  [[ -f "${script}" ]] || continue
  bash -n "${script}"
done

python3 - "${SOURCE}/wizard/install" "${SOURCE}/wizard/upgrade" "${SOURCE}/wizard/uninstall" "${SOURCE}/wizard/config" <<'PY'
import json, sys
for filename in sys.argv[1:]:
    with open(filename, encoding="utf-8") as handle:
        json.load(handle)
    print(f"valid json: {filename}")
PY

for field in appname version display_name desc maintainer source platform desktop_uidir desktop_applaunchname; do
  grep -Eq "^${field}=\"[^\"]+\"$" "${SOURCE}/manifest" || { echo "manifest field ${field} must be quoted" >&2; exit 1; }
done
grep -Eq '^appname="fn-codex"$' "${SOURCE}/manifest"
grep -Eq '^platform="(x86|arm|all)"$' "${SOURCE}/manifest"
grep -Eq '^arch="(x86_64|arm64)"$' "${SOURCE}/manifest"
grep -Eq '^os_min_version="1\.2\.0"$' "${SOURCE}/manifest"
[[ "$(tr -d '\r' < "${SOURCE}/cmd/install_init")" == $'#!/bin/sh\nexit 0' ]] || { echo "install_init must be an environment-independent no-op" >&2; exit 1; }
grep -Fq 'export FN_CODEX_BIND="${FN_CODEX_BIND:-0.0.0.0}"' "${SOURCE}/cmd/main"
grep -Fq 'const BIND = process.env.FN_CODEX_BIND || "0.0.0.0";' "${SOURCE}/app/server/server.js"
file "${SOURCE}/ICON.PNG" "${SOURCE}/ICON_256.PNG"
if command -v fnpack >/dev/null 2>&1; then
  echo "fnpack detected: $(command -v fnpack)"
else
  echo "fnpack not installed here; skipping fnOS-native build validation"
fi
echo "FPK source validation passed"
