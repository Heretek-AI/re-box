# re-box — reproducible reverse-engineering container (M6 wire-up)
#
# Multi-stage build:
#   Stage 1 (system): Ubuntu 24.04 + APT toolchain (JDK 21 full, procps ps,
#                     util-linux prlimit, git, python3+pip+venv, curl/unzip,
#                     NodeSource keyring prerequisites).
#   Stage 2 (final):  Node 22 (NodeSource), Bun, OpenCode CLI 2.0.32
#                     (pinned, locked), all M5 analysis engines, non-root `re`
#                     user, /workspace, M6 REA wire-up (setup-rea.sh as `re`:
#                     rea setup + opencode-rea plugin + skill bundle +
#                     operator-memory + compact profile + watcher.ignore),
#                     entrypoint gates ps/prlimit then execs opencode.
#
# M5 engines (IMPLEMENTATION_PROMPT Sec 4.4, pinned):
#   Ghidra 12.1.4 (NSA release, sha-verified) + full JDK 21,
#   JADX jadx-headless-mcp 0.7.1 (sha256-verified JAR),
#   rizin 0.9.1 (static release; REA invokes `rizin`, never `r2`) + radare2,
#   GNU objdump (binutils), gdb + pwndbg, Binwalk 3.1.x (cargo Rust build),
#   Unblob 26.6.4, Apktool 3.0.3, tshark+capinfos 4.x, sigrok-cli 0.7.2, adb,
#   Wakaru 1.14.0, WABT 1.0.42, venv /opt/venvs/re-tools
#   (pwntools 4.15.0 + pyelftools 0.33 + unicorn 2.1.2 + mitmproxy 12.2.3).
# Every REA_* path lives in config/env.defaults, is COPYed to
# /etc/profile.d/re-box-env.sh, and is mirrored as Docker ENV lines so
# non-login shells + `opencode` see identical values.
# Secrets policy: never bake API keys/tokens into the image. The model
# provider key is supplied at runtime (env/mount), never at build time.

# ---------------------------------------------------------------- Stage 1
FROM ubuntu:24.04 AS system

ENV DEBIAN_FRONTEND=noninteractive

# Core APT toolchain. openjdk-21-jdk is the FULL JDK (jdk.compiler module),
# not a headless JRE. procps provides `ps`, util-linux provides `prlimit`.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       gnupg \
       git \
       unzip \
       procps \
       util-linux \
       python3 \
       python3-pip \
       python3-venv \
       openjdk-21-jdk \
  && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------- Stage 2
FROM system AS final

ENV DEBIAN_FRONTEND=noninteractive

# Node.js 22 via NodeSource (pinned major 22.x).
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && node --version

# Bun via the official install script, promoted to /usr/local/bin so every
# user (including the non-root `re` user) sees it on PATH.
ENV BUN_INSTALL=/usr/local/bun
RUN curl -fsSL https://bun.sh/install | bash \
  && ln -sf /usr/local/bun/bin/bun /usr/local/bin/bun \
  && bun --version

# OpenCode CLI pinned to 2.0.32 (locked per IMPLEMENTATION_PROMPT Sec 4.6
# Decision 4). This pin belongs to re-box only; opencode-rea stays on 2.0.26.
RUN npm install -g @opencode/cli@2.0.32 \
  && opencode --version

# rea-agents CLI (pinned 6.5.0) — provides `rea doctor` / `rea analyze` used
# by the build-time acceptance checks and available at runtime.
RUN npm install -g rea-agents@6.5.0 \
  && rea --version

# ---- M5 APT engines ------------------------------------------------------
# binutils (objdump), gdb, tshark+capinfos 4.x, sigrok-cli 0.7.2,
# adb 34.x (standalone `adb` package — the `android-sdk-platform-tools`
# metapackage only Recommends it, so --no-install-recommends skips it),
# radare2 (optional, for skills; REA itself calls `rizin`, never `r2`),
# gcc (tiny sample build + cargo cc), python3-dev (venv/pwndbg builds),
# libfontconfig1-dev (fontconfig.pc for binwalk's yeslogic-fontconfig-sys).
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       binutils \
       gdb \
       gdbserver \
       tshark \
       sigrok-cli \
       adb \
       radare2 \
       gcc \
       python3-dev \
       pkg-config \
       libfontconfig1-dev \
       file \
       xz-utils \
  && rm -rf /var/lib/apt/lists/* \
  && objdump --version \
  && gdb --version \
  && adb --version

# ---- M5 Ghidra 12.1.4 (sha-verified NSA release) --------------------------
COPY scripts/install-ghidra.sh /tmp/re-box/install-ghidra.sh
RUN bash /tmp/re-box/install-ghidra.sh \
  && test -x /opt/ghidra_12.1.4_PUBLIC/support/analyzeHeadless

# ---- M5 JADX 0.7.1 (sha-verified JAR) -------------------------------------
COPY scripts/install-jadx.sh /tmp/re-box/install-jadx.sh
RUN bash /tmp/re-box/install-jadx.sh \
  && test -f /opt/jadx/jadx-headless-mcp-0.7.1-all.jar

# ---- M5 rizin 0.9.1 (static upstream release; REA invokes `rizin`) ---------
# No published digest exists for the static asset, so admission is by exact
# version string (`rizin -version` must report 0.9.1); recorded in NOTES.
RUN set -eux; \
  mkdir -p /opt/rizin-0.9.1; \
  curl -fL --retry 3 --retry-delay 5 \
    -o /tmp/rizin-static.tar.xz \
    https://github.com/rizinorg/rizin/releases/download/v0.9.1/rizin-v0.9.1-static-x86_64.tar.xz; \
  tar -xJf /tmp/rizin-static.tar.xz -C /opt/rizin-0.9.1; \
  rm -f /tmp/rizin-static.tar.xz; \
  for b in /opt/rizin-0.9.1/bin/*; do ln -sf "$b" /usr/local/bin/; done; \
  rizin -version; \
  rizin -version | grep -q '0\.9\.1'

# ---- M5 WABT 1.0.42 (sha-verified GitHub release tarball) ------------------
RUN set -eux; \
  mkdir -p /opt/wabt-1.0.42; \
  curl -fL --retry 3 --retry-delay 5 \
    -o /tmp/wabt-1.0.42-linux-x64.tar.gz \
    https://github.com/WebAssembly/wabt/releases/download/1.0.42/wabt-1.0.42-linux-x64.tar.gz; \
  curl -fL --retry 3 --retry-delay 5 \
    -o /tmp/wabt-1.0.42-linux-x64.tar.gz.sha256 \
    https://github.com/WebAssembly/wabt/releases/download/1.0.42/wabt-1.0.42-linux-x64.tar.gz.sha256; \
  (cd /tmp && sha256sum -c wabt-1.0.42-linux-x64.tar.gz.sha256); \
  tar -xzf /tmp/wabt-1.0.42-linux-x64.tar.gz -C /opt/wabt-1.0.42 --strip-components=1; \
  rm -f /tmp/wabt-1.0.42-linux-x64.tar.gz /tmp/wabt-1.0.42-linux-x64.tar.gz.sha256; \
  test -x /opt/wabt-1.0.42/bin/wasm2wat; \
  /opt/wabt-1.0.42/bin/wasm2wat --version | grep -q '1\.0\.42'

# ---- M5 Wakaru 1.14.0 (official release binary, binary-sha verified) --------
# REA docs pin the extracted binary SHA-256 to
# 664fa06782a61eda7ed15885134b52525fd565dd77607e642062ceb6cd927c38.
RUN set -eux; \
  mkdir -p /opt/wakaru; \
  curl -fL --retry 3 --retry-delay 5 \
    -o /tmp/wakaru.tgz \
    https://github.com/pionxzh/wakaru/releases/download/v1.14.0/wakaru-linux-x64.tar.gz; \
  tar -xzf /tmp/wakaru.tgz -C /opt/wakaru; \
  rm -f /tmp/wakaru.tgz; \
  echo '664fa06782a61eda7ed15885134b52525fd565dd77607e642062ceb6cd927c38  /opt/wakaru/wakaru' | sha256sum -c -; \
  chmod +x /opt/wakaru/wakaru; \
  /opt/wakaru/wakaru --version | grep -q '1\.14\.0'

# ---- M5 Binwalk 3.1.x (Rust rewrite via cargo; apt's binwalk is 2.x) -------
# Toolchain is removed after the install; the static binary stays at
# /opt/binwalk/bin/binwalk.
RUN set -eux; \
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain stable; \
  export PATH="/root/.cargo/bin:${PATH}"; \
  rustc --version; cargo --version; \
  cargo install binwalk --version 3.1.0 --root /opt/binwalk; \
  rustup self uninstall -y; \
  rm -rf /root/.cargo /root/.rustup; \
  /opt/binwalk/bin/binwalk --version; \
  /opt/binwalk/bin/binwalk --version 2>&1 | grep -qE '3\.1\.[0-9]+'

# ---- M5 Python venv: pwntools 4.15.0 + mitmproxy 12.2.3 + Unblob 26.6.4 ----
RUN set -eux; \
  python3 -m venv /opt/venvs/re-tools; \
  /opt/venvs/re-tools/bin/pip install --no-cache-dir --upgrade pip; \
  /opt/venvs/re-tools/bin/pip install --no-cache-dir \
    'pwntools==4.15.0' 'pyelftools==0.33' 'unicorn==2.1.2' \
    'mitmproxy==12.2.3' 'unblob==26.6.4'; \
  /opt/venvs/re-tools/bin/python -c 'import pwnlib, unicorn, elftools; print("py-ok")'; \
  /opt/venvs/re-tools/bin/mitmdump --version | grep -q '12\.2\.3'; \
  /opt/venvs/re-tools/bin/unblob --version 2>&1 | grep -qE '26\.6\.'

# ---- M5 Apktool 3.0.3 (>= 3.0.2 per CVE disclosure rule) --------------------
RUN set -eux; \
  mkdir -p /opt/apktool; \
  curl -fL --retry 3 --retry-delay 5 \
    -o /opt/apktool/apktool_3.0.3.jar \
    https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar; \
  printf '#!/bin/sh\nexec java -jar /opt/apktool/apktool_3.0.3.jar "$@"\n' > /usr/local/bin/apktool; \
  chmod +x /usr/local/bin/apktool; \
  apktool --version; \
  apktool --version 2>&1 | grep -qE '3\.0\.[2-9]|3\.[1-9][0-9]*\.'

# ---- M5 pwndbg (latest release clone; gdb+gdbinit+venv contract) ------------
RUN set -eux; \
  git clone --depth 1 --branch 2026.09.15 https://github.com/pwndbg/pwndbg /opt/pwndbg; \
  cd /opt/pwndbg; \
  PWNDBG_VENV_PATH=/opt/pwndbg/.venv PWNDBG_NO_AUTOUPDATE=1 ./setup.sh; \
  test -f /opt/pwndbg/gdbinit.py; \
  test -d /opt/pwndbg/.venv

# ---- M5 engine-path contract ------------------------------------------------
# Single source of truth: config/env.defaults -> /etc/profile.d (login
# shells) + Docker ENV (non-login shells, `opencode`).
COPY config/env.defaults /etc/profile.d/re-box-env.sh
COPY scripts/healthcheck.mjs /opt/re-box/scripts/healthcheck.mjs

ENV GHIDRA_INSTALL_DIR=/opt/ghidra_12.1.4_PUBLIC
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV REA_JADX_MCP_JAR=/opt/jadx/jadx-headless-mcp-0.7.1-all.jar
ENV REA_RIZIN_COMMAND=/opt/rizin-0.9.1/bin/rizin
ENV REA_OBJDUMP_COMMAND=/usr/bin/objdump
ENV REA_GDB_COMMAND=/usr/bin/gdb
ENV REA_PWNTOOLS_PYTHON=/opt/venvs/re-tools/bin/python
ENV REA_MITMDUMP_COMMAND=/opt/venvs/re-tools/bin/mitmdump
ENV REA_UNBLOB_COMMAND=/opt/venvs/re-tools/bin/unblob
ENV REA_PWNDBG_GDB=/usr/bin/gdb
ENV REA_PWNDBG_GDBINIT=/opt/pwndbg/gdbinit.py
ENV REA_PWNDBG_VENV_PATH=/opt/pwndbg/.venv
ENV REA_BINWALK_COMMAND=/opt/binwalk/bin/binwalk
ENV REA_APKTOOL_COMMAND=/usr/local/bin/apktool
ENV REA_ADB_PATH=/usr/bin/adb
ENV REA_TSHARK_COMMAND=/usr/bin/tshark
ENV REA_CAPINFOS_COMMAND=/usr/bin/capinfos
ENV REA_SIGROK_COMMAND=/usr/bin/sigrok-cli
ENV REA_WAKARU_COMMAND=/opt/wakaru/wakaru
ENV REA_WABT_BIN_DIRECTORY=/opt/wabt-1.0.42/bin
ENV REA_TSHARK_PRLIMIT_COMMAND=/usr/bin/prlimit
ENV REA_SIGROK_PRLIMIT_COMMAND=/usr/bin/prlimit
ENV REA_JAVASCRIPT_PRLIMIT_COMMAND=/usr/bin/prlimit
ENV REA_FIRMWARE_PRLIMIT_COMMAND=/usr/bin/prlimit
ENV REA_EVM_PRLIMIT_COMMAND=/usr/bin/prlimit
ENV REA_MCP_INPUT_SCHEMA_PROFILE=compact

# ---- M5 tiny sample target (Ghidra headless acceptance decompile) ----------
RUN set -eux; \
  mkdir -p /opt/re-box/samples; \
  printf '#include <stdio.h>\nint main(void){printf("re-box m5\\n");return 0;}\n' > /opt/re-box/samples/hello.c; \
  gcc -O0 -g -o /opt/re-box/samples/hello /opt/re-box/samples/hello.c; \
  /opt/re-box/samples/hello | grep -q 're-box m5'

# Non-root operator + mount point.
RUN useradd -m -s /bin/bash re \
  && mkdir -p /workspace \
  && chown re:re /workspace

# ---- M6 wire-up (IMPLEMENTATION_PROMPT Sec 6 M6; root-owned inputs) ---------
# jq: the opencode.json merge in setup-rea.sh.
# Curated skill bundle (copy-from-image, documented choice): the published
# @heretek-ai/opencode-rea skill packs, pinned, extracted to
# /opt/re-box/skills. setup-rea.sh copies them into ~/.agents/skills and
# never overwrites reverse-engineer-anything (Gotcha 14).
# operator-helper: installs operator-memory for OpenCode V2 (Decision 2).
RUN apt-get update \
  && apt-get install -y --no-install-recommends jq \
  && rm -rf /var/lib/apt/lists/* \
  && jq --version

ARG REBOX_REA_PLUGIN_VERSION=0.1.2
RUN set -eux; \
  mkdir -p /opt/re-box/skills; \
  cd /tmp; \
  TARBALL="$(npm pack "@heretek-ai/opencode-rea@${REBOX_REA_PLUGIN_VERSION}" --silent | tail -n 1)"; \
  test -n "$TARBALL"; \
  test -f "/tmp/$TARBALL"; \
  tar -xzf "/tmp/$TARBALL" -C /tmp; \
  test -f /tmp/package/skills/rea-opencode/SKILL.md; \
  cp -r /tmp/package/skills/* /opt/re-box/skills/; \
  rm -rf "/tmp/$TARBALL" /tmp/package; \
  ls /opt/re-box/skills

RUN npm install -g "@aerovato/operator-helper@1.8.0" \
  && operator-helper --help 2>&1 | grep -q 'install opencode-v2'

COPY --chown=re:re scripts/setup-rea.sh scripts/entrypoint.sh /opt/re-box/scripts/
RUN chmod +x /opt/re-box/scripts/setup-rea.sh /opt/re-box/scripts/entrypoint.sh \
  && sh -n /opt/re-box/scripts/setup-rea.sh \
  && sh -n /opt/re-box/scripts/entrypoint.sh

WORKDIR /workspace
USER re

# M6 wire-up runs as `re` at build time (idempotent; the entrypoint only
# re-checks prerequisites, it does not re-run setup).
RUN /opt/re-box/scripts/setup-rea.sh

# Acceptance checks (fail closed: any mismatch fails the build).
# M4 base checks first, then the M5 engine contract — every binary check
# runs INSIDE the built image, never by grepping config.
RUN set -eux; \
  node --version | grep -q '^v22\.'; \
  bun --version; \
  java -version 2>&1 | tee /tmp/java-version.txt; \
  grep -Eq 'openjdk version "(2[1-9]|[3-9][0-9])' /tmp/java-version.txt; \
  opencode --version | grep -q 'opencode v2\.0\.32'; \
  ps --version; \
  /usr/bin/prlimit --version; \
  java --list-modules | grep -q jdk.compiler; \
  echo "M4 acceptance checks passed"

RUN set -eux; \
  echo '6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75  /opt/jadx/jadx-headless-mcp-0.7.1-all.jar' | sha256sum -c -; \
  test -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless"; \
  rizin -version | grep -q '0\.9\.1'; \
  objdump --version; \
  gdb --version; \
  adb --version; \
  apktool --version 2>&1 | grep -qE '3\.0\.[2-9]|3\.[1-9][0-9]*\.'; \
  "$REA_BINWALK_COMMAND" --version 2>&1 | grep -qE '3\.1\.[0-9]+'; \
  "$REA_UNBLOB_COMMAND" --version 2>&1 | grep -qE '26\.6\.'; \
  "$REA_TSHARK_COMMAND" --version 2>&1 | grep -qiE 'tshark .* 4\.'; \
  capinfos --version 2>&1 | grep -qiE 'capinfos .* 4\.'; \
  sigrok-cli --version 2>&1 | grep -q '0\.7\.2'; \
  "$REA_WAKARU_COMMAND" --version | grep -q '1\.14\.0'; \
  node /opt/re-box/scripts/healthcheck.mjs; \
  echo "M5 binary acceptance checks passed"

# Provider-scoped doctor gate (hard): ghidra + jadx must report available.
# Licensed/host-only providers (IDA, Hopper, JEB, Kuna) are excluded from this
# gate. The exact M5 acceptance command with `--client opencode` is also run
# and its engine inspections asserted; the opencode client registration itself
# is M6 wire-up (setup-rea.sh) and is recorded as informational here.
RUN set -eux; \
  rea doctor --provider ghidra --provider jadx --json | tee /tmp/doctor-scoped.json | head -c 2000; echo; \
  node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync("/tmp/doctor-scoped.json","utf8"));const report=r.result??r;if(report.healthy!==true){console.error("doctor scoped report unhealthy");process.exit(1);}const ins=Object.fromEntries((report.providerInspections??[]).map(i=>[i.id,i]));for(const id of ["ghidra","jadx"]){if(!ins[id]||ins[id].available!==true){console.error(`doctor: provider ${id} not available`);process.exit(1);}console.log(`doctor: ${id} available (${ins[id].providerVersion??"unversioned"})`);}console.log("doctor scoped gate passed");'
RUN set -eux; \
  rea doctor --client opencode --json > /tmp/doctor.json || true; \
  node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync("/tmp/doctor.json","utf8"));const report=r.result??r;const ins=Object.fromEntries((report.providerInspections??[]).map(i=>[i.id,i]));for(const id of ["ghidra","jadx"]){if(!ins[id]||ins[id].available!==true){console.error(`doctor(client opencode): provider ${id} not available`);process.exit(1);}console.log(`doctor(client opencode): ${id} available (${ins[id].providerVersion??"unversioned"})`);}const licensed=new Set(["hopper","ida-registration","ida","jeb","kuna"]);const missing=(report.checks??[]).concat(report.scope_checks??[]).filter(c=>c.classification==="missing_analysis_engine"&&!licensed.has(c.name));if(missing.length>0){for(const m of missing)console.error(`missing engine: ${m.name} ${m.detail??""}`);process.exit(1);}for(const name of licensed){console.log(`doctor(client opencode): licensed/host-only ${name} excluded from gate (mount, do not bake)`);}console.log("doctor(client opencode): no missing engine for installed providers");'

# Real Ghidra decompile of the tiny sample (engine-missing output would fail
# this step: non-zero exit or absence of the `main` symbol in the report).
RUN set -eux; \
  rea analyze /opt/re-box/samples/hello --provider ghidra --json > /tmp/ghidra-hello.json; \
  wc -c /tmp/ghidra-hello.json; \
  node -e 'const fs=require("fs");const raw=fs.readFileSync("/tmp/ghidra-hello.json","utf8");if(!/main/.test(raw)){console.error("decompile: no main symbol in report");process.exit(1);}for(const marker of ["missing_analysis_engine","provider_missing","engine-missing","not_configured"]){if(raw.includes(marker)){console.error(`decompile: engine-missing marker ${marker}`);process.exit(1);}}console.log("ghidra decompile gate passed");'

# ---- M6 wire-up acceptance (runs INSIDE the image, as `re`) ----------------
# setup-rea.sh already ran above; re-assert its contract here so the build
# fails closed: opencode.json has mcp.rea (compact env) + plugin entry +
# watcher.ignore, the skills are on disk, and the entrypoint gates pass.
RUN set -eux; \
  node -e 'const fs=require("fs"),os=require("os"),path=require("path");const p=path.join(os.homedir(),".config/opencode/opencode.json");const c=JSON.parse(fs.readFileSync(p,"utf8"));if(!c.mcp||!c.mcp.rea)throw new Error("mcp.rea block missing");if(c.mcp.rea.environment?.REA_MCP_INPUT_SCHEMA_PROFILE!=="compact")throw new Error("compact profile missing on mcp.rea");if(!(c.plugins??[]).some(s=>String(s).includes("opencode-rea")))throw new Error("opencode-rea plugin entry missing");if(!(c.plugins??[]).some(s=>String(s).includes("operator-opencode-v2")))throw new Error("operator-opencode-v2 plugin entry missing");for(const g of ["targets/**","captures/**","ghidra_projects/**",".rea/**","*.gpr","*.rep/**","*.idb","*.i64","*.pcap*","*.core","*.dmp"]){if(!(c.watcher?.ignore??[]).includes(g))throw new Error("watcher.ignore missing "+g);}console.log("M6 opencode.json gate passed");'; \
  test -f "$HOME/.agents/skills/reverse-engineer-anything/SKILL.md"; \
  for s in rea-evidence-report rea-investigation rea-opencode rea-reconstruction; do test -f "$HOME/.agents/skills/$s/SKILL.md"; done; \
  command -v ps; \
  /usr/bin/prlimit --version; \
  /opt/re-box/scripts/entrypoint.sh --help | grep -q 'OpenCode command line interface'; \
  echo "M6 wire-up acceptance checks passed"

ENTRYPOINT ["/opt/re-box/scripts/entrypoint.sh"]
CMD []

HEALTHCHECK --interval=5m --timeout=2m --start-period=1m \
  CMD node /opt/re-box/scripts/healthcheck.mjs || exit 1
