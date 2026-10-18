# M5 implementation report — re-box engine contract

- Stage ID: M5 (IMPLEMENTATION_PROMPT §6 M5 + §4.4/§4.4a/§4.4b, Gotchas 7, 8, 9, 10, 15, 16, 17, 19)
- Branch: `claude/project-thread-gnv9zf` @ `360b3cf` (`feat(m5): engine contract`, amends joint-session work to the exact required message; not pushed)
- Before-state: `git status --short` showed `M Dockerfile README.md config/env.defaults scripts/install-ghidra.sh scripts/install-jadx.sh` + `?? scripts/healthcheck.mjs` (expected dirty M5 work; no reset performed)
- Image: `re-box:m5` `81de28cc0fec` (9.89 GB), `docker build -t re-box:m5 .` → exit 0 (`BUILD_EXIT:0`)

## Summary of deliverables

Single commit `360b3cf feat(m5): engine contract` (7 files, +743/−46):

- `Dockerfile` — full M5 engine contract: APT layer (binutils, gdb, gdbserver, tshark, sigrok-cli, standalone `adb`, radare2, gcc, python3-dev, pkg-config, `libfontconfig1-dev`, `xz-utils`, file), Ghidra 12.1.4, JADX 0.7.1, rizin 0.9.1 static, WABT 1.0.42, Wakaru 1.14.0, Binwalk 3.1.0 via cargo, venv `/opt/venvs/re-tools`, Apktool 3.0.3, pwndbg @2026.09.15, env contract (COPY + 26 Docker ENV), tiny ELF sample, `re` user, M4+M5 in-build acceptance RUNs, both doctor gates, Ghidra decompile gate, `HEALTHCHECK`. Fixes landed during the milestone: WABT checksum filename (kept upstream name), `libfontconfig1-dev` for `cargo install binwalk`, doctor gate excludes licensed/host-only `{hopper, ida, jeb, kuna}` families.
- `scripts/install-ghidra.sh` / `scripts/install-jadx.sh` — sha-verified installs (Ghidra `ddac49f9…87d`, JADX `6e5eacf5…73ff75`, build fails on mismatch).
- `scripts/healthcheck.mjs` — loops every path var in env.defaults, fails closed on missing/non-absolute/malformed/wrong-profile; asserts `analyzeHeadless` executability; runs as last build step and as Docker `HEALTHCHECK`.
- `config/env.defaults` — 26 entries, all absolute, `export `-prefixed; `REA_GHIDRA_COMPILER_SPEC_ID/LANGUAGE_ID` unset; IDA/Hopper documented as mount-only.
- `README.md` — engines table (+env contract, acceptance, mount, secrets sections).
- `docs/NOTES.md` — full evidence: pre-build upstream verification, in-build gate table, live probes, SHA record, trimmed decompile sample.

## Files created / modified

`Dockerfile`, `scripts/install-ghidra.sh`, `scripts/install-jadx.sh`, `scripts/healthcheck.mjs` (new), `config/env.defaults`, `README.md`, `docs/NOTES.md`. Explicit `git add` only; no push.

## Test results

- `docker build -t re-box:m5 .` → exit 0 after 4 attempts (1 operator-killed superseded run; binwalk fontconfig + doctor licensed-gate failures, distinct causes, fixed; 3×-same-error rule never triggered).
- In-build (all inside image): JADX `OK`, analyzeHeadless executable, `rizin 0.9.1`, objdump 2.42 / gdb 15.1 / adb 34.0.4, apktool 3.0.3, binwalk 3.1.0, unblob 26.6.4, mitmdump 12.2.3, tshark/capinfos 4.2.2, sigrok-cli 0.7.2, wakaru 1.14.0, wabt 1.0.42, `healthcheck: all 26 entries present`, doctor scoped `healthy:true` (ghidra 12.1.4, jadx), doctor client zero non-licensed missing, Ghidra decompile 8694 bytes with `main`, zero engine-missing markers.
- Live probes: versions identical; doctor client `healthy:false` only from `registration:opencode` `config_drift` (M6) + unmounted licensed providers, missing exactly `[hopper, ida-registration]`; profile.d exports 24 `REA_*`; healthcheck green.
- `healthcheck.mjs` unit-probed on host with `node`: fail-closed on all malformed inputs (exit 1).

## Self-audit notes

- Concurrent session edited the same workdir mid-milestone (added `xz-utils`, licensed-gate exclusion, NOTES.md evidence section). Merged additively; verified no clobbering; amended joint commit to the required message. Tree clean, unpushed.
- Licensed/host-only providers (hopper, ida, jeb, kuna) are mounted, never baked — gate exclusion matches the Dockerfile comment and Gotcha 11.
- Pre-M6 `healthy:false` on the client-scoped doctor is expected and recorded; both M5-owned gates assert exactly the M5 contract.
- No stubs, no swallowed errors, no secrets baked. Linter N/A (no JS/TS in repo besides healthcheck, probed with node).
