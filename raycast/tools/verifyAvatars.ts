// Live acceptance only: requires a logged-in supported WeChat bridge.
// Fetches avatars for the current search results; prints counts, never contacts,
// source URLs, credentials, or image contents. No files are written.
import { BridgeClient } from "../src/bridge.ts";
import { AvatarLoader } from "../src/services/avatarLoader.ts";

const bridge = new BridgeClient();
const health = await bridge.health();
if (health.state !== "ready" || !health.capabilities.avatars) {
  throw new Error("Log in to WeChat with the current avatar-enabled bridge first");
}
const result = await bridge.search("");
let errors = 0, completed = 0, available = 0;
const loader = new AvatarLoader(async (id, epoch, signal) => {
  try { return await bridge.avatar(id, epoch, signal); }
  catch { ++errors; return undefined; }
});
loader.activate(result.session);
const begin = Date.now();
await Promise.all(result.items.map(async (contact) => {
  if (await loader.load(contact.id, result.session, new AbortController().signal)) ++available;
  if (++completed % 20 === 0) console.log(JSON.stringify({ completed, available, errors }));
}));
console.log(JSON.stringify({ total: result.items.length, available, missing: result.items.length - available, errors, elapsedMs: Date.now() - begin }));
if (errors || !available) process.exitCode = 1;
