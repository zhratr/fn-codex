#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.3}"
PLATFORM="${PLATFORM:-x86_64}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist}"
NODE_VERSION="${NODE_VERSION:-22.14.0}"
FNPACK_VERSION="${FNPACK_VERSION:-1.2.3}"
SKIP_RUNTIME="${SKIP_RUNTIME:-0}"

case "${PLATFORM}" in
  x86_64) NODE_ARCH="x64"; NODE_ENV_NAME="NODE_BINARY_X86_64"; MANIFEST_PLATFORM="x86" ;;
  arm64) NODE_ARCH="arm64"; NODE_ENV_NAME="NODE_BINARY_ARM64"; MANIFEST_PLATFORM="arm" ;;
  *) echo "Unsupported platform: ${PLATFORM} (expected x86_64 or arm64)" >&2; exit 2 ;;
esac

mkdir -p "${OUT_DIR}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fn-codex-fpk.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/project"

# Build the actual fnpack project. fnpack validates wizard JSON, desktop
# entry naming, manifest compatibility, and writes the app.tgz checksum.
cp -R "${ROOT_DIR}/fpk/." "${STAGE}/project/"
sed -i.bak "s/^version=.*/version=\"${VERSION}\"/; s/^platform=.*/platform=\"${MANIFEST_PLATFORM}\"/; s/^arch=.*/arch=\"${PLATFORM}\"/" "${STAGE}/project/manifest"
rm -f "${STAGE}/project/manifest.bak"

if [[ "${SKIP_RUNTIME}" == "1" ]]; then
  echo "warning: SKIP_RUNTIME=1; this is a package-shape preview, not a self-contained FPK" >&2
else
  mkdir -p "${STAGE}/project/app/runtime"
  RUNTIME_SOURCE="${!NODE_ENV_NAME:-}"
  if [[ -n "${RUNTIME_SOURCE}" ]]; then
    cp "${RUNTIME_SOURCE}" "${STAGE}/project/app/runtime/node"
  else
    HOST_ARCH="$(uname -m)"
    if [[ "${PLATFORM}" == "x86_64" && "${HOST_ARCH}" == "x86_64" ]] || [[ "${PLATFORM}" == "arm64" && ( "${HOST_ARCH}" == "arm64" || "${HOST_ARCH}" == "aarch64" ) ]]; then
      NODE_LOCAL="$(command -v node || true)"
      if [[ -n "${NODE_LOCAL}" ]]; then cp "${NODE_LOCAL}" "${STAGE}/project/app/runtime/node"; fi
    fi
    if [[ ! -x "${STAGE}/project/app/runtime/node" ]]; then
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
      cp "${EXTRACT_DIR}/node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin/node" "${STAGE}/project/app/runtime/node"
    fi
  fi
  chmod +x "${STAGE}/project/app/runtime/node"
  RUNTIME_INFO="$(file -b "${STAGE}/project/app/runtime/node" 2>/dev/null || true)"
  case "${PLATFORM}" in
    x86_64) grep -Eq 'ELF 64-bit.*(x86-64|Advanced Micro Devices X86-64)' <<<"${RUNTIME_INFO}" || { echo "runtime is not a Linux x86_64 Node binary: ${RUNTIME_INFO}" >&2; exit 1; } ;;
    arm64) grep -Eq 'ELF 64-bit.*(ARM aarch64|AArch64)' <<<"${RUNTIME_INFO}" || { echo "runtime is not a Linux ARM64 Node binary: ${RUNTIME_INFO}" >&2; exit 1; } ;;
  esac
fi

FNPACK_BIN="${FNPACK_BIN:-}"
if [[ -z "${FNPACK_BIN}" ]]; then FNPACK_BIN="$(command -v fnpack || true)"; fi
if [[ -z "${FNPACK_BIN}" ]]; then
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64) FNPACK_ASSET="darwin-arm64" ;;
    Darwin:x86_64) FNPACK_ASSET="darwin-amd64" ;;
    Linux:x86_64) FNPACK_ASSET="linux-amd64" ;;
    Linux:aarch64|Linux:arm64) FNPACK_ASSET="linux-arm64" ;;
    *) echo "Cannot select fnpack ${FNPACK_VERSION} for $(uname -s)/$(uname -m)" >&2; exit 1 ;;
  esac
  FNPACK_CACHE_DIR="${FNPACK_CACHE_DIR:-${TMPDIR:-/tmp}/fn-codex-fnpack}"
  FNPACK_BIN="${FNPACK_CACHE_DIR}/fnpack-${FNPACK_VERSION}-${FNPACK_ASSET}"
  mkdir -p "${FNPACK_CACHE_DIR}"
  if [[ ! -x "${FNPACK_BIN}" ]]; then
    command -v curl >/dev/null || { echo "curl is required to fetch fnpack ${FNPACK_VERSION}" >&2; exit 1; }
    curl -fsSL "https://static2.fnnas.com/fnpack/fnpack-${FNPACK_VERSION}-${FNPACK_ASSET}" -o "${FNPACK_BIN}"
    chmod +x "${FNPACK_BIN}"
  fi
fi

(cd "${STAGE}" && "${FNPACK_BIN}" build --directory "${STAGE}/project")
OUTPUT="${OUT_DIR}/fn-codex-${VERSION}-${PLATFORM}.fpk"
mv "${STAGE}/fn-codex.fpk" "${OUTPUT}"
echo "built ${OUTPUT} with fnpack ${FNPACK_VERSION}"
