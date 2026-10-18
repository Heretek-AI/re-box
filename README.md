# re-box

Reproducible Docker image that preinstalls the native toolchain REA needs so a
container starts ready to reverse-engineer. Companion to
[`opencode-rea`](https://github.com/Heretek-AI/opencode-rea) (the thin
OpenCode plugin); see `docs/IMPLEMENTATION_PROMPT.md` (copy of the
opencode-rea spec) for the full milestone plan.

> Status: **M5 engine contract**. M6 (wire-up), M7 (ReVa/DIE), M8 (smoke/PRs)
> land in later milestones.

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
docker build -t re-box:m5 .

# Run interactive, workspace mounted
docker run --rm -it -v "$PWD/workspace:/workspace" re-box:m5 bash

# Inside: node --version  # v22.x
#         rea doctor --client opencode --json  # ghidra + jadx available
#         rea analyze /opt/re-box/samples/hello --provider ghidra --json
```

Acceptance is enforced **inside the build** (fail-closed, never by grepping
config): JADX JAR sha256 re-verified; `$GHIDRA_INSTALL_DIR/support/analyzeHeadless`
executable; `rizin/objdump/gdb/adb --version` succeed; `apktool --version`
≥ 3.0.2; Binwalk 3.1.x / Unblob 26.6.x / TShark+capinfos 4.x / sigrok-cli 0.7.2 /
Wakaru 1.14.0 version gates; `healthcheck.mjs` green; scoped
`rea doctor --provider ghidra --provider jadx --json` healthy;
`rea doctor --client opencode --json` shows no missing engine for installed
providers; and `rea analyze` on the bundled tiny ELF returns real Ghidra
output. Evidence in `docs/NOTES.md`.

`docker-compose.yml` (M6) will mount `./workspace:/workspace`,
`./targets:/workspace/targets:ro`, add `cap_add: [SYS_PTRACE]` for gdb/rizin
debug sessions, and take the model provider key from the host environment.

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
Dockerfile            # multi-stage; base + engines + acceptance checks
.dockerignore
README.md             # this file
docs/IMPLEMENTATION_PROMPT.md  # copy of the opencode-rea spec for contributors
docs/NOTES.md         # build evidence + discovery log
scripts/              # install-ghidra.sh, install-jadx.sh, healthcheck.mjs, setup-rea.sh (M6), smoke.sh (M8)
config/env.defaults   # single source of truth for every REA_* engine path
.github/workflows/build.yml  # build image (smoke lands in M8)
```

## Contributing

Read `docs/IMPLEMENTATION_PROMPT.md` top to bottom before changing anything.
Stage explicit paths only (`git add Dockerfile …`) — never `git add -A` / `.`.
