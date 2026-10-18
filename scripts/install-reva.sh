#!/bin/sh
# re-box M7: install ReVa (cyberkaida/reverse-engineering-assistant) headless.
#
# Two halves from ONE pinned source commit:
#   1. Python CLI (`mcp-reva`) via `pip install` of the pinned checkout into
#      /opt/venvs/re-tools, symlinked as /usr/local/bin/mcp-reva.
#   2. Ghidra extension built from the SAME checkout with the exact Gradle
#      version the baked Ghidra requires
#      (`$GHIDRA_INSTALL_DIR/Ghidra/application.properties`
#      `application.gradle.version`) and installed via the upstream `gradle
#      install` task into `$GHIDRA_INSTALL_DIR/Ghidra/Extensions`.
#
# Pin: commit a05a6b0a18649efd6d74ec8447bdadf8d468c365 (2026-10-13, post-v7.3.1).
# The v7.3.1 tag is DELIBERATELY NOT used:
#   - its Python CLI imports `streamablehttp_client` from
#     `mcp.client.streamable_http`, a symbol the declared `mcp>=2.3,<3` floor
#     (2.3.0) no longer exports — `mcp-reva --help` dies with ImportError
#     (proven by M7 build attempt 1);
#   - the pinned commit carries the MCP SDK v2 migration, the transport
#     restart fix, and upstream Ghidra 12.1.4 CI support, matching the baked
#     Ghidra 12.1.4 exactly.
# Apache-2.0 licensed.
#
# Fail-closed: any missing prerequisite, ref mismatch, build failure, or
# missing post-install artifact aborts the build. Gradle + sources are removed
# afterwards; only the installed extension and the venv entrypoint remain.
#
# Env overrides (all optional):
#   REVA_REF    upstream commit (default: the pinned SHA below)
#   REVA_VENV   target venv (default /opt/venvs/re-tools)
set -eu

log() { printf 'install-reva: %s\n' "$*"; }
fail() { printf 'install-reva: %s\n' "$*" >&2; exit 1; }

: "${GHIDRA_INSTALL_DIR:?GHIDRA_INSTALL_DIR must be set (baked Ghidra)}"
[ -d "$GHIDRA_INSTALL_DIR" ] || fail "GHIDRA_INSTALL_DIR missing: $GHIDRA_INSTALL_DIR"
command -v java >/dev/null 2>&1 || fail 'java not on PATH (full JDK 21 required)'
command -v git >/dev/null 2>&1 || fail 'git not on PATH'
command -v curl >/dev/null 2>&1 || fail 'curl not on PATH'
command -v unzip >/dev/null 2>&1 || fail 'unzip not on PATH'

REVA_REF="${REVA_REF:-a05a6b0a18649efd6d74ec8447bdadf8d468c365}"
VENV="${REVA_VENV:-/opt/venvs/re-tools}"
[ -x "$VENV/bin/pip" ] || fail "venv pip missing: $VENV/bin/pip"
# NOTE: the checkout directory name MUST be `reverse-engineering-assistant`:
# the Ghidra `install` task names the extension archive (and hence the
# directory unzipped into Ghidra/Extensions) after the project directory.
# Cloning into /tmp/reva-src installs to Extensions/reva-src and the
# verification below fails (M7 build attempt 3 evidence).
SRC_DIR=/tmp/reverse-engineering-assistant

# ---- 1. Pinned source checkout (full clone: setuptools_scm needs tags) -------
rm -rf "$SRC_DIR"
git clone https://github.com/cyberkaida/reverse-engineering-assistant "$SRC_DIR"
git -C "$SRC_DIR" checkout "$REVA_REF"
CHECKED_OUT="$(git -C "$SRC_DIR" rev-parse HEAD)"
[ "$CHECKED_OUT" = "$REVA_REF" ] || fail "ref mismatch: wanted $REVA_REF, got $CHECKED_OUT"
log "checked out ${CHECKED_OUT} ($(git -C "$SRC_DIR" log -1 --format='%ad %s' --date=short))"

# ---- 2. Python CLI from the same checkout ------------------------------------
log "pip-installing ReVa CLI into ${VENV}"
"$VENV/bin/pip" install "$SRC_DIR"
"$VENV/bin/pip" show reverse-engineering-assistant | head -n 3
"$VENV/bin/python" -c 'import reva_cli; print("install-reva: reva_cli import ok")'
ln -sf "$VENV/bin/mcp-reva" /usr/local/bin/mcp-reva
mcp-reva --help >/dev/null || fail 'mcp-reva --help failed'

# ---- 3. Gradle (exact version the baked Ghidra requires) ----------------------
APP_PROPS="$GHIDRA_INSTALL_DIR/Ghidra/application.properties"
[ -f "$APP_PROPS" ] || fail "application.properties missing: $APP_PROPS"
# Ghidra 12.1.4 stamps a supported Gradle *range* (application.gradle.min/max),
# not a single version — use the minimum (8.5 runs on JDK 21).
GRADLE_VERSION="$(grep -E '^application\.gradle\.min=' "$APP_PROPS" | cut -d= -f2 | tr -d '[:space:]')"
[ -n "$GRADLE_VERSION" ] || fail 'application.gradle.min not found in application.properties'
GHIDRA_VERSION="$(grep -E '^application\.version=' "$APP_PROPS" | cut -d= -f2 | tr -d '[:space:]')"
log "baked Ghidra ${GHIDRA_VERSION}; required Gradle ${GRADLE_VERSION}"
curl -fL --retry 3 --retry-delay 5 \
  -o "/tmp/gradle-${GRADLE_VERSION}-bin.zip" \
  "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
curl -fL --retry 3 --retry-delay 5 \
  -o "/tmp/gradle-${GRADLE_VERSION}-bin.zip.sha256" \
  "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip.sha256"
EXPECTED_HASH="$(tr -d '[:space:]' < "/tmp/gradle-${GRADLE_VERSION}-bin.zip.sha256" | cut -c1-64)"
ACTUAL_HASH="$(sha256sum "/tmp/gradle-${GRADLE_VERSION}-bin.zip" | awk '{print $1}')"
[ -n "$EXPECTED_HASH" ] || fail 'empty gradle sha256 file'
[ "$EXPECTED_HASH" = "$ACTUAL_HASH" ] || fail "gradle zip hash mismatch (expected $EXPECTED_HASH, got $ACTUAL_HASH)"
rm -rf /opt/gradle && mkdir -p /opt/gradle
unzip -q "/tmp/gradle-${GRADLE_VERSION}-bin.zip" -d /opt/gradle
GRADLE_BIN="$(echo /opt/gradle/gradle-*/bin/gradle)"
[ -x "$GRADLE_BIN" ] || fail 'gradle binary missing after unzip'
"$GRADLE_BIN" --version | head -n 8

# ---- 4. Build + install the extension against the baked Ghidra ----------------
export GHIDRA_INSTALL_DIR
export GRADLE_USER_HOME=/tmp/reva-gradle-home
"$GRADLE_BIN" -p "$SRC_DIR" install --console=plain --no-daemon

# ---- 5. Verify the install ----------------------------------------------------
EXT_DIR="$GHIDRA_INSTALL_DIR/Ghidra/Extensions/reverse-engineering-assistant"
[ -f "$EXT_DIR/extension.properties" ] || fail "extension.properties missing in $EXT_DIR"
[ -f "$EXT_DIR/lib/reverse-engineering-assistant.jar" ] || fail 'extension jar missing'
EXT_VERSION="$(grep -E '^version=' "$EXT_DIR/extension.properties" | cut -d= -f2 | tr -d '[:space:]')"
log "extension version stamp: ${EXT_VERSION} (baked Ghidra: ${GHIDRA_VERSION})"
if [ "$EXT_VERSION" != "$GHIDRA_VERSION" ]; then
  log "WARNING: extension stamp ${EXT_VERSION} != Ghidra ${GHIDRA_VERSION} (runtime probe decides)"
fi

# ---- 6. Cleanup (extension + venv entrypoint remain) --------------------------
rm -rf "/tmp/gradle-${GRADLE_VERSION}-bin.zip" "/tmp/gradle-${GRADLE_VERSION}-bin.zip.sha256" \
  "$SRC_DIR" "$GRADLE_USER_HOME" /opt/gradle
log "ReVa ${REVA_REF} installed (extension + mcp-reva)"
