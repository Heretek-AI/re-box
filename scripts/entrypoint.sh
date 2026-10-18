#!/bin/sh
# re-box entrypoint (M6): gate on REA's process prerequisites, then run opencode.
#
# REA's workers need a procps-compatible `ps` (owned-process checks) and
# util-linux `prlimit` at /usr/bin/prlimit (CapabilityInventory fail-closed
# without it); without them the container would boot into a silently degraded
# state, so fail here instead. Then exec opencode with /workspace as workdir.
set -eu

command -v ps >/dev/null 2>&1 || {
  echo 'entrypoint: ps not found (procps required)' >&2
  exit 1
}
[ -x /usr/bin/prlimit ] || {
  echo 'entrypoint: /usr/bin/prlimit not executable (util-linux required)' >&2
  exit 1
}
/usr/bin/prlimit --version >/dev/null 2>&1 || {
  echo 'entrypoint: /usr/bin/prlimit is broken' >&2
  exit 1
}
[ -d /workspace ] || {
  echo 'entrypoint: /workspace missing (mount ./workspace:/workspace)' >&2
  exit 1
}
cd /workspace
exec opencode "$@"
