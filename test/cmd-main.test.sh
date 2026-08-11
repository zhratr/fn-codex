#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d /proc ]]; then
  echo "cmd/main stale-PID test skipped: /proc is unavailable"
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fn-codex-main-test.XXXXXX")"
APPDEST="${WORK_DIR}/app"
VAR_DIR="${WORK_DIR}/var"
PID_FILE="${VAR_DIR}/fn-codex.pid"
STALE_PID=""

cleanup() {
  if [[ -s "${PID_FILE}" ]]; then kill "$(cat "${PID_FILE}")" 2>/dev/null || true; fi
  [[ -n "${STALE_PID}" ]] && kill "${STALE_PID}" 2>/dev/null || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${APPDEST}/runtime" "${APPDEST}/server" "${VAR_DIR}"
printf '%s\n' '#!/bin/sh' 'while :; do sleep 60; done' >"${APPDEST}/runtime/node"
chmod +x "${APPDEST}/runtime/node"
touch "${APPDEST}/server/server.js"

sleep 300 &
STALE_PID="$!"
printf '%s\n' "${STALE_PID}" >"${PID_FILE}"

TRIM_APPDEST="${APPDEST}" TRIM_PKGVAR="${VAR_DIR}" "${ROOT_DIR}/fpk/cmd/main"
CURRENT_PID="$(cat "${PID_FILE}")"
[[ "${CURRENT_PID}" != "${STALE_PID}" ]] || { echo "stale PID was accepted" >&2; exit 1; }
kill -0 "${CURRENT_PID}"
grep -Fq 'start requested:' "${VAR_DIR}/fn-codex.log"
grep -Fq "start launched pid=${CURRENT_PID}" "${VAR_DIR}/fn-codex.log"
TRIM_APPDEST="${APPDEST}" TRIM_PKGVAR="${VAR_DIR}" "${ROOT_DIR}/fpk/cmd/main" status | grep -Eq '^running \([0-9]+\)$'
TRIM_APPDEST="${APPDEST}" TRIM_PKGVAR="${VAR_DIR}" "${ROOT_DIR}/fpk/cmd/main" stop
[[ ! -e "${PID_FILE}" ]]
echo "cmd/main stale-PID checks passed"
