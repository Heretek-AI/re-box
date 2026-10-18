#!/usr/bin/env bash
# re-box M5: install Ghidra 12.1.4 (NSA release) with checksum verification.
#
# Downloads ghidra_12.1.4_PUBLIC_20260921.zip, verifies its SHA-256 against the
# release metadata, extracts to /opt/ghidra_12.1.4_PUBLIC, and verifies that
# support/analyzeHeadless exists and is executable.
#
# Fail-closed: any download, checksum, extraction, or layout mismatch aborts
# with a non-zero exit (Docker build fails). Never proceeds with an
# unverified binary.
#
# Env overrides (all optional):
#   GHIDRA_VERSION      default 12.1.4
#   GHIDRA_BUILD_DATE   default 20260921 (release asset date stamp)
#   GHIDRA_SHA256       default ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db
#   GHIDRA_INSTALL_DIR  default /opt/ghidra_12.1.4_PUBLIC
set -euo pipefail

GHIDRA_VERSION="${GHIDRA_VERSION:-12.1.4}"
GHIDRA_BUILD_DATE="${GHIDRA_BUILD_DATE:-20260921}"
GHIDRA_SHA256="${GHIDRA_SHA256:-ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db}"
GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/opt/ghidra_${GHIDRA_VERSION}_PUBLIC}"
GHIDRA_ZIP="ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_BUILD_DATE}.zip"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/${GHIDRA_ZIP}"

echo "install-ghidra: Ghidra ${GHIDRA_VERSION} -> ${GHIDRA_INSTALL_DIR}" >&2
echo "install-ghidra: ${GHIDRA_URL}" >&2

if [ -x "${GHIDRA_INSTALL_DIR}/support/analyzeHeadless" ]; then
  echo "install-ghidra: already installed at ${GHIDRA_INSTALL_DIR}, skipping download" >&2
  exit 0
fi

command -v curl >/dev/null || { echo "install-ghidra: curl not found" >&2; exit 1; }
command -v unzip >/dev/null || { echo "install-ghidra: unzip not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "install-ghidra: downloading ${GHIDRA_ZIP} ($(du -h /dev/null >/dev/null 2>&1; echo '~570MB'))" >&2
curl -fL --retry 3 --retry-delay 5 -o "${WORK}/${GHIDRA_ZIP}" "${GHIDRA_URL}"

echo "install-ghidra: verifying sha256" >&2
echo "${GHIDRA_SHA256}  ${WORK}/${GHIDRA_ZIP}" | sha256sum -c -

echo "install-ghidra: extracting to /opt" >&2
unzip -q -o "${WORK}/${GHIDRA_ZIP}" -d /opt

if [ ! -x "${GHIDRA_INSTALL_DIR}/support/analyzeHeadless" ]; then
  echo "install-ghidra: FAIL: ${GHIDRA_INSTALL_DIR}/support/analyzeHeadless missing or not executable after extract" >&2
  ls -la /opt >&2 || true
  exit 1
fi

echo "install-ghidra: OK ${GHIDRA_INSTALL_DIR}/support/analyzeHeadless" >&2
"${GHIDRA_INSTALL_DIR}/support/analyzeHeadless" 2>&1 | head -3 || true
