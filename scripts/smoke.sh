#!/bin/sh
# re-box smoke (M8): build the image and run one end-to-end investigation.
#
# Steps:
#   1. `docker build -t "$IMAGE" .` (in-image M4/M5/M6/M7 acceptance RUNs
#      fail the build on any mismatch — Gotcha 19: every binary check runs
#      INSIDE the image, never by grepping config).
#   2. Run the env healthcheck inside the container
#      (`node /opt/re-box/scripts/healthcheck.mjs`).
#   3. Point REA at the small bundled sample target
#      (`/opt/re-box/samples/hello`, built from `samples/hello.c` in the
#      Dockerfile M5 layer) via `rea analyze --provider ghidra --json`,
#      assert the report names the `main` symbol, contains no
#      engine-missing markers, and record one finding (evidence id +
#      subject sha256) on stdout.
#
# Fail-closed: `set -eu`, every gate aborts non-zero with a reason on
# stderr. No secrets: `rea analyze` is fully local, no model provider key
# is needed or read. The container entrypoint (`entrypoint.sh`, which
# execs `opencode`) is overridden per-run via `--entrypoint` so the smoke
# drives `rea` directly.
#
# Env overrides: IMAGE (default re-box:final), SAMPLE (default
# /opt/re-box/samples/hello), SKIP_BUILD=1 to reuse an existing image.
set -eu

IMAGE="${IMAGE:-re-box:final}"
SAMPLE="${SAMPLE:-/opt/re-box/samples/hello}"
SKIP_BUILD="${SKIP_BUILD:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() {
  printf 'smoke: %s\n' "$*" >&2
}

fail() {
  printf 'smoke: FAILED: %s\n' "$*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "docker not found on PATH"
command -v node >/dev/null 2>&1 || fail "node not found on PATH (needed to verify the report JSON)"

if [ "$SKIP_BUILD" = "1" ]; then
  log "SKIP_BUILD=1 — reusing existing image $IMAGE"
else
  log "building image $IMAGE from $ROOT"
  docker build -t "$IMAGE" "$ROOT" >&2 || fail "docker build -t $IMAGE failed"
  log "build ok: $IMAGE"
fi

log "gate 1/3: env healthcheck inside $IMAGE"
docker run --rm --entrypoint node "$IMAGE" /opt/re-box/scripts/healthcheck.mjs >&2 \
  || fail "container healthcheck failed"

log "gate 2/3: rea analyze $SAMPLE --provider ghidra --json"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT INT TERM
docker run --rm --entrypoint rea "$IMAGE" analyze "$SAMPLE" --provider ghidra --json >"$OUT" 2>"$OUT.stderr" \
  || { cat "$OUT.stderr" >&2; fail "rea analyze exited non-zero (see stderr above)"; }
test -s "$OUT" || fail "rea analyze produced empty output"

log "gate 3/3: verify report names main, has no engine-missing markers, record one finding"
node -e '
const fs = require("fs");
const raw = fs.readFileSync(process.argv[1], "utf8");
if (!/main/.test(raw)) { console.error("smoke: report has no main symbol"); process.exit(1); }
for (const marker of ["missing_analysis_engine", "provider_missing", "engine-missing", "not_configured"]) {
  if (raw.includes(marker)) { console.error(`smoke: engine-missing marker present: ${marker}`); process.exit(1); }
}
let finding = null;
try {
  const report = JSON.parse(raw);
  const r = report.result ?? report;
  finding = {
    evidence_id: r.evidence_id ?? r.evidenceId ?? null,
    subject: r.subject ?? null,
  };
} catch (e) {
  console.error(`smoke: report is not valid JSON: ${e.message}`);
  process.exit(1);
}
console.log(JSON.stringify(finding, null, 2));
' "$OUT" || fail "report verification failed"

log "SMOKE OK: opened $SAMPLE with ghidra and recorded one finding (above)"
