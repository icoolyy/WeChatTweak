import { test } from "node:test";
import assert from "node:assert/strict";
import { ContactService } from "./services/contactService.ts";

test("upstream rows accept missing avatars and retain the search epoch", async () => {
  const service = new ContactService({
    search: async () => ({ session: "epoch1", source: "loadedContacts", items: [
      { id: "one", arg: "one", title: "文件传输助手" }, { id: "two", arg: "two", title: "测试" }] }),
    open: async () => {},
  });
  const result = await service.searchContacts("文件传输助手", new AbortController().signal);
  assert.equal(result.items[0].arg, "one"); assert.equal(result.items[0].session, "epoch1");
  assert.equal(result.items[0].subtitle, "");
});
test("failed chat confirmation cannot write a recent contact", async () => {
  let saved = false, failed = true;
  const service = new ContactService({ search: async () => ({ session: "epoch1", source: "loadedContacts", items: [] }),
    open: async (id, epoch) => { assert.equal(id, "one"); assert.equal(epoch, "epoch1"); if (failed) throw Error("not confirmed"); } });
  const item = { id: "one", arg: "one", title: "One", subtitle: "", session: "epoch1" };
  const history = { addRecent: async () => { saved = true; } };
  await assert.rejects(service.startChat(item, history), /not confirmed/); assert.equal(saved, false);
  failed = false; await service.startChat(item, history); assert.equal(saved, true);
});
test("a history write failure does not misreport a confirmed chat as failed", async () => {
  const service = new ContactService({ search: async () => ({ session: "epoch1", source: "loadedContacts", items: [] }), open: async () => {} });
  const result = await service.startChat({ id: "one", arg: "one", title: "One", subtitle: "", session: "epoch1" },
    { addRecent: async () => { throw Error("storage unavailable"); } });
  assert.deepEqual(result, { historySaved: false });
});

test("contact avatars belong to the latest successful search session", async () => {
  let epoch = "one";
  const service = new ContactService({ search: async () => ({ session: epoch, source: "loadedContacts", items: [] }), open: async () => {}, avatar: async () => "image" });
  const signal = new AbortController().signal;
  await service.searchContacts("", signal);
  const contact = { id: "id", arg: "id", title: "Name", subtitle: "", session: "one" };
  assert.equal(await service.avatar(contact, signal), "image");
  epoch = "two"; await service.searchContacts("", signal);
  assert.equal(await service.avatar(contact, signal), undefined);
});
