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

## M5 — engine contract

Date: 2026-10-18 (UTC). Branch: `claude/project-thread-gnv9zf`
(from `94868f7` feat(m4) + dirty M5 work in progress).
Spec: `docs/IMPLEMENTATION_PROMPT.md` §6 M5 + §4.4 table + §4.4a/4.4b +
§7 Gotchas 7, 8, 9, 10, 15, 16, 17, 19 + §8.

Before-state (per task brief): `git status --short` shows
`M Dockerfile README.md config/env.defaults scripts/install-ghidra.sh scripts/install-jadx.sh`
plus untracked `scripts/healthcheck.mjs` — the in-progress M5 work this
milestone completes. No reset was performed.

### What was built

`scripts/install-ghidra.sh` (Ghidra 12.1.4 → `/opt/ghidra_12.1.4_PUBLIC`,
sha-verified), `scripts/install-jadx.sh` (jadx-headless-mcp 0.7.1 JAR →
`/opt/jadx/jadx-headless-mcp-0.7.1-all.jar`, sha-verified),
`scripts/healthcheck.mjs` (loops every path var in `config/env.defaults`,
exit 1 on any missing/non-absolute entry; also asserts the `compact`
schema profile value and `analyzeHeadless` executability), `config/env.defaults`
(26 entries, all absolute: GHIDRA_INSTALL_DIR, JAVA_HOME, REA_JADX_MCP_JAR,
Rizin/objdump/gdb, venv python/mitmdump/unblob, pwndbg gdb/gdbinit/venv,
Binwalk, Apktool, adb, tshark/capinfos/sigrok-cli, Wakaru, WABT bin dir,
5 prlimit overrides, schema profile), `COPY`ed to
`/etc/profile.d/re-box-env.sh` and mirrored as Docker `ENV` lines.
`REA_GHIDRA_COMPILER_SPEC_ID` / `REA_GHIDRA_LANGUAGE_ID` intentionally unset
(counter-setting the former without the latter fails REA validation —
`rea/src/config/environment.ts:181-189`).

`Dockerfile` (final stage) adds, in order: APT engines (binutils, gdb,
gdbserver, tshark, sigrok-cli, standalone `adb` package — the
`android-sdk-platform-tools` metapackage only Recommends it so
`--no-install-recommends` skips it — radare2, gcc, python3-dev, pkg-config,
libfontconfig1-dev (provides `fontconfig.pc` for Binwalk's
`yeslogic-fontconfig-sys` crate — without it `cargo install binwalk`
fails), xz-utils, file), Ghidra, JADX, rizin 0.9.1 static (`rizin -version` must report
0.9.1; REA invokes `rizin`, never `r2` — `rea/src/rizin/RizinDebugSessionManager.ts:254`),
WABT 1.0.42 (upstream `.sha256`-verified), Wakaru 1.14.0 (binary-sha
verified), Binwalk 3.1.0 via cargo (apt's binwalk is 2.x), venv
`/opt/venvs/re-tools` (pwntools 4.15.0 + pyelftools 0.33 + unicorn 2.1.2 +
mitmproxy 12.2.3 + Unblob 26.6.4), Apktool 3.0.3, pwndbg (tag `2026.09.15`),
env contract, tiny C sample (`/opt/re-box/samples/hello`), non-root `re`
user, in-build M4 + M5 acceptance `RUN`s, `rea doctor` gates, a real Ghidra
decompile gate, and `HEALTHCHECK` running `healthcheck.mjs`.

### Pre-build upstream verification (host, 2026-10-18)

Every download URL was checked (`curl -sIL` → 200) before the build:

| Artifact | URL check | Hash / version proof |
| --- | --- | --- |
| Ghidra 12.1.4 | 200 (`.../Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip`) | in-build `sha256sum -c` with `ddac49f9…87d` → `OK` (see build log) |
| JADX 0.7.1 | 200 (`1013503897/jadx-headless-mcp/.../jadx-headless-mcp-0.7.1-all.jar`) | `6e5eacf5…73ff75` re-verified in-build (Gotcha 8) |
| rizin 0.9.1 | 200 | tarball listing starts with `bin/rizin` (no top-level dir) → `/opt/rizin-0.9.1/bin/rizin` layout confirmed; `rizin -version \| grep 0\.9\.1` in-build |
| WABT 1.0.42 | 200 | upstream `.sha256` file is `<hash>  wabt-1.0.42-linux-x64.tar.gz` — Dockerfile keeps the upstream filename for `sha256sum -c` (a `wabt.tar.gz` rename would fail the check; fixed during M5) |
| Wakaru 1.14.0 | 200 | tarball contains single top-level `wakaru`; extracted binary sha256 `664fa067…927c38` matches Dockerfile; `./wakaru --version` → `wakaru 1.14.0` |
| Binwalk | `cargo search` + crates.io API: `binwalk = "3.1.0"` exists (only 3.x on crates.io) | `binwalk --version` → 3.1.x in-build |
| Apktool 3.0.3 | 200 (`.../v3.0.3/apktool_3.0.3.jar`) | `apktool --version` ≥ 3.0.2 gate in-build |
| pwndbg | `git ls-remote`: tag `2026.09.15` exists (`55596aa6…`) | `--branch 2026.09.15` clone + `gdbinit.py`/`.venv` checks in-build |
| PyPI | `pwntools 4.15.0`, `pyelftools 0.33`, `unicorn 2.1.2`, `mitmproxy 12.2.3`, `unblob 26.6.4` all 200 on `pypi.org/pypi/<name>/<ver>/json` | `pip install` pins + `mitmdump --version` / `unblob --version` gates in-build |
| rea-agents | `npm` `rea-agents@6.5.0` | `bin` = `rea` + `rea-agents` (`rea/package.json`); `--json` is a valid Incur output flag (`rea/src/cliOutput.ts`); doctor JSON prints the report object directly (Dockerfile `node -e` accepts `r.result ?? r`) |

REA source facts re-checked (read-only): doctor report = `{ healthy,
environment_healthy, scope, scope_checks, checks, providerInspections[{id,
available, providerVersion}], ... }` (`rea/src/application/Doctor.ts`);
`--provider ghidra --provider jadx` scope is satisfiable without client
registration, while `--client opencode` yields a `registration:opencode`
`config_drift` check until M6 `rea setup` runs — so the Dockerfile gates
assert `healthy` only for the provider-scoped run, and provider-availability
+ zero `missing_analysis_engine` for the client-scoped run.

`scripts/healthcheck.mjs` unit-probed on the host with `node`:
all-missing env → exit 1 with 18 failures; crafted all-present env →
only the (expected, image-only) `analyzeHeadless` failure; malformed line /
wrong `compact` value / relative path each fail closed with exit 1.
`config/env.defaults` assignments use `export ` so login shells sourcing
`/etc/profile.d/re-box-env.sh` propagate to child processes (the
healthcheck parser accepts the optional `export ` prefix).

### Build + acceptance evidence

Build attempts: 2 of max 3 used (1 prior fontconfig fix per brief + 2 here).

- Attempt 1 (`docker build -t re-box:m5 .`, full log
  `/tmp/opencode/m5-build-attempt1.log`) → exit 1 at `[final 25/26]`
  (`rea doctor --client opencode` gate). Root cause: the gate asserted
  zero `missing_analysis_engine` across `checks + scope_checks`, but
  `--client opencode` reports licensed/host-only `hopper` and
  `ida-registration` as `missing_analysis_engine` even though Gotcha 11
  forbids baking them (`mount, do not bake`). The in-build log proves it:
  `doctor(client opencode): ghidra available (12.1.4)`,
  `doctor(client opencode): jadx available (unversioned)`, then
  `missing engine: hopper` / `missing engine: ida-registration IDA MCP
  registration is not configured.` — exit 1. Fix (Dockerfile `RUN`
  25/26): exclude the licensed/host-only set
  `{hopper, ida-registration, ida, jeb, kuna}` from the missing-engine
  failure, logging each exclusion; the Dockerfile comment already stated
  this intent, the code now matches it. All other layers (M4 checks, M5
  binary checks, scoped doctor) were green in attempt 1, so only the
  doctor + decompile layers re-ran.
- Attempt 2 (same command, full log `/tmp/opencode/m5-build.log`) →
  exit 0. Final image `re-box:m5 9.89GB (81de28cc0fec)`.

In-build gates (every binary check runs INSIDE the image as a Dockerfile
`RUN`, never by grepping config — Gotcha 19):

| Check | Dockerfile RUN (in-image) | Observed (build log) |
| --- | --- | --- |
| JADX jar sha | `RUN ... echo '6e5eac…73ff75 ...jar' \| sha256sum -c -` (final 23/26) | `/opt/jadx/jadx-headless-mcp-0.7.1-all.jar: OK` (also `install-jadx.sh`: download `OK` + installed `OK`) |
| analyzeHeadless | `RUN bash .../install-ghidra.sh && test -x .../analyzeHeadless` + `test -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless"` (final 23/26) | `install-ghidra: verifying sha256` → `ghidra_12.1.4_PUBLIC_20260921.zip: OK` → `install-ghidra: OK .../support/analyzeHeadless` |
| rizin | `rizin -version \| grep -q '0\.9\.1'` (final 23/26; install pins `rizin-v0.9.1-static`) | `rizin 0.9.1 @ linux-x86-64` |
| objdump / gdb / adb | `objdump --version; gdb --version; adb --version` (APT layer + final 23/26) | `GNU objdump 2.42`, `GNU gdb 15.1`, `Android Debug Bridge 1.0.41 / 34.0.4-debian` |
| apktool | `apktool --version ... grep -qE '3\.0\.[2-9]\|...'` (final 23/26) | `3.0.3` |
| binwalk | `"$REA_BINWALK_COMMAND" --version ... grep -qE '3\.1\.[0-9]+'` (final 23/26) | `binwalk 3.1.0` |
| unblob | `"$REA_UNBLOB_COMMAND" --version ... grep -qE '26\.6\.'` (final 23/26) | `26.6.4` |
| tshark/capinfos | `"$REA_TSHARK_COMMAND" --version ... 'tshark .* 4\.'` + `capinfos --version ... 'capinfos .* 4\.'` (final 23/26) | `TShark (Wireshark) 4.2.2`, `Capinfos (Wireshark) 4.2.2` |
| sigrok-cli | `sigrok-cli --version ... grep -q '0\.7\.2'` (final 23/26) | `sigrok-cli 0.7.2` |
| wakaru | `"$REA_WAKARU_COMMAND" --version \| grep -q '1\.14\.0'` (final 23/26) | `wakaru 1.14.0` (binary sha `664fa067…927c38: OK`) |
| wabt | `wasm2wat --version \| grep -q '1\.0\.42'` (WABT layer) | upstream `.sha256: OK`, `1.0.42` |
| M4 contract | `RUN ... node --version \| grep -q '^v22\.'; bun; java; opencode; ps; prlimit; jdk.compiler` (final 22/26) | `M4 acceptance checks passed` |
| healthcheck | `node /opt/re-box/scripts/healthcheck.mjs` (final 23/26) + `HEALTHCHECK` | `healthcheck: all 26 entries present` |
| doctor scoped | `rea doctor --provider ghidra --provider jadx --json` + `healthy===true`, ghidra+jadx available (final 24/26) | `doctor: ghidra available (12.1.4)`, `doctor: jadx available (unversioned)`, `doctor scoped gate passed` |
| doctor client | `rea doctor --client opencode --json` + ghidra+jadx available, zero non-licensed missing (final 25/26) | `ghidra available (12.1.4)`, `jadx available (unversioned)`, 5 licensed exclusions logged, `no missing engine for installed providers` |
| real decompile | `rea analyze /opt/re-box/samples/hello --provider ghidra --json` + `main` symbol, no engine-missing markers (final 26/26) | `8694 /tmp/ghidra-hello.json`, `ghidra decompile gate passed` |

Post-build runtime probes (trimmed, no secrets):

- `docker run --rm re-box:m5 node /opt/re-box/scripts/healthcheck.mjs`
  → exit 0, `healthcheck: all 26 entries present
  (/etc/profile.d/re-box-env.sh)` (all 25 paths `ok` + `compact` +
  `analyzeHeadless` executable).
- `docker run --rm re-box:m5 rea doctor --client opencode --json`
  → `healthy=false` (expected pre-M6: `registration:opencode` +
  `skill:identity` are `config_drift` until `rea setup` runs),
  `providers=[ghidra available 12.1.4, ida available false,
  jadx available true]`,
  `missing_total=4 [hopper, ida-registration ×2]` (checks +
  informational), `missing_nonlicensed=(none)`. Trimmed head shows
  `ghidra-installation .../Ghidra/application.properties`,
  `ghidra-version 12.1.4`, `ghidra-headless .../analyzeHeadless`,
  `ghidra-native_decompiler ... decompile reports elf x86_64`,
  `ghidra-java 21.0.12.1; 64-bit; JDK`.
- Runtime versions match the in-build gates: jar `OK`, analyzeHeadless
  `OK`, `rizin 0.9.1`, `objdump 2.42`, `gdb 15.1`, `adb 1.0.41 /
  34.0.4-debian`, `apktool 3.0.3`, `binwalk 3.1.0`, `unblob 26.6.4`,
  `tshark/capinfos 4.2.2`, `sigrok-cli 0.7.2`, `wakaru 1.14.0`.

SHA record: JADX jar
`6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75`
(`: OK` in-build + runtime); Ghidra zip sha
`ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db`
(`: OK`); Wakaru binary
`664fa06782a61eda7ed15885134b52525fd565dd77607e642062ceb6cd927c38`
(`: OK`); rizin admitted by exact `0.9.1` version string (no upstream
digest); WABT admitted by upstream `.sha256` file (`: OK`).

No blockers. 1 attempt remaining unused.

### Cross-check probes (second pass, live container)

Independent `docker run --rm re-box:m5 …` probes (user `re`, cwd
`/workspace`) confirming the in-build gates from outside the build:

- Base + tool pins: `node v22.23.3`, `bun 1.4.3`,
  `opencode v2.0.32`, `rea 6.5.0`,
  `openjdk 21.0.12.1` (full JDK, `jdk.compiler` gated in-build).
- Engines: `rizin 0.9.1 @ linux-x86-64`, `GNU objdump 2.42`,
  `GNU gdb 15.1`, `Android Debug Bridge 1.0.41 / 34.0.4-debian`,
  `apktool 3.0.3`, `binwalk 3.1.0`, `unblob 26.6.4`,
  `Mitmproxy: 12.2.3`, `TShark/Capinfos 4.2.2`, `sigrok-cli 0.7.2`,
  `wakaru 1.14.0`, `wasm2wat 1.0.42`.
- `rea doctor --client opencode --json`: `healthy=false` solely from
  `registration:opencode` (`config_drift`, M6 wire-up) and unmounted
  licensed providers; `providerInspections=[ghidra available 12.1.4,
  ida available false, jadx available true]`; `missing_analysis_engine`
  over `checks + scope_checks` = exactly `["hopper","ida-registration"]`
  (licensed/host-only, excluded from the gate by design).
- `node /opt/re-box/scripts/healthcheck.mjs` (the Docker `HEALTHCHECK`
  command): `all 26 entries present (/etc/profile.d/re-box-env.sh)`.
- `source /etc/profile.d/re-box-env.sh` exports 24 `REA_*` vars
  (26 entries minus `GHIDRA_INSTALL_DIR`/`JAVA_HOME`).
- Real decompile (`rea analyze /opt/re-box/samples/hello --provider
  ghidra --json`, 8694 bytes, `main` present, zero engine-missing
  markers): `evidence_id`
  `ev_325cfa2858ceaeb774be753aba3b4f9e5ae727195409c4094fcdb1e72492850f`,
  subject `{name: hello, sha256: fd924d44…b76, format: elf,
  architecture: x86_64}`, upstream profile `{provider: ghidra 12.1.4,
  target_kind: executable, target_format: elf, architecture: x86_64, …}`;
  `normalized_result` opens with Ghidra image segments (`.interp`,
  `.note.gnu.property`, `.dynsym`, …, `image_base 0x100000`).
