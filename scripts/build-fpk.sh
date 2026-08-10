#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
PLATFORM="${PLATFORM:-x86_64}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist}"
NODE_VERSION="${NODE_VERSION:-22.14.0}"
SKIP_RUNTIME="${SKIP_RUNTIME:-0}"

case "${PLATFORM}" in
  x86_64) NODE_ARCH="x64"; NODE_ENV_NAME="NODE_BINARY_X86_64" ;;
  arm64) NODE_ARCH="arm64"; NODE_ENV_NAME="NODE_BINARY_ARM64" ;;
  *) echo "Unsupported platform: ${PLATFORM} (expected x86_64 or arm64)" >&2; exit 2 ;;
esac

mkdir -p "${OUT_DIR}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fn-codex-fpk.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/content/app" "${STAGE}/package/cmd" "${STAGE}/package/config" "${STAGE}/package/wizard"

cp -R "${ROOT_DIR}/app/server" "${STAGE}/content/app/server"
cp -R "${ROOT_DIR}/app/ui" "${STAGE}/content/app/ui"
cp "${ROOT_DIR}/fpk/app/ui/config" "${STAGE}/content/app/ui/config"
cp "${ROOT_DIR}/fpk/manifest" "${STAGE}/package/manifest"
sed -i.bak "s/^version=.*/version=${VERSION}/; s/^platform=.*/platform=${PLATFORM}/" "${STAGE}/package/manifest"
rm -f "${STAGE}/package/manifest.bak"
cp -R "${ROOT_DIR}/fpk/cmd/." "${STAGE}/package/cmd/"
cp -R "${ROOT_DIR}/fpk/config/." "${STAGE}/package/config/"
cp -R "${ROOT_DIR}/fpk/wizard/." "${STAGE}/package/wizard/"
cp "${ROOT_DIR}/fpk/ICON.PNG" "${STAGE}/package/ICON.PNG"
cp "${ROOT_DIR}/fpk/ICON_256.PNG" "${STAGE}/package/ICON_256.PNG"
cp "${ROOT_DIR}/LICENSE" "${STAGE}/package/LICENSE"
chmod +x "${STAGE}/package/cmd/"* "${STAGE}/package/wizard/"*

if [[ "${SKIP_RUNTIME}" == "1" ]]; then
  echo "warning: SKIP_RUNTIME=1; this is a package-shape preview, not a self-contained FPK" >&2
else
  mkdir -p "${STAGE}/content/runtime"
  RUNTIME_SOURCE="${!NODE_ENV_NAME:-}"
  if [[ -n "${RUNTIME_SOURCE}" ]]; then
    cp "${RUNTIME_SOURCE}" "${STAGE}/content/runtime/node"
  else
    HOST_ARCH="$(uname -m)"
    if [[ "${PLATFORM}" == "x86_64" && "${HOST_ARCH}" == "x86_64" ]] || [[ "${PLATFORM}" == "arm64" && ( "${HOST_ARCH}" == "arm64" || "${HOST_ARCH}" == "aarch64" ) ]]; then
      NODE_LOCAL="$(command -v node || true)"
      if [[ -n "${NODE_LOCAL}" ]]; then cp "${NODE_LOCAL}" "${STAGE}/content/runtime/node"; fi
    fi
    if [[ ! -x "${STAGE}/content/runtime/node" ]]; then
      CACHE_DIR="${RUNTIME_CACHE_DIR:-${TMPDIR:-/tmp}/fn-codex-node-runtime}"
      ARCHIVE="${CACHE_DIR}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
      mkdir -p "${CACHE_DIR}"
      if [[ ! -f "${ARCHIVE}" ]]; then
        command -v curl >/dev/null || { echo "curl is required to fetch the ${PLATFORM} Node runtime" >&2; exit 1; }
        curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -o "${ARCHIVE}"
      fi
      EXTRACT_DIR="${STAGE}/node-runtime"
      mkdir -p "${EXTRACT_DIR}"
      tar -xJf "${ARCHIVE}" -C "${EXTRACT_DIR}"
      cp "${EXTRACT_DIR}/node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin/node" "${STAGE}/content/runtime/node"
    fi
  fi
  chmod +x "${STAGE}/content/runtime/node"
  RUNTIME_INFO="$(file -b "${STAGE}/content/runtime/node" 2>/dev/null || true)"
  case "${PLATFORM}" in
    x86_64) grep -Eq 'ELF 64-bit.*(x86-64|Advanced Micro Devices X86-64)' <<<"${RUNTIME_INFO}" || { echo "runtime is not a Linux x86_64 Node binary: ${RUNTIME_INFO}" >&2; exit 1; } ;;
    arm64) grep -Eq 'ELF 64-bit.*(ARM aarch64|AArch64)' <<<"${RUNTIME_INFO}" || { echo "runtime is not a Linux ARM64 Node binary: ${RUNTIME_INFO}" >&2; exit 1; } ;;
  esac
fi

tar -czf "${STAGE}/package/app.tgz" -C "${STAGE}/content" app runtime 2>/dev/null || tar -czf "${STAGE}/package/app.tgz" -C "${STAGE}/content" app
OUTPUT="${OUT_DIR}/fn-codex-${VERSION}-${PLATFORM}.fpk"
tar -czf "${OUTPUT}" -C "${STAGE}/package" .
echo "built ${OUTPUT}"
