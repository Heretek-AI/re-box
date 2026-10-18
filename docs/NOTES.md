# re-box — discovery log

## M4 — base image

Date: 2026-10-18 (UTC). Branch: `claude/project-thread-gnv9zf`
(from `origin/main @ 44cfc76`).
Spec: `docs/IMPLEMENTATION_PROMPT.md` §6 M4 + §4.4 (JDK, ps, prlimit),
§4.5 (opencode 2.0.32), §4.6 Decision 4, §5 re-box layout,
§7 Gotchas 4, 9, 10, 12 + §8.

### What was built

Multi-stage `Dockerfile` (`ubuntu:24.04`):

- Stage 1 `system`: APT toolchain — `ca-certificates curl gnupg git unzip`
  + `procps` (ps) + `util-linux` (prlimit) + `python3 python3-pip python3-venv`
  + full `openjdk-21-jdk`.
- Stage 2 `final` (FROM system): Node 22 via NodeSource `setup_22.x`,
  Bun via official `https://bun.sh/install` promoted to `/usr/local/bin/bun`,
  OpenCode CLI pinned `npm install -g @opencode/cli@2.0.32` (re-box-only pin;
  opencode-rea stays on 2.0.26 per Gotcha 4), non-root `re` user,
  `/workspace` mount point (`WORKDIR`, owned by `re`), then in-build
  acceptance `RUN` (fail-closed: any mismatch fails the build).

Layout per §5 (minimal for M4, full content in later milestones):
`Dockerfile`, `.dockerignore`, `README.md` (inside / run / IDA-Hopper mount),
`docs/IMPLEMENTATION_PROMPT.md` (verbatim copy of
`/home/john/Projects/RE/opencode-rea/docs/IMPLEMENTATION_PROMPT.md`),
`docs/NOTES.md` (this file), `scripts/` placeholders
(`install-ghidra.sh`, `install-jadx.sh`, `setup-rea.sh`, `smoke.sh` —
each exits 1 with an "M5/M6/M8" notice), `config/env.defaults` placeholder
(M5), `.github/workflows/build.yml` skeleton (build image; smoke in M8).

No API keys/tokens baked (Gotcha 12); provider key is runtime env/mount only.

### Acceptance evidence

`docker build -t re-box:m4 .` → exit 0 (single attempt, ~3.5 min;
exported `sha256:f09a022386cef88219672940d55ee4779e5464a12e07cc7f34dfb90d785d42f`).

In-build `RUN` (stage `final 6/6`) output, all green:

| Check | Command (in build) | Observed |
| --- | --- | --- |
| Node 22 | `node --version \| grep -q '^v22\.'` | pass — container reports `v22.23.3` |
| Bun | `bun --version` | `1.4.3` |
| JDK 21+ | `java -version` + `grep -Eq 'openjdk version "(2[1-9]\|[3-9][0-9])'` | `openjdk version "21.0.12.1" 2026-08-18` / `OpenJDK 64-Bit Server VM (build 21.0.12.1+1-1-24.04.4-Ubuntu, mixed mode, sharing)` |
| OpenCode pin | `opencode --version \| grep -q 'opencode v2\.0\.32'` | `opencode v2.0.32` |
| ps | `ps --version` | `ps from procps-ng 4.0.4` |
| prlimit | `/usr/bin/prlimit --version` | `prlimit from util-linux 2.39.3` |
| Full JDK | `java --list-modules \| grep -q jdk.compiler` | `jdk.compiler@21.0.12.1` present |

Post-build container probe
(`docker run --rm re-box:m4 bash -lc '…; whoami; pwd'`) confirms the same
versions plus `whoami → re`, `pwd → /workspace`.

### Notes / discrepancies

- None vs §4: Node is `v22.23.3` (satisfies `^22.19` REA range); JDK is a
  full 21.x with `jdk.compiler`; opencode is exactly `v2.0.32` (not the
  opencode-rea 2.0.26 pin — intentional per Decision 4).
- Docker build attempts: 1 (no failures; no blocker).
