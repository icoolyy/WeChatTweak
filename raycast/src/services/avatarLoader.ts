type FetchAvatar = (id: string, session: string, signal: AbortSignal) => Promise<string | undefined>;

// Command-local, bounded memory only. Nothing is reused after an observed epoch change.
export class AvatarLoader {
  private fetch: FetchAvatar;
  private session = "";
  private generation = 0;
  private cache = new Map<string, string>();
  private bytes = 0;
  private active = 0;
  private waiting: ((granted: boolean) => void)[] = [];
  constructor(fetch: FetchAvatar) { this.fetch = fetch; }
  activate(session: string) {
    if (session === this.session) return;
    this.session = session; ++this.generation; this.cache.clear(); this.bytes = 0;
    [...this.waiting].forEach((wake) => wake(false));
  }
  async load(id: string, session: string, signal: AbortSignal): Promise<string | undefined> {
    const generation = this.generation;
    const current = () => !signal.aborted && session === this.session && generation === this.generation;
    if (!current()) return undefined;
    const cached = this.cache.get(id);
    if (cached) { this.cache.delete(id); this.cache.set(id, cached); return cached; }
    if (this.active >= 4) {
      if (this.waiting.length >= 128) return undefined;
      const acquired = await new Promise<boolean>((resolve) => {
        const abort = () => wake(false);
        const wake = (granted: boolean) => {
          signal.removeEventListener("abort", abort);
          const index = this.waiting.indexOf(wake); if (index >= 0) this.waiting.splice(index, 1);
          if (granted) ++this.active; // Reserve synchronously before waking the continuation.
          resolve(granted);
        };
        this.waiting.push(wake); signal.addEventListener("abort", abort, { once: true });
      });
      if (!acquired) return undefined;
    } else ++this.active;
    if (!current()) { this.release(); return undefined; }
    try {
      const value = await this.fetch(id, session, signal);
      if (!current() || !value) return undefined;
      const old = this.cache.get(id); if (old) this.bytes -= old.length;
      this.cache.delete(id); this.cache.set(id, value); this.bytes += value.length;
      while (this.cache.size > 64 || this.bytes > 4 * 1024 * 1024) {
        const oldest = this.cache.keys().next().value;
        if (oldest === undefined) break;
        this.bytes -= this.cache.get(oldest)!.length; this.cache.delete(oldest);
      }
      return value;
    } catch { return undefined; }
    finally { this.release(); }
  }
  private release() {
    --this.active;
    this.waiting[0]?.(true);
  }
}
