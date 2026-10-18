# M6 implementation report — re-box wire-up

- Stage ID: M6 (IMPLEMENTATION_PROMPT §6 M6 + §4.4a compact schema + §4.3 rea setup + §5 re-box layout, Gotchas 3, 12)
- Branch: `claude/project-thread-gnv9zf` @ `924edd2` (clean; no reset performed)
- Image: `re-box:m6` `sha256:989bd4a7fac849a492030246479b632eb49ad9d6644d2aac2e2f1376eefffa33` (10.6 GB), `docker build -t re-box:m6 .` → exit 0 first attempt (log `/tmp/opencode/m6-build.log`)

## Summary of deliverables

Single commit `feat(m6): re-box wire-up rea setup compact watcher`:

- `scripts/setup-rea.sh` (was placeholder) — real wire-up, runs as `re` at build, fail-closed/idempotent: `npx -y rea-agents@6.5.0 setup --client opencode --yes`; `opencode plugin add @heretek-ai/opencode-rea`; copy curated skills from `$REBOX_SKILLS_DIR` (default `/opt/re-box/skills`) into `~/.agents/skills`, never overwriting `reverse-engineer-anything` (Gotcha 14); `operator-helper install opencode-v2`; `jq` merge of `REA_MCP_INPUT_SCHEMA_PROFILE=compact` into `mcp.rea.environment` (preserves setup's block) + 11-entry `watcher.ignore`; node verify gate + skill presence checks.
- `scripts/entrypoint.sh` (new) — gates `ps` on PATH + executable `/usr/bin/prlimit` (`--version` runs), requires `/workspace`, `exec opencode "$@"`.
- `docker-compose.yml` (new) — `./workspace:/workspace`, `./targets:/workspace/targets:ro`, `cap_add: [SYS_PTRACE]`, `stdin_open/tty`, provider keys pass through from host env only when set, never baked (Gotcha 12).
- `Dockerfile` — M6 layers after M5 (cache-preserving): `jq`; `ARG REBOX_REA_PLUGIN_VERSION=0.1.2` + `npm pack` published plugin tarball, `skills/` → `/opt/re-box/skills` (copy-from-image, documented); `npm i -g @aerovato/operator-helper@1.8.0`; `COPY --chown=re:re` both scripts + `sh -n` gate; `RUN setup-rea.sh` as `re`; M6 acceptance RUN (opencode.json gate: mcp.rea + compact + both plugin entries + all 11 watcher.ignore; skill files; `entrypoint.sh --help` smoke); `ENTRYPOINT [entrypoint.sh]` + `CMD []`.
- `README.md` — M6 status, compose usage, "What setup-rea.sh does", layout.
- `docs/NOTES.md` — M6 section: host probes, MCP/docker evidence, SHA/version record, fixture limitation.

## Files created / modified

`scripts/setup-rea.sh`, `scripts/entrypoint.sh` (new), `docker-compose.yml` (new), `Dockerfile`, `README.md`, `docs/NOTES.md`, `docs/reports/m6-implementation.md` (this file). Explicit `git add` only; no push.

## Test results

- `sh -n` on both scripts: pass.
- Host run of the identical `setup-rea.sh` (isolated `HOME=/tmp/m6run2`, `REBOX_SKILLS_DIR` = published 0.1.2 skills): exit 0. `opencode.json` carries `mcp.rea` (+`environment.compact`), both plugin entries, 11-entry `watcher.ignore`. Skills: `reverse-engineer-anything` + 4 bundled. `rea doctor --client opencode --json`: `healthy: True`, `registration:opencode ok:true`.
- Direct MCP stdio `tools/list`: 207 tools (default and compact; compact advertises fewer bytes: 2483476 vs 3089015).
- `opencode run --standalone --format json --auto "run rea_readiness and report"` (local `ollama/qwen2.5-coder:latest`): exit 0, plugins load clean (no `LoadError`), server log `mcp connected server=rea tools=207`; model names `rea_readiness` but emits it as text, never `tool_use` — small-model fixture limitation, recorded in NOTES (2 attempts, distinct prompts).
- `docker build -t re-box:m6 .` → exit 0 first attempt; in-build M6 gate (`M6 opencode.json gate passed`, `M6 wire-up acceptance checks passed`) plus green M4/M5 re-runs. Runtime: in-image `opencode.json` carries mcp.rea (+forwarded engine env + compact), both plugins, 11 watcher.ignore; skills on disk; in-image `rea doctor --client opencode` `healthy: True` (ghidra 12.1.4, jadx); `docker compose config` validates.
- 3x-fail budget: untouched (0 same-error repeats).

## Self-audit notes

- No delegation, no stubs, no swallowed errors (`set -eu` everywhere, fail-closed gates), no secrets baked or committed (provider key is host-env pass-through; isolated-HOME probes used no credentials).
- Gotcha 3 respected: no `ctx.mcp.transform` anywhere; MCP config is `rea setup` + `jq` merge only. Gotcha 12 respected: keys never in image/repo.
- Skill licensing: bundled packs are the plugin's own MIT skills (same package whose LICENSE ships in the tarball); `reverse-engineer-anything` comes from `rea setup`, never vendored (Gotcha 14).
- Dockerfile header comment updated to M6 (comments only; landed after the in-flight build read the file — functionally identical).
