#!/usr/bin/env bash
set -euo pipefail

PACKAGE="${1:?usage: PLATFORM=x86_64 VERSION=0.1.1 REQUIRE_RUNTIME=0 $0 package.fpk}"
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

tar -tzf "${PACKAGE}" >"${WORK}/outer.list"
for required in ./manifest ./app.tgz ./cmd/main ./config/privilege ./config/resource ./wizard/install ./ICON.PNG ./ICON_256.PNG; do
  grep -qxF "${required}" "${WORK}/outer.list" || { echo "missing outer entry: ${required}" >&2; exit 1; }
done

tar -xOzf "${PACKAGE}" ./manifest >"${WORK}/manifest"
grep -Eq '^appname="fn-codex"$' "${WORK}/manifest"
grep -Eq "^version=\"${VERSION:-[0-9.]+}\"$" "${WORK}/manifest"
grep -Eq "^platform=\"${MANIFEST_PLATFORM}\"$" "${WORK}/manifest"
grep -Eq "^arch=\"${PLATFORM}\"$" "${WORK}/manifest"

tar -xOzf "${PACKAGE}" ./app.tgz >"${WORK}/app.tgz"
tar -tzf "${WORK}/app.tgz" >"${WORK}/app.list"
for required in ./server/server.js ./ui/config ./ui/index.html ./ui/app.js ./ui/styles.css; do
  grep -qxF "${required}" "${WORK}/app.list" || { echo "missing app.tgz entry: ${required}" >&2; exit 1; }
done
if grep -qE '^\./app(/|$)' "${WORK}/app.list"; then
  echo "app.tgz has an invalid nested app/ directory" >&2
  exit 1
fi

if [[ "${REQUIRE_RUNTIME}" == "1" ]]; then
  grep -qxF "./runtime/node" "${WORK}/app.list" || { echo "missing self-contained runtime" >&2; exit 1; }
  RUNTIME_INFO="$(tar -xOzf "${WORK}/app.tgz" ./runtime/node | file -b - 2>/dev/null || true)"
  case "${PLATFORM}" in
    x86_64) grep -Eq 'ELF 64-bit.*(x86-64|Advanced Micro Devices X86-64)' <<<"${RUNTIME_INFO}" || { echo "runtime architecture mismatch: ${RUNTIME_INFO}" >&2; exit 1; } ;;
    arm64) grep -Eq 'ELF 64-bit.*(ARM aarch64|AArch64)' <<<"${RUNTIME_INFO}" || { echo "runtime architecture mismatch: ${RUNTIME_INFO}" >&2; exit 1; } ;;
  esac
else
  echo "runtime check skipped: package-shape validation only"
fi

echo "FPK archive validation passed: ${PACKAGE} (${PLATFORM})"
