import { test } from "node:test";
import assert from "node:assert/strict";
import { ManagementService } from "./services/management.ts";

test("manager uses this CLI protocol and cancellation never executes a command", async () => {
  const calls: string[][] = [];
  const manager = new ManagementService({ cliPath: "/tmp/CLI with spaces", appPath: "/Applications/WeChat.app", backupPath: "/tmp/Backup with spaces" },
    async (cli, args) => { calls.push([cli, ...args]); return "done"; });
  await manager.install(async () => false); await manager.restore(async () => false);
  assert.equal(calls.length, 0);
  await manager.preflight();
  assert.deepEqual(calls.pop(), ["/tmp/CLI with spaces", "patch", "--app", "/Applications/WeChat.app", "--install-bridge", "--dry-run"]);
  await manager.install(async () => true);
  assert.deepEqual(calls.pop(), ["/tmp/CLI with spaces", "patch", "--app", "/Applications/WeChat.app", "--install-bridge"]);
  await manager.restore(async () => true);
  assert.deepEqual(calls.pop(), ["/tmp/CLI with spaces", "restore", "--app", "/Applications/WeChat.app", "--backup", "/tmp/Backup with spaces"]);
});
test("restore rejects missing or relative backup paths before execution", async () => {
  let called = false;
  const manager = new ManagementService({ cliPath: "/tmp/cli", appPath: "/Applications/WeChat.app", backupPath: "relative" },
    async () => { called = true; return ""; });
  await assert.rejects(manager.restore(async () => true), /备份.*绝对路径/); assert.equal(called, false);
});
