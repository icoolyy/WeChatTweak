import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { createHmac } from "node:crypto";
import { mkdtemp, writeFile, chmod, symlink, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BridgeClient } from "./bridge.ts";

test("bridge verifies identity before bearer and confirms epoch-bound opening", async () => {
  const directory = await mkdtemp(join(tmpdir(), "wct-client-"));
  const path = join(directory, "token"), token = "a".repeat(64);
  await writeFile(path, token, { mode: 0o600 });
  let hostile = false, stale = false, unconfirmed = false, bearerRequests = 0;
  let mode = "normal";
  const server = createServer((req, res) => {
    const url = new URL(req.url!, "http://127.0.0.1");
    res.setHeader("Content-Type", "application/json");
    if (url.pathname === "/health") {
      assert.equal(req.headers.authorization, undefined);
      if (mode === "html") { res.setHeader("Content-Type", "text/html"); res.end("<html>unrelated service</html>"); return; }
      res.end(JSON.stringify({ service: "WeChatTweak", protocol: mode === "incompatible" ? 2 : 1, state: "ready", build: "269602",
        session: stale ? "epoch2" : "epoch1", contactsSource: "loadedContacts",
        capabilities: { contacts: true, openChat: true, ...(mode === "badCapability" ? { persistentContacts: "yes" } : {}) }, proof: hostile ? "0".repeat(64) :
          createHmac("sha256", token).update(`wechattweak-health-v1:${url.searchParams.get("challenge")}`).digest("hex") }));
      return;
    }
    bearerRequests++;
    assert.equal(req.headers.authorization, `Bearer ${token}`);
    if (mode === "unauthorized") {res.statusCode = 401; res.end(JSON.stringify({ error: { code: "unauthorized" } })); return;}
    if (url.pathname === "/wechat/search") {
      assert.equal(url.searchParams.get("keyword"), "文件传输助手");
      res.end(JSON.stringify({ ok: true, session: "epoch1", source: "loadedContacts",
        items: [{ id: "filehelper", arg: "filehelper", title: "文件传输助手" }] }));
    } else {
      assert.equal(url.searchParams.get("session"), "filehelper");
      assert.equal(url.searchParams.get("epoch"), "epoch1");
      res.end(JSON.stringify({ ok: true, confirmed: !unconfirmed }));
    }
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address !== "string");
  const client = new BridgeClient(path, address.port);
  try {
    const health = await client.health();
    for (const key of ["accountContext", "contactPagination", "persistentContacts", "avatars", "quicklinks", "fullContacts"] as const)
      assert.equal(health.capabilities[key], false);
    mode = "badCapability";
    await assert.rejects(client.health(), /协议或构建不兼容/);
    assert.equal(bearerRequests, 0);
    mode = "normal";
    const result = await client.search("文件传输助手");
    assert.equal(result.items[0].id, "filehelper");
    await client.open("filehelper", result.session);
    assert.equal(bearerRequests, 2);
    hostile = true;
    await assert.rejects(client.search("文件传输助手"), /身份校验失败/);
    assert.equal(bearerRequests, 2);
    hostile = false; stale = true;
    await assert.rejects(client.open("filehelper", result.session), /重新搜索/);
    assert.equal(bearerRequests, 2);
    stale = false; mode = "html";
    await assert.rejects(client.health(), /不是兼容/);
    mode = "incompatible";
    await assert.rejects(client.health(), /协议或构建不兼容/);
    assert.equal(bearerRequests, 2);
    mode = "unauthorized";
    await assert.rejects(client.search("文件传输助手"), /凭证不匹配/);
    mode = "normal";
    stale = false; unconfirmed = true;
    await assert.rejects(client.open("filehelper", result.session), /没有确认/);
    await chmod(path, 0o644);
    await assert.rejects(client.health(), /安全的桥接凭证/);
    await chmod(path, 0o600);
    const link = join(directory, "link"); await symlink(path, link);
    await assert.rejects(new BridgeClient(link, address.port).health(), /安全的桥接凭证/);
    const controller = new AbortController(); controller.abort();
    await assert.rejects(client.health(controller.signal), /abort/i);
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true });
  }
});
