#!/usr/bin/env node
// re-box M5/M7: fail-closed engine-path healthcheck.
//
// Loops over every path variable in config/env.defaults (in the image:
// /etc/profile.d/re-box-env.sh) and fails (exit 1) if any is missing —
// except M7 optional triage paths (OPTIONAL_PATH_VARS), which warn-and-skip
// so ARG=0 lean images stay green.
// Run as the last Dockerfile build step and as the Docker HEALTHCHECK, so the
// build fails on any absent engine and an unhealthy container is reported.
//
// Non-path entries (VAR names listed in NON_PATH_VARS) are validated for
// value instead of existence. Comment (#) and blank lines are ignored.
// A process environment variable with the same name overrides the file value
// (empty counts as unset); checks run against the effective value.
// Usage: node scripts/healthcheck.mjs [env-file]
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const NON_PATH_VARS = new Map([
  // name -> expected value (exact match required)
  ["REA_MCP_INPUT_SCHEMA_PROFILE", "compact"],
]);

// Optional command paths (M7 complementary triage). A lean image built with
// REBOX_WITH_REVA=0 / REBOX_WITH_DIE=0 legitimately lacks these, so a missing
// entry warns instead of failing. When present, the target must exist.
const OPTIONAL_PATH_VARS = new Set(["REVA_COMMAND", "DIEC_COMMAND"]);

const EXTRA_CHECKS = [
  // [label, path] — must exist AND be executable
  ["analyzeHeadless", `${process.env.GHIDRA_INSTALL_DIR ?? "/opt/ghidra_12.1.4_PUBLIC"}/support/analyzeHeadless`],
];

function parseEnvFile(text) {
  const entries = [];
  for (const rawLine of text.split("\n")) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) continue;
    // Allow optional leading `export ` (profile.d sourced form).
    const body = line.startsWith("export ") ? line.slice(7).trim() : line;
    const eq = body.indexOf("=");
    if (eq === -1) {
      console.error(`healthcheck: malformed line (no '='): ${rawLine}`);
      process.exitCode = 1;
      continue;
    }
    const name = body.slice(0, eq).trim();
    let value = body.slice(eq + 1).trim();
    // Strip matching single/double quotes.
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    entries.push({ name, value });
  }
  return entries;
}

async function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const fallback = resolve(here, "../config/env.defaults");
  const envFile = process.argv[2] ?? (existsSync("/etc/profile.d/re-box-env.sh") ? "/etc/profile.d/re-box-env.sh" : fallback);
  let text;
  try {
    text = await readFile(envFile, "utf8");
  } catch (cause) {
    console.error(`healthcheck: cannot read ${envFile}: ${cause.message}`);
    process.exit(1);
  }
  const entries = parseEnvFile(text);
  if (entries.length === 0) {
    console.error(`healthcheck: no entries in ${envFile}`);
    process.exit(1);
  }
  let failures = 0;
  for (const { name, value } of entries) {
    // Effective runtime path: an exported env var wins (it is what the
    // runtime actually sees), otherwise the file value. An empty-string env
    // counts as unset. Per-line output stays byte-stable when no override is
    // set; an active override is marked so the source is auditable.
    const envVal = process.env[name];
    const overridden = envVal !== undefined && envVal !== "";
    const effective = overridden ? envVal : value;
    const tag = overridden ? " (env override)" : "";
    if (NON_PATH_VARS.has(name)) {
      const expected = NON_PATH_VARS.get(name);
      if (effective !== expected) {
        console.error(`healthcheck: FAIL ${name}=${effective} (expected ${expected})`);
        failures += 1;
      } else {
        console.log(`healthcheck: ok ${name}=${effective}${tag}`);
      }
      continue;
    }
    if (!effective.startsWith("/")) {
      console.error(`healthcheck: FAIL ${name}=${effective} (not an absolute path)`);
      failures += 1;
      continue;
    }
    if (!existsSync(effective)) {
      if (OPTIONAL_PATH_VARS.has(name)) {
        console.log(`healthcheck: skip ${name}=${effective} (optional, not installed)`);
        continue;
      }
      console.error(`healthcheck: FAIL ${name}=${effective} (missing)`);
      failures += 1;
      continue;
    }
    console.log(`healthcheck: ok ${name}=${effective}${tag}`);
  }
  for (const [label, path] of EXTRA_CHECKS) {
    try {
      const { constants } = await import("node:fs");
      const { access } = await import("node:fs/promises");
      await access(path, constants.X_OK);
      console.log(`healthcheck: ok ${label} executable at ${path}`);
    } catch {
      console.error(`healthcheck: FAIL ${label} not executable at ${path}`);
      failures += 1;
    }
  }
  if (failures > 0) {
    console.error(`healthcheck: ${failures} failure(s) in ${envFile}`);
    process.exit(1);
  }
  console.log(`healthcheck: all ${entries.length} entries present (${envFile})`);
}

await main();
