import { test } from "node:test";
import assert from "node:assert/strict";
import { AvatarLoader } from "./services/avatarLoader.ts";

test("avatar loading limits concurrency, caches only the current epoch and discards cancelled results", async () => {
  let active = 0, maximum = 0, calls = 0;
  const release: (() => void)[] = [];
  const loader = new AvatarLoader(async (id) => {
    ++calls; maximum = Math.max(maximum, ++active);
    await new Promise<void>((resolve) => release.push(resolve)); --active;
    return `image-${id}`;
  });
  loader.activate("one");
  const signal = new AbortController();
  const first = Array.from({ length: 6 }, (_, i) => loader.load(String(i), "one", signal.signal));
  await new Promise((resolve) => setImmediate(resolve)); assert.equal(maximum, 4);
  signal.abort(); loader.activate("two");
  release.splice(0).forEach((run) => run());
  assert.deepEqual(await Promise.all(first), Array(6).fill(undefined));
  assert.equal(await loader.load("0", "one", new AbortController().signal), undefined);
  const next = loader.load("0", "two", new AbortController().signal);
  await new Promise((resolve) => setImmediate(resolve)); release.splice(0).forEach((run) => run());
  assert.equal(await next, "image-0");
  const before = calls;
  assert.equal(await loader.load("0", "two", new AbortController().signal), "image-0"); assert.equal(calls, before);
});

test("avatar failures fall back and do not poison later retries", async () => {
  let failing = true;
  const loader = new AvatarLoader(async () => { if (failing) throw Error("not ready"); return "image"; });
  loader.activate("one");
  assert.equal(await loader.load("id", "one", new AbortController().signal), undefined);
  failing = false;
  assert.equal(await loader.load("id", "one", new AbortController().signal), "image");
});

test("a newly arriving request cannot steal a slot reserved for a queued avatar", async () => {
  let active = 0, maximum = 0;
  const release: (() => void)[] = [];
  const loader = new AvatarLoader(() => {
    maximum = Math.max(maximum, ++active);
    return new Promise<string>((resolve) => release.push(() => { --active; resolve("image"); }));
  });
  loader.activate("one"); const signal = new AbortController().signal;
  const pending = Array.from({ length: 5 }, (_, i) => loader.load(String(i), "one", signal));
  release.shift()!();
  queueMicrotask(() => { pending.push(loader.load("interloper", "one", signal)); });
  await new Promise((resolve) => setImmediate(resolve));
  const measured = maximum;
  while (release.length) { release.splice(0).forEach((run) => run()); await new Promise((resolve) => setImmediate(resolve)); }
  await Promise.all(pending); assert.equal(measured, 4);
});

test("queued avatars from an old epoch cannot starve the new epoch", async () => {
  const release: (() => void)[] = []; let newStarted = false;
  const loader = new AvatarLoader((_id, epoch) => {
    if (epoch === "two") newStarted = true;
    return new Promise<string>((resolve) => release.push(() => resolve("image")));
  });
  loader.activate("one"); const signal = new AbortController().signal;
  const old = Array.from({ length: 9 }, (_, i) => loader.load(String(i), "one", signal));
  loader.activate("two"); const next = loader.load("new", "two", signal);
  release.splice(0).forEach((run) => run());
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(newStarted, true);
  release.splice(0).forEach((run) => run());
  await Promise.all([...old, next]);
});
