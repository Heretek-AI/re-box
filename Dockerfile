# re-box — reproducible reverse-engineering container (M4 base image)
#
# Multi-stage build:
#   Stage 1 (system): Ubuntu 24.04 + APT toolchain (JDK 21 full, procps ps,
#                     util-linux prlimit, git, python3+pip+venv, curl/unzip,
#                     NodeSource keyring prerequisites).
#   Stage 2 (final):  Node 22 (NodeSource), Bun, OpenCode CLI 2.0.32
#                     (pinned, locked), non-root `re` user, /workspace.
#
# Later milestones (M5+) add Ghidra/JADX/rizin/etc. on top of this base.
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

# Non-root operator + mount point.
RUN useradd -m -s /bin/bash re \
  && mkdir -p /workspace \
  && chown re:re /workspace

WORKDIR /workspace
USER re

# Acceptance checks (fail closed: any mismatch fails the build).
# Recorded with evidence in docs/NOTES.md.
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
