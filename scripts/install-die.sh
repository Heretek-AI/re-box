#!/bin/sh
# re-box M7: install DIE (horsicq/DIE-engine) so `diec` is on PATH for fast triage.
#
# Pinned: DIE 3.21 `die_3.21_Ubuntu_24.04_amd64.deb` (matches the image's
# Ubuntu 24.04 base, so hard dependencies resolve via APT). MIT licensed.
# Fail-closed: any missing prerequisite, failed download, failed APT install,
# or missing `diec` aborts the build. No secrets involved.
#
# Env overrides (all optional):
#   DIE_VERSION  release tag/file version (default 3.21)
set -eu

log() { printf 'install-die: %s\n' "$*"; }
fail() { printf 'install-die: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail 'curl not on PATH'
command -v apt-get >/dev/null 2>&1 || fail 'apt-get not on PATH'

DIE_VERSION="${DIE_VERSION:-3.21}"
DIE_DEB="die_${DIE_VERSION}_Ubuntu_24.04_amd64.deb"
DIE_URL="https://github.com/horsicq/DIE-engine/releases/download/${DIE_VERSION}/${DIE_DEB}"

log "downloading ${DIE_URL}"
rm -f "/tmp/${DIE_DEB}"
curl -fL --retry 3 --retry-delay 5 -o "/tmp/${DIE_DEB}" "$DIE_URL"
test -s "/tmp/${DIE_DEB}" || fail "downloaded deb is empty: /tmp/${DIE_DEB}"

log "installing ${DIE_DEB} (resolves Qt deps via APT)"
apt-get update
apt-get install -y "/tmp/${DIE_DEB}"
rm -f "/tmp/${DIE_DEB}"

command -v diec >/dev/null 2>&1 || fail 'diec not on PATH after install'
diec --version || fail 'diec --version failed'
# Stable contract path for config/env.defaults (DIEC_COMMAND): the .deb lays
# diec down under /usr/bin, but pin the canonical location explicitly so the
# healthcheck never depends on .deb internals.
ln -sf "$(command -v diec)" /usr/local/bin/diec
test -x /usr/local/bin/diec || fail '/usr/local/bin/diec not executable'

log "DIE ${DIE_VERSION} installed (diec at $(command -v diec))"
