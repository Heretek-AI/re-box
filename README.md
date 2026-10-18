# re-box

Reproducible Docker image that preinstalls the native toolchain REA needs so a
container starts ready to reverse-engineer. Companion to
[`opencode-rea`](https://github.com/Heretek-AI/opencode-rea) (the thin
OpenCode plugin); see `docs/IMPLEMENTATION_PROMPT.md` (copy of the
opencode-rea spec) for the full milestone plan.

> Status: **M7 complementary triage**. M8 (smoke/PRs) lands next.

## What's inside (M5)

| Component | Version / source |
| --- | --- |
| Base OS | `ubuntu:24.04` |
| Node.js | 22.x (NodeSource `setup_22.x`) |
| Bun | latest from `https://bun.sh/install` |
| JDK | full `openjdk-21-jdk` (`jdk.compiler` module present, 64-bit) |
| Process tools | `procps` (`ps`), `util-linux` (`/usr/bin/prlimit`) |
| Languages | `python3` + `pip` + `venv` |
| VCS / fetch | `git`, `curl`, `unzip` |
| OpenCode CLI | **pinned** `@opencode/cli@2.0.32` (`npm install -g`) |
| REA CLI | **pinned** `rea-agents@6.5.0` (`npm install -g`, for `doctor`/analysis) |
| Ghidra | **12.1.4** — NSA release `ghidra_12.1.4_PUBLIC_20260921.zip`, sha256-verified, at `/opt/ghidra_12.1.4_PUBLIC` |
| JADX | **jadx-headless-mcp 0.7.1** — sha256-verified JAR at `/opt/jadx/jadx-headless-mcp-0.7.1-all.jar` |
| Rizin | **0.9.1** — static upstream release at `/opt/rizin-0.9.1/bin/rizin` (REA invokes `rizin`, never `r2`); `radare2` (apt) also present for skills |
| Disasm/debug | GNU `objdump` (binutils), `gdb` + `gdbserver`, `pwndbg` (release `2026.09.15` at `/opt/pwndbg`) |
| Firmware | Binwalk **3.1.x** (cargo Rust build at `/opt/binwalk/bin/binwalk`), Unblob **26.6.4** (venv) |
| Android | Apktool **3.0.3** (`/usr/local/bin/apktool`), `adb` (standalone apt `adb` package at `/usr/bin/adb`) |
| Network/signals | `tshark` + `capinfos` **4.x**, `sigrok-cli` **0.7.2** |
| JS/WASM | Wakaru **1.14.0** (binary-sha verified, `/opt/wakaru/wakaru`), WABT **1.0.42** (`/opt/wabt-1.0.42/bin`) |
| Python venv | `/opt/venvs/re-tools`: **pwntools 4.15.0** (+`pyelftools 0.33`, `unicorn 2.1.2`), **mitmproxy 12.2.3**, Unblob 26.6.4 |
| User | non-root `re` |
| Workdir | `/workspace` (mount point) |
| M6 wire-up | `rea setup --client opencode` (mcp.rea + compact env), `@heretek-ai/opencode-rea` plugin, curated RE skills + `reverse-engineer-anything` in `~/.agents/skills`, `operator-helper install opencode-v2`, `watcher.ignore` for targets/captures artefacts |
| M7 fast triage | DIE **3.21** (`diec` on `PATH`, `/usr/local/bin/diec`, Ubuntu 24.04 `.deb`) |
| M7 headless RE | ReVa (pinned commit `a05a6b0`, `7.3.2.dev11`) — Ghidra extension built from source against the baked Ghidra 12.1.4 + `mcp-reva` CLI (`/usr/local/bin/mcp-reva`), registered as `mcp.reva` (`type: local`) in `opencode.json` |
| Entrypoint | `scripts/entrypoint.sh` gates `ps` + `/usr/bin/prlimit`, then `exec opencode` in `/workspace` |
| Compose | `docker-compose.yml`: `./workspace:/workspace`, `./targets:/workspace/targets:ro`, `cap_add SYS_PTRACE`, host provider key |

Ghidra and JADX both run on the full JDK 21 (Gotcha 9). IDA and Hopper are
licensed and never baked in — see "How to mount IDA / Hopper" below.

### Engine-path contract

Every `REA_*` path (spec §4.4) is written once in `config/env.defaults`,
`COPY`ed to `/etc/profile.d/re-box-env.sh` (login shells), and mirrored as
Docker `ENV` lines (non-login shells, `opencode`). Each path is absolute and
must exist: `scripts/healthcheck.mjs` loops over every entry and fails if any
is missing. It runs as the last build step and as the Docker `HEALTHCHECK`.

`REA_GHIDRA_COMPILER_SPEC_ID` and `REA_GHIDRA_LANGUAGE_ID` are intentionally
left unset (setting the former without the latter fails REA validation).
`REA_MCP_INPUT_SCHEMA_PROFILE=compact` is set per spec §4.4a.

## How to run

```sh
# Build (must exit 0)
docker build -t re-box:m6 .

# Run interactive, workspace mounted (compose adds targets:ro + SYS_PTRACE)
mkdir -p workspace targets
ANTHROPIC_API_KEY=... docker compose run --rm re-box

# Or plain docker:
docker run --rm -it -v "$PWD/workspace:/workspace" \
  -v "$PWD/targets:/workspace/targets:ro" \
  --cap-add SYS_PTRACE re-box:m6

# Inside: node --version  # v22.x
#         rea doctor --client opencode --json  # healthy, registration:opencode ok
#         rea analyze /opt/re-box/samples/hello --provider ghidra --json
```

The entrypoint gates on `ps` and `/usr/bin/prlimit` (fail-closed), then
`exec`s `opencode` with `/workspace` as the workdir.

Acceptance is enforced **inside the build** (fail-closed, never by grepping
config): JADX JAR sha256 re-verified; `$GHIDRA_INSTALL_DIR/support/analyzeHeadless`
executable; `rizin/objdump/gdb/adb --version` succeed; `apktool --version`
≥ 3.0.2; Binwalk 3.1.x / Unblob 26.6.x / TShark+capinfos 4.x / sigrok-cli 0.7.2 /
Wakaru 1.14.0 version gates; `healthcheck.mjs` green; scoped
`rea doctor --provider ghidra --provider jadx --json` healthy;
`rea doctor --client opencode --json` shows no missing engine for installed
providers; and `rea analyze` on the bundled tiny ELF returns real Ghidra
output. Evidence in `docs/NOTES.md`.

`docker-compose.yml` mounts `./workspace:/workspace`,
`./targets:/workspace/targets:ro`, adds `cap_add: [SYS_PTRACE]` for gdb/rizin
debug sessions, and takes the model provider key from the host environment
(`ANTHROPIC_API_KEY` / `OPENAI_API_KEY` pass through only when set on the
host — never baked into the image).

## Complementary triage (M7 — ReVa + DIE, opt-in)

Both ship **enabled by default**; a lean image skips either behind a build arg:

```sh
# Full triage image (default)
docker build -t re-box:m7 .

# Lean image (no ReVa, no DIE)
docker build -t re-box:m7-lean \
  --build-arg REBOX_WITH_REVA=0 \
  --build-arg REBOX_WITH_DIE=0 .
```

- **DIE** (`diec --version`): Detect-It-Easy 3.21 console triage, installed
  from the upstream Ubuntu 24.04 `.deb` (MIT licensed). `diec` is on `PATH`
  (`/usr/local/bin/diec`, also `DIEC_COMMAND` in `config/env.defaults`).
- **ReVa** (`mcp-reva --help`): the `reverse-engineering-assistant` Python CLI
  plus the Ghidra extension, both from **one pinned upstream commit**
  (`a05a6b0`, post-v7.3.1) — built from source with the exact Gradle version
  the baked Ghidra 12.1.4 requires and installed into
  `$GHIDRA_INSTALL_DIR/Ghidra/Extensions` (Apache-2.0 licensed). The v7.3.1
  tag is deliberately not used: its CLI imports a symbol the declared
  `mcp>=2.3` floor no longer exports (proven by a failed M7 build), while the
  pinned commit carries the SDK-v2 migration and Ghidra 12.1.4 support. `setup-rea.sh` registers it as `mcp.reva` (`type: local`,
  `command: ["mcp-reva"]`) in `opencode.json` whenever `mcp-reva` is on
  `PATH` (skipped silently in lean images).
- **Headless note**: a full ReVa headless boot (Ghidra init + MCP
  `tools/list` round-trip) is heavy (~90 s boot in-container, GBs of RAM),
  so the build gate proves *load* (extension installed with matching
  version stamp, `mcp-reva --help`, `import reva_cli`, `mcp.reva`
  registered) rather than blocking the build on a live server round-trip.
  The live round-trip is verified post-build and recorded in `docs/NOTES.md`
  + `docs/evidence/m7/confirm-probes.log` (`initialize` →
  `serverInfo ReVa 7.3.2.dev11+ga05a6b0a1` → `tools/list` → 86 tools).
  Start it at runtime with `mcp-reva` (stdio MCP) from any workspace
  directory.

## What setup-rea.sh does (M6 wire-up)

At build time, as the `re` user, `scripts/setup-rea.sh` (fail-closed,
idempotent):

1. `npx -y rea-agents@6.5.0 setup --client opencode --yes` — writes the
   `mcp.rea` block and installs the `reverse-engineer-anything` skill.
2. `opencode plugin add @heretek-ai/opencode-rea` — the thin RE plugin.
3. Copies the curated skill bundle from the image (`/opt/re-box/skills`,
   extracted at build from the pinned `@heretek-ai/opencode-rea@0.1.2`
   tarball: `rea-evidence-report`, `rea-investigation`, `rea-opencode`,
   `rea-reconstruction`) into `~/.agents/skills` — copy-from-image, so no
   network is needed at container start. `reverse-engineer-anything` is
   never overwritten (Gotcha 14).
4. `operator-helper install opencode-v2` — operator-memory (locked Decision 2).
5. Merges `"environment": {"REA_MCP_INPUT_SCHEMA_PROFILE": "compact"}` into
   `mcp.rea` with `jq` (keeps everything `rea setup` wrote) and adds the
   `watcher.ignore` list (`targets/**`, `captures/**`, `ghidra_projects/**`,
   `.rea/**`, `*.gpr`, `*.rep/**`, `*.idb`, `*.i64`, `*.pcap*`, `*.core`,
   `*.dmp`).

## How to mount IDA / Hopper

IDA and Hopper are **licensed — they are never baked into the image**.
Mount them at runtime and point REA at them:

```sh
docker run --rm -it \
  -v "$PWD/workspace:/workspace" \
  -v /path/to/ida:/opt/ida:ro \
  -v /path/to/hopper:/opt/hopper:ro \
  -e REA_IDA_MCP_CONFIG=/workspace/ida-mcp.json \
  -e HOPPER_LAUNCHER_PATH=/opt/hopper/Hopper \
  re-box:m5 bash
```

Set `REA_IDA_MCP_CONFIG` to your IDA MCP bridge config and
`HOPPER_LAUNCHER_PATH` to the mounted Hopper launcher. macOS-only targets
(ipatool, Apple bundle analysis, Hopper GUI flows) stay host-side; the Linux
image covers the scripted/headless path.

## Secrets

Never bake API keys, tokens, or credentials into the image or commit them.
Pass the model provider key at runtime:

```sh
docker run --rm -it -e OPENCODE_API_KEY="$OPENCODE_API_KEY" \
  -v "$PWD/workspace:/workspace" re-box:m5 opencode
```

(prefer your provider's own env name; the image reads nothing at build time).

## Layout

```
Dockerfile            # multi-stage; base + engines + M6 wire-up + acceptance
.dockerignore
docker-compose.yml    # M6: workspace/targets mounts, SYS_PTRACE, host key env
README.md             # this file
docs/IMPLEMENTATION_PROMPT.md  # copy of the opencode-rea spec for contributors
docs/NOTES.md         # build evidence + discovery log
docs/reports/         # per-milestone implementation reports
scripts/              # install-ghidra.sh, install-jadx.sh, healthcheck.mjs,
                      # install-die.sh, install-reva.sh (M7), setup-rea.sh (M6/M7),
                      # entrypoint.sh (M6), smoke.sh (M8)
config/env.defaults   # single source of truth for every REA_* engine path
.github/workflows/build.yml  # build image (smoke lands in M8)
```

## Contributing

Read `docs/IMPLEMENTATION_PROMPT.md` top to bottom before changing anything.
Stage explicit paths only (`git add Dockerfile …`) — never `git add -A` / `.`.
