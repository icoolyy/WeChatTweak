import type { BridgeClient } from "../bridge.ts";
import type { SearchResult } from "../types/index.ts";

export class ContactService {
  private bridge: Pick<BridgeClient, "search" | "open">;
  constructor(bridge: Pick<BridgeClient, "search" | "open">) { this.bridge = bridge; }
  async searchContacts(keyword: string, signal: AbortSignal): Promise<{ items: SearchResult[]; session: string }> {
    const result = await this.bridge.search(keyword, signal);
    const items = result.items.map((item) => ({ ...item, subtitle: item.subtitle ?? "", session: result.session }));
    if (keyword) {
      const query = keyword.toLocaleLowerCase();
      const rank = (item: SearchResult) => {
        const values = [item.title, item.subtitle].map((text) => text.toLocaleLowerCase());
        return values.some((value) => value === query) ? 0 : values.some((value) => value.startsWith(query)) ? 1 : 2;
      };
      items.sort((a, b) => rank(a) - rank(b));
    }
    return { items, session: result.session };
  }
  async startChat(contact: SearchResult, history: { addRecent(contact: SearchResult): Promise<unknown> }): Promise<{ historySaved: boolean }> {
    await this.bridge.open(contact.arg, contact.session);
    try { await history.addRecent(contact); return { historySaved: true }; }
    catch { return { historySaved: false }; }
  }
}
