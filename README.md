# re-box

Reproducible Docker image that preinstalls the native toolchain REA needs so a
container starts ready to reverse-engineer. Companion to
[`opencode-rea`](https://github.com/Heretek-AI/opencode-rea) (the thin
OpenCode plugin); see `docs/IMPLEMENTATION_PROMPT.md` (copy of the
opencode-rea spec) for the full milestone plan.

> Status: **M4 base image**. M5+ (engines), M6 (wire-up), M7 (ReVa/DIE) land in
> later milestones.

## What's inside (M4)

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
| User | non-root `re` |
| Workdir | `/workspace` (mount point) |

In-build acceptance checks (the `RUN … && …` tail of the `Dockerfile`) assert:
`node --version` starts with `v22.`; `bun --version` prints a version;
`java -version` is 21+; `opencode --version` prints `opencode v2.0.32`;
`ps --version` and `/usr/bin/prlimit --version` work;
`java --list-modules | grep -q jdk.compiler`. Evidence in `docs/NOTES.md`.

## How to run

```sh
# Build (must exit 0)
docker build -t re-box:m4 .

# Run interactive, workspace mounted
docker run --rm -it -v "$PWD/workspace:/workspace" re-box:m4 bash

# Inside: node --version  # v22.x
#         bun --version
#         java -version   # 21+
#         opencode --version  # opencode v2.0.32
```

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
  re-box:m4 bash
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
  -v "$PWD/workspace:/workspace" re-box:m4 opencode
```

(prefer your provider's own env name; the image reads nothing at build time).

## Layout

```
Dockerfile            # multi-stage; base + toolchain + acceptance checks
.dockerignore
README.md             # this file
docs/IMPLEMENTATION_PROMPT.md  # copy of the opencode-rea spec for contributors
docs/NOTES.md         # build evidence + discovery log
scripts/              # install-ghidra.sh, install-jadx.sh, setup-rea.sh, smoke.sh (M5+)
config/               # env.defaults (REA_* paths, M5+)
.github/workflows/build.yml  # build image, run smoke.sh (minimal now, full in M8)
```

## Contributing

Read `docs/IMPLEMENTATION_PROMPT.md` top to bottom before changing anything.
Stage explicit paths only (`git add Dockerfile …`) — never `git add -A` / `.`.
