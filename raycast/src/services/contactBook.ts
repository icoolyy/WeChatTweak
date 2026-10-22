import type { SearchResult } from "../types/index.ts";

interface Store { get(key: string): Promise<unknown>; set(key: string, value: string): Promise<void> }
export interface SavedContacts { pinned: SearchResult[]; recent: SearchResult[] }
const KEY = "wechat_verified_contacts_v1";
const empty = (): SavedContacts => ({ pinned: [], recent: [] });
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === "object" && !Array.isArray(value); }
function contacts(value: unknown, session: string, limit: number): SearchResult[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value.filter((item): item is SearchResult => {
    if (!object(item) || typeof item.id !== "string" || !item.id || Buffer.byteLength(item.id) > 1024 || item.arg !== item.id ||
      item.session !== session || typeof item.title !== "string" || item.title.length > 4096 ||
      typeof item.subtitle !== "string" || item.subtitle.length > 4096 || seen.has(item.id)) return false;
    seen.add(item.id); return true;
  }).slice(0, limit).map(({ id, arg, title, subtitle, session }) => ({ id, arg, title, subtitle, session }));
}
export class ContactBook {
  private store: Store;
  private queue: Promise<unknown> = Promise.resolve();
  constructor(store: Store) { this.store = store; }
  private async stored(): Promise<{ session: string; contacts: SavedContacts } | undefined> {
    const raw = await this.store.get(KEY);
    if (typeof raw !== "string" || raw.length > 2 * 1024 * 1024) return;
    try {
      const value: unknown = JSON.parse(raw);
      if (!object(value) || typeof value.session !== "string" || !value.session || value.session.length > 128) return;
      return { session: value.session, contacts: { pinned: contacts(value.pinned, value.session, 100), recent: contacts(value.recent, value.session, 10) } };
    } catch { return; }
  }
  async read(session: string): Promise<SavedContacts> {
    await this.queue; const stored = await this.stored(); return stored?.session === session ? stored.contacts : empty();
  }
  // Only the successful current search may activate a new verified epoch.
  // Local actions never implicitly replace the book belonging to another epoch.
  activate(session: string, signal?: AbortSignal): Promise<SavedContacts> {
    const next = this.queue.then(async () => {
      if (!session || session.length > 128) throw new Error("无效的微信会话");
      const stored = await this.stored();
      if (signal?.aborted) throw new DOMException("Search aborted", "AbortError");
      if (stored?.session === session) return stored.contacts;
      const saved = empty(); await this.store.set(KEY, JSON.stringify({ session, ...saved })); return saved;
    });
    this.queue = next.catch(() => {}); return next;
  }
  private update(session: string, change: (current: SavedContacts) => void): Promise<SavedContacts> {
    if (!session || session.length > 128) return Promise.reject(new Error("无效的微信会话"));
    const next = this.queue.then(async () => {
      const stored = await this.stored();
      if (stored && stored.session !== session) throw new Error("微信会话已变化，请重新搜索");
      const current = stored?.contacts ?? empty(); change(current);
      const saved = { pinned: contacts(current.pinned, session, 100), recent: contacts(current.recent, session, 10) };
      await this.store.set(KEY, JSON.stringify({ session, ...saved })); return saved;
    });
    this.queue = next.catch(() => {}); return next;
  }
  addRecent(contact: SearchResult): Promise<SavedContacts> {
    return this.update(contact.session, (saved) => { saved.recent = [contact, ...saved.recent.filter((item) => item.id !== contact.id)]; });
  }
  togglePin(contact: SearchResult): Promise<SavedContacts> {
    return this.update(contact.session, (saved) => {
      if (saved.pinned.some((item) => item.id === contact.id)) saved.pinned = saved.pinned.filter((item) => item.id !== contact.id);
      else { if (saved.pinned.length >= 100) throw new Error("最多置顶 100 个联系人"); saved.pinned.push(contact); }
    });
  }
  clearRecent(session: string): Promise<SavedContacts> { return this.update(session, (saved) => { saved.recent = []; }); }
}
