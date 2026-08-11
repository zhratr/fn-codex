#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "${ROOT_DIR}/fpk/app/ui/config" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
entry = config.get(".url", {}).get("fn-codex.Application", {})
assert entry.get("type") == "url"
assert entry.get("protocol") == "http"
assert entry.get("port") == "3010"
assert entry.get("url") == "/"
print("desktop ui config checks passed")
PY
