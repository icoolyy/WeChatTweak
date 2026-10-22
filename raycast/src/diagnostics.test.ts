import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, chmod, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { findExecutable, parseDiagnosis, readDiagnosis } from "./diagnostics.ts";

function report() {
  return { schemaVersion: 1, cliVersion: "2.1.0-dev", patchState: "ready", pendingWrites: 2,
    alreadyPatched: 0, configuredFeatures: ["revoke", "multiInstance"], contactsBridgeAvailable: false,
    contactsBridgeReason: "No verified adapter", errors: [],
    app: { displayVersion: "4.1.13", build: "269602", bundleID: "com.tencent.xinWeChat" } };
}

test("absolute executable detection is independent of PATH", async () => {
  const dir = await mkdtemp(join(tmpdir(), "wct-path-"));
  try {
    const brew = join(dir, "brew"); await writeFile(brew, "#!/bin/sh\nexit 0\n");
    assert.equal(findExecutable([brew]), null);
    await chmod(brew, 0o755);
    assert.equal(findExecutable([brew]), brew);
    assert.equal(findExecutable([dir]), null);
  } finally { await rm(dir, { recursive: true }); }
});

test("CLI installation and contact capability remain distinct", () => {
  const result = parseDiagnosis(JSON.stringify(report()));
  assert.equal(result.cliVersion, "2.1.0-dev");
  assert.equal(result.contactsBridgeAvailable, false);
  assert.equal(result.pendingWrites, 2);
});

test("update diagnosis defaults safely for older CLI and validates new fields", () => {
  const legacy = parseDiagnosis(JSON.stringify(report()));
  assert.equal(legacy.distribution, "unknown");
  assert.deepEqual(legacy.automaticUpdates, { status: "unsupported", independentlyBlocked: false });
  const current = { ...report(), distribution: "appStore", automaticUpdates: { status: "managedByAppStore", independentlyBlocked: false } };
  assert.equal(parseDiagnosis(JSON.stringify(current)).automaticUpdates.status, "managedByAppStore");
  for (const invalid of [
    { ...current, distribution: "website" },
    { ...current, automaticUpdates: { status: "blocked", independentlyBlocked: true } },
    { ...current, automaticUpdates: { status: "managedByAppStore", independentlyBlocked: "false" } },
    { ...current, distribution: "unknown" },
    { ...current, automaticUpdates: undefined },
    { ...current, distribution: ["appStore"] },
    { ...report(), distribution: null },
    { ...report(), automaticUpdates: null },
  ]) assert.throws(() => parseDiagnosis(JSON.stringify(invalid)));
});

test("reject wrong protocol, HTML and incomplete or malformed responses", () => {
  for (const value of ["<html>another server</html>", "{}", JSON.stringify({ ...report(), schemaVersion: 2 }),
    JSON.stringify({ ...report(), contactsBridgeAvailable: "yes" }), JSON.stringify({ ...report(), pendingWrites: -1 }),
    JSON.stringify({ ...report(), app: { build: "269602" } })]) {
    assert.throws(() => parseDiagnosis(value));
  }
});

test("read actual CLI stdout using a literal executable path with spaces", async () => {
  const dir = await mkdtemp(join(tmpdir(), "wct-cli-"));
  try {
    const cli = join(dir, "fake CLI $(echo literal)");
    await writeFile(cli, "#!/bin/sh\n[ \"$1\" = doctor ] && [ \"$2\" = --json ] || exit 64\nprintf '%s' '" + JSON.stringify(report()) + "'\n");
    await chmod(cli, 0o755);
    assert.equal((await readDiagnosis(cli)).app?.build, "269602");
    await writeFile(cli, "#!/bin/sh\nprintf '%s' '" + JSON.stringify({ ...report(), patchState: "error", errors: ["Missing app"] }) + "'\nexit 1\n");
    assert.deepEqual((await readDiagnosis(cli)).errors, ["Missing app"]);
    await writeFile(cli, "#!/bin/sh\necho unsupported doctor >&2\nexit 64\n");
    await assert.rejects(readDiagnosis(cli), /本分支/);
    await assert.rejects(readDiagnosis("relative/wechattweak"), /绝对路径/);
  } finally { await rm(dir, { recursive: true }); }
});
