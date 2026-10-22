import { test } from "node:test";
import assert from "node:assert/strict";
import { ContactBook } from "./services/contactBook.ts";

function fixture() {
  const values = new Map<string, string>();
  return { values, book: new ContactBook({ get: async (key: string) => values.get(key),
    set: async (key: string, value: string) => { values.set(key, value); } }) };
}
const contact = (id: string, session = "epoch1") => ({ id, arg: id, title: id, subtitle: "", session });

test("recent and pinned contacts are isolated by verified session", async () => {
  const { book } = fixture();
  await book.togglePin(contact("builtin")); await book.addRecent(contact("builtin"));
  assert.equal((await book.read("epoch1")).pinned.length, 1);
  assert.deepEqual(await book.read("epoch2"), { pinned: [], recent: [] });
  await book.activate("epoch2");
  await book.addRecent(contact("other", "epoch2"));
  assert.equal((await book.read("epoch2")).recent[0].id, "other");
  assert.deepEqual(await book.read("epoch1"), { pinned: [], recent: [] });
});
test("concurrent history updates are deduplicated, bounded and clear preserves pins", async () => {
  const { book } = fixture();
  await Promise.all(Array.from({ length: 12 }, (_, i) => book.addRecent(contact(`id${i}`))));
  await book.addRecent(contact("id5"));
  const stored = await book.read("epoch1");
  assert.equal(stored.recent.length, 10); assert.equal(stored.recent[0].id, "id5");
  assert.equal(new Set(stored.recent.map((item) => item.id)).size, 10);
  await book.togglePin(contact("pin")); await book.clearRecent("epoch1");
  assert.deepEqual((await book.read("epoch1")).recent, []);
  assert.equal((await book.read("epoch1")).pinned[0].id, "pin");
  await book.togglePin(contact("pin")); assert.equal((await book.read("epoch1")).pinned.length, 0);
});
test("malformed storage and legacy entries without an epoch are never reused", async () => {
  const { values, book } = fixture();
  await book.addRecent(contact("safe"));
  const key = [...values.keys()][0];
  values.set(key, JSON.stringify({ session: "epoch1", recent: [{ arg: "old", title: "old" }], pinned: [] }));
  assert.deepEqual(await book.read("epoch1"), { pinned: [], recent: [] });
  values.set(key, "bad json"); assert.deepEqual(await book.read("epoch1"), { pinned: [], recent: [] });
});
test("a delayed old-session mutation cannot erase the newer session's saved contacts", async () => {
  const { book } = fixture();
  await book.togglePin(contact("current", "epoch2")); await book.addRecent(contact("current", "epoch2"));
  await assert.rejects(book.clearRecent("epoch1"), /会话已变化/);
  await assert.rejects(book.addRecent(contact("old", "epoch1")), /会话已变化/);
  assert.equal((await book.read("epoch2")).pinned[0].id, "current");
  assert.equal((await book.read("epoch2")).recent[0].id, "current");
});
test("an aborted old search cannot activate or clear the current session", async () => {
  const { book } = fixture();
  await book.togglePin(contact("current", "epoch2"));
  const controller = new AbortController(); controller.abort();
  await assert.rejects(book.activate("epoch1", controller.signal), /aborted/);
  assert.equal((await book.read("epoch2")).pinned[0].id, "current");
});
