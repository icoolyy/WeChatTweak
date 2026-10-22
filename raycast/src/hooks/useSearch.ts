// Adapted from upstream-wechat useSearch: cancel stale requests and scope saved rows.
import { Alert, confirmAlert, showToast, Toast } from "@raycast/api";
import { useCallback, useEffect, useMemo, useState } from "react";
import { createContactService, storageService } from "../services/runtime.ts";
import type { SearchResult, SearchState } from "../types/index.ts";

export function useSearch() {
  const service = useMemo(createContactService, []);
  const [query, search] = useState("");
  const [refresh, setRefresh] = useState(0);
  const [state, setState] = useState<SearchState>({ items: [], recentContacts: [], pinnedContacts: [], isLoading: true, searchText: "" });
  useEffect(() => {
    const controller = new AbortController(); let active = true;
    setState({ items: [], recentContacts: [], pinnedContacts: [], isLoading: true, searchText: query });
    const timer = setTimeout(() => {
      void service.searchContacts(query, controller.signal).then(async (result) => {
        if (!active) return;
        const saved = await storageService.activate(result.session, controller.signal);
        if (active) setState({ items: result.items, session: result.session, recentContacts: saved.recent,
          pinnedContacts: saved.pinned, isLoading: false, searchText: query });
      }).catch((error: unknown) => {
        if (active) setState({ items: [], recentContacts: [], pinnedContacts: [], isLoading: false, searchText: query,
          error: error instanceof Error ? error.message : String(error) });
      });
    }, 150);
    return () => { active = false; clearTimeout(timer); controller.abort(); };
  }, [query, refresh, service]);
  const reload = useCallback(() => setRefresh((value) => value + 1), []);
  const togglePin = useCallback(async (contact: SearchResult) => {
    try {
      const saved = await storageService.togglePin(contact);
      setState((current) => current.session === contact.session ? { ...current, pinnedContacts: saved.pinned } : current);
    } catch (error) { await showToast({ style: Toast.Style.Failure, title: "置顶操作失败", message: String(error) }); }
  }, []);
  const clearRecentContacts = useCallback(async () => {
    const session = state.session;
    if (!session || !await confirmAlert({ title: "清除最近联系人", message: "仅清除当前会话的搜索历史，保留置顶联系人。",
      primaryAction: { title: "清除", style: Alert.ActionStyle.Destructive }, dismissAction: { title: "取消" } })) return;
    try {
      await storageService.clearRecent(session);
      setState((current) => current.session === session ? { ...current, recentContacts: [] } : current);
      await showToast({ style: Toast.Style.Success, title: "已清除最近联系人" });
    } catch (error) { await showToast({ style: Toast.Style.Failure, title: "清除失败", message: String(error) }); }
  }, [state.session]);
  return { state, search, reload, togglePin, clearRecentContacts, service };
}
