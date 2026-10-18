#!/usr/bin/env bash
# re-box M5: install the pinned jadx-headless-mcp JAR with checksum verification.
#
# Downloads jadx-headless-mcp-0.7.1-all.jar from the upstream release, verifies
# sha256 6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75
# (rea/src/android/JadxRelease.ts), and installs it to
# /opt/jadx/jadx-headless-mcp-0.7.1-all.jar.
#
# Fail-closed: a hash mismatch aborts with a non-zero exit (Docker build
# fails) — never proceed with an unverified binary (Gotcha 8).
#
# Env overrides (all optional):
#   JADX_VERSION   default 0.7.1
#   JADX_SHA256    default 6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75
#   REA_JADX_MCP_JAR default /opt/jadx/jadx-headless-mcp-0.7.1-all.jar
set -euo pipefail

JADX_VERSION="${JADX_VERSION:-0.7.1}"
JADX_SHA256="${JADX_SHA256:-6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75}"
JADX_JAR="jadx-headless-mcp-${JADX_VERSION}-all.jar"
JADX_URL="https://github.com/1013503897/jadx-headless-mcp/releases/download/v${JADX_VERSION}/${JADX_JAR}"
REA_JADX_MCP_JAR="${REA_JADX_MCP_JAR:-/opt/jadx/${JADX_JAR}}"

echo "install-jadx: jadx-headless-mcp ${JADX_VERSION} -> ${REA_JADX_MCP_JAR}" >&2
echo "install-jadx: ${JADX_URL}" >&2

if [ -f "${REA_JADX_MCP_JAR}" ]; then
  echo "install-jadx: verifying existing ${REA_JADX_MCP_JAR}" >&2
  echo "${JADX_SHA256}  ${REA_JADX_MCP_JAR}" | sha256sum -c -
  echo "install-jadx: OK (already installed)" >&2
  exit 0
fi

command -v curl >/dev/null || { echo "install-jadx: curl not found" >&2; exit 1; }

mkdir -p "$(dirname "${REA_JADX_MCP_JAR}")"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

curl -fL --retry 3 --retry-delay 5 -o "${WORK}/${JADX_JAR}" "${JADX_URL}"

echo "install-jadx: verifying sha256 (build fails on mismatch)" >&2
echo "${JADX_SHA256}  ${WORK}/${JADX_JAR}" | sha256sum -c -

mv "${WORK}/${JADX_JAR}" "${REA_JADX_MCP_JAR}"
chmod 644 "${REA_JADX_MCP_JAR}"

echo "${JADX_SHA256}  ${REA_JADX_MCP_JAR}" | sha256sum -c -
echo "install-jadx: OK ${REA_JADX_MCP_JAR}" >&2
