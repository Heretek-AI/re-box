#!/bin/sh
# re-box M6: wire REA + plugin + skills + memory into the container.
#
# Runs as the `re` user, at build time (Dockerfile `RUN`, HOME=/home/re).
# Idempotent: every step can be re-run (rea setup merges, plugin add is
# upsert, skill copies replace, jq merge is convergent).
#
# Fail-closed: `set -eu`; any missing prerequisite or failing step aborts
# the build. Never bakes secrets: the model provider key is runtime env only.
#
# What it does (IMPLEMENTATION_PROMPT Sec 6 M6):
#   1. `npx -y rea-agents@6.5.0 setup --client opencode --yes`
#      (writes the `mcp.rea` block, installs `reverse-engineer-anything`).
#   2. `opencode plugin add @heretek-ai/opencode-rea` (thin RE plugin).
#   3. Copies the curated skill bundle from the image
#      (`$REBOX_SKILLS_DIR`, default `/opt/re-box/skills`) into
#      `~/.agents/skills` — copy-from-image (documented choice; the bundle
#      is the published @heretik-ai/opencode-rea skill packs, pinned in the
#      Dockerfile). Never overwrites `reverse-engineer-anything` (Gotcha 14).
#   4. `operator-helper install opencode-v2` (operator-memory, Decision 2).
#   5. Merges `"environment": {"REA_MCP_INPUT_SCHEMA_PROFILE": "compact"}`
#      into `mcp.rea` (jq; keeps everything rea setup wrote) and adds the
#      `watcher.ignore` list for targets/captures/decompiler artefacts.
set -eu

log() { printf 'setup-rea: %s\n' "$*"; }
fail() { printf 'setup-rea: %s\n' "$*" >&2; exit 1; }

command -v npx >/dev/null 2>&1 || fail 'npx not found on PATH'
command -v opencode >/dev/null 2>&1 || fail 'opencode not found on PATH'
command -v jq >/dev/null 2>&1 || fail 'jq not found on PATH'
command -v node >/dev/null 2>&1 || fail 'node not found on PATH'

# 1. REA registration + reverse-engineer-anything skill (pinned 6.5.0).
log 'rea setup --client opencode --yes'
npx -y rea-agents@6.5.0 setup --client opencode --yes

# 2. Thin RE plugin (Decision: keep opencode-rea thin).
log 'opencode plugin add @heretek-ai/opencode-rea'
opencode plugin add @heretek-ai/opencode-rea

# 3. Curated skill bundle: copy from the image.
SKILLS_SRC="${REBOX_SKILLS_DIR:-/opt/re-box/skills}"
[ -d "$SKILLS_SRC" ] || fail "skills bundle dir missing: $SKILLS_SRC"
mkdir -p "$HOME/.agents/skills"
copied=0
for d in "$SKILLS_SRC"/*; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if [ "$name" = 'reverse-engineer-anything' ]; then
    log 'skip bundled reverse-engineer-anything (owned by rea setup, Gotcha 14)'
    continue
  fi
  [ -f "$d/SKILL.md" ] || fail "bundled skill $name has no SKILL.md"
  rm -rf "$HOME/.agents/skills/$name"
  cp -r "$d" "$HOME/.agents/skills/$name"
  test -f "$HOME/.agents/skills/$name/SKILL.md" || fail "copy of $name failed"
  log "bundled skill: $name"
  copied=$((copied + 1))
done
[ "$copied" -gt 0 ] || fail "no skills copied from $SKILLS_SRC"

# 4. Operator memory for OpenCode V2 (Decision 2, locked).
command -v operator-helper >/dev/null 2>&1 || fail 'operator-helper not found on PATH'
log 'operator-helper install opencode-v2'
operator-helper install opencode-v2

# 5. compact schema profile (Sec 4.4a) + watcher.ignore (jq merge).
CONFIG="$HOME/.config/opencode/opencode.json"
[ -f "$CONFIG" ] || fail "opencode config missing: $CONFIG (rea setup did not write it?)"
tmp="$(mktemp)"
jq '
  .mcp.rea.environment = (
    (.mcp.rea.environment // {}) + {"REA_MCP_INPUT_SCHEMA_PROFILE": "compact"}
  )
  | .watcher = (.watcher // {})
  | .watcher.ignore = (
      ((.watcher.ignore // []) + [
        "targets/**",
        "captures/**",
        "ghidra_projects/**",
        ".rea/**",
        "*.gpr",
        "*.rep/**",
        "*.idb",
        "*.i64",
        "*.pcap*",
        "*.core",
        "*.dmp"
      ]) | unique
    )
' "$CONFIG" > "$tmp"
mv "$tmp" "$CONFIG"
log "merged compact profile + watcher.ignore into $CONFIG"

# 6. Verify (fail closed).
CONFIG="$CONFIG" node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.env.CONFIG, "utf8"));
if (!c.mcp || !c.mcp.rea) throw new Error("mcp.rea block missing");
if (c.mcp.rea.environment?.REA_MCP_INPUT_SCHEMA_PROFILE !== "compact")
  throw new Error("REA_MCP_INPUT_SCHEMA_PROFILE=compact missing on mcp.rea");
if (!(c.plugins ?? []).some((p) => String(p).includes("opencode-rea")))
  throw new Error("@heretek-ai/opencode-rea plugin entry missing");
const want = ["targets/**","captures/**","ghidra_projects/**",".rea/**","*.gpr","*.rep/**","*.idb","*.i64","*.pcap*","*.core","*.dmp"];
for (const g of want)
  if (!(c.watcher?.ignore ?? []).includes(g)) throw new Error("watcher.ignore missing " + g);
console.log("setup-rea: config gate passed");
'
test -f "$HOME/.agents/skills/reverse-engineer-anything/SKILL.md" \
  || fail 'reverse-engineer-anything skill missing after wire-up'
log 'wire-up complete'
