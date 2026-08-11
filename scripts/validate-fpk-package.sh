#!/usr/bin/env bash
set -euo pipefail

PACKAGE="${1:?usage: PLATFORM=x86_64 VERSION=0.1.7 REQUIRE_RUNTIME=0 $0 package.fpk}"
PLATFORM="${PLATFORM:-x86_64}"
VERSION="${VERSION:-}"
REQUIRE_RUNTIME="${REQUIRE_RUNTIME:-0}"

case "${PLATFORM}" in
  x86_64) MANIFEST_PLATFORM="x86" ;;
  arm64) MANIFEST_PLATFORM="arm" ;;
  *) echo "unsupported platform: ${PLATFORM}" >&2; exit 2 ;;
esac

[[ -f "${PACKAGE}" ]] || { echo "package not found: ${PACKAGE}" >&2; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/fn-codex-validate.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

normalize_tar_list() { sed 's#^\./##; s#/$##' ; }

tar_entry() {
  local archive="$1"
  local wanted="$2"
  tar -tzf "${archive}" | awk -v wanted="${wanted}" '
    {
      entry = $0
      normalized = entry
      sub(/^\.\//, "", normalized)
      sub(/\/$/, "", normalized)
      if (!found && normalized == wanted) {
        matched_entry = entry
        found = 1
      }
    }
    END { if (found) print matched_entry }
  '
}

extract_tar_entry() {
  local archive="$1"
  local wanted="$2"
  local entry
  entry="$(tar_entry "${archive}" "${wanted}")"
  [[ -n "${entry}" ]] || { echo "missing tar entry: ${wanted}" >&2; exit 1; }
  tar -xOzf "${archive}" "${entry}"
}

tar -tzf "${PACKAGE}" | normalize_tar_list >"${WORK}/outer.list"
for required in manifest app.tgz cmd/main cmd/install_init config/privilege config/resource wizard/install ICON.PNG ICON_256.PNG; do
  grep -qxF "${required}" "${WORK}/outer.list" || { echo "missing outer entry: ${required}" >&2; exit 1; }
done

extract_tar_entry "${PACKAGE}" manifest >"${WORK}/manifest"
grep -Eq '^appname[[:space:]]*=[[:space:]]*"?fn-codex"?[[:space:]]*$' "${WORK}/manifest"
grep -Eq "^version[[:space:]]*=[[:space:]]*\"?${VERSION:-[0-9.]+}\"?[[:space:]]*$" "${WORK}/manifest"
grep -Eq "^platform[[:space:]]*=[[:space:]]*\"?${MANIFEST_PLATFORM}\"?[[:space:]]*$" "${WORK}/manifest"
grep -Eq "^arch[[:space:]]*=[[:space:]]*\"?${PLATFORM}\"?[[:space:]]*$" "${WORK}/manifest"
grep -Eq '^os_min_version[[:space:]]*=[[:space:]]*"?1\.2\.0"?[[:space:]]*$' "${WORK}/manifest"
extract_tar_entry "${PACKAGE}" cmd/install_init >"${WORK}/install_init"
[[ "$(tr -d '\r' < "${WORK}/install_init")" == $'#!/bin/sh\nexit 0' ]] || { echo "install_init must be an environment-independent no-op" >&2; exit 1; }

extract_tar_entry "${PACKAGE}" app.tgz >"${WORK}/app.tgz"
tar -tzf "${WORK}/app.tgz" | normalize_tar_list >"${WORK}/app.list"
for required in server/server.js ui/config ui/index.html ui/app.js ui/styles.css; do
  grep -qxF "${required}" "${WORK}/app.list" || { echo "missing app.tgz entry: ${required}" >&2; exit 1; }
done
if grep -qE '^app(/|$)' "${WORK}/app.list"; then
  echo "app.tgz has an invalid nested app/ directory" >&2
  exit 1
fi

CHECKSUM="$(sed -n 's/^checksum[[:space:]]*=[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$/\1/p' "${WORK}/manifest")"
APP_MD5="$(md5 -q "${WORK}/app.tgz" 2>/dev/null || md5sum "${WORK}/app.tgz" | awk '{print $1}')"
[[ -n "${CHECKSUM}" ]] || { echo "manifest is missing fnpack checksum" >&2; exit 1; }
[[ "${CHECKSUM}" == "${APP_MD5}" ]] || { echo "app.tgz checksum mismatch: manifest=${CHECKSUM} actual=${APP_MD5}" >&2; exit 1; }

if [[ "${REQUIRE_RUNTIME}" == "1" ]]; then
  grep -qxF "runtime/node" "${WORK}/app.list" || { echo "missing self-contained runtime" >&2; exit 1; }
  RUNTIME_FILE="${WORK}/runtime-node"
  extract_tar_entry "${WORK}/app.tgz" runtime/node >"${RUNTIME_FILE}"
  RUNTIME_INFO="$(file -b "${RUNTIME_FILE}" 2>/dev/null || true)"
  case "${PLATFORM}" in
    x86_64) grep -Eq 'ELF 64-bit.*(x86-64|Advanced Micro Devices X86-64)' <<<"${RUNTIME_INFO}" || { echo "runtime architecture mismatch: ${RUNTIME_INFO}" >&2; exit 1; } ;;
    arm64) grep -Eq 'ELF 64-bit.*(ARM aarch64|AArch64)' <<<"${RUNTIME_INFO}" || { echo "runtime architecture mismatch: ${RUNTIME_INFO}" >&2; exit 1; } ;;
  esac
else
  echo "runtime check skipped: package-shape validation only"
fi

echo "FPK archive validation passed: ${PACKAGE} (${PLATFORM})"
