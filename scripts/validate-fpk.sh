#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-${ROOT_DIR}/fpk}"
if [[ "${SOURCE}" == "--source" ]]; then SOURCE="${2:?--source requires a directory}"; fi

for required in manifest config/privilege config/resource app/server/server.js app/ui/config app/ui/index.html app/ui/app.js app/ui/styles.css app/ui/images/icon_64.png app/ui/images/icon_256.png cmd/main cmd/install_init ICON.PNG ICON_256.PNG; do
  [[ -e "${SOURCE}/${required}" ]] || { echo "missing ${required}" >&2; exit 1; }
done

python3 - "${SOURCE}/config/privilege" "${SOURCE}/config/resource" "${SOURCE}/app/ui/config" <<'PY'
import json, sys
for filename in sys.argv[1:]:
    with open(filename, encoding="utf-8") as handle:
        json.load(handle)
    print(f"valid json: {filename}")
with open(sys.argv[3], encoding="utf-8") as handle:
    config = json.load(handle)
entry = config.get(".url", {}).get("fn-codex.Application", {})
if entry.get("port") != "3010":
    raise SystemExit("fn-codex desktop entry must declare port 3010")
PY

for script in "${SOURCE}/cmd/"*; do
  [[ -f "${script}" ]] || continue
  bash -n "${script}"
done

[[ ! -e "${SOURCE}/wizard" ]] || { echo "wizard directory must not be present" >&2; exit 1; }

EXPECTED_RESOURCE=$'{\n    "data-share": {\n        "shares": [\n            {\n                "name": "fn-codex",\n                "permission": {\n                    "rw": [\n                        "fn-codex"\n                    ]\n                }\n            },\n            {\n                "name": "fn-codex/data",\n                "permission": {\n                    "rw": [\n                        "fn-codex"\n                    ]\n                }\n            }\n        ]\n    }\n}\n'
cmp -s <(printf '%s' "${EXPECTED_RESOURCE}") "${SOURCE}/config/resource" || { echo "config/resource must match the NAS-validated data-share definition" >&2; exit 1; }

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
grep -Fq '/proc/${pid}/cmdline' "${SOURCE}/cmd/main"
grep -Fq 'rm -f "${PID_FILE}"' "${SOURCE}/cmd/main"
grep -Fq 'ACTION="${1:-start}"' "${SOURCE}/cmd/main"
grep -Fq 'fn-codex lifecycle:' "${SOURCE}/cmd/main"
grep -Fq 'SCRIPT_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd -P)"' "${SOURCE}/cmd/main"
grep -Fq '/usr/local/apps/@appcenter/${APP_NAME}' "${SOURCE}/cmd/main"
grep -Fq 'APPDEST="${TRIM_APPDEST:-/var/apps/${APP_NAME}}"' "${SOURCE}/cmd/main"
grep -Fq 'PKGHOME="${TRIM_PKGHOME:-${TRIM_APPHOME:-/usr/local/apps/@apphome/${APP_NAME}}}"' "${SOURCE}/cmd/main"
grep -Fq 'PKGVAR="${TRIM_PKGVAR:-${TRIM_APPDATA:-/usr/local/apps/@appdata/${APP_NAME}}}"' "${SOURCE}/cmd/main"
grep -Fq 'LOG_FILE="${PKGVAR}/${APP_NAME}.log"' "${SOURCE}/cmd/main"
grep -Fq 'if ! : >>"${LOG_FILE}" 2>/dev/null; then' "${SOURCE}/cmd/main"
grep -Fq 'LOG_FILE="/dev/null"' "${SOURCE}/cmd/main"
grep -Fq '>>"${LOG_FILE}" 2>/dev/null || true' "${SOURCE}/cmd/main"
grep -Fq 'echo "running ($(cat "${PID_FILE}"))"' "${SOURCE}/cmd/main"
grep -Fq 'echo "stopped"' "${SOURCE}/cmd/main"
grep -Fq '      exit 0' "${SOURCE}/cmd/main"
grep -Fq '      exit 3' "${SOURCE}/cmd/main"
file "${SOURCE}/ICON.PNG" "${SOURCE}/ICON_256.PNG"
if command -v fnpack >/dev/null 2>&1; then
  echo "fnpack detected: $(command -v fnpack)"
else
  echo "fnpack not installed here; skipping fnOS-native build validation"
fi
echo "FPK source validation passed"
