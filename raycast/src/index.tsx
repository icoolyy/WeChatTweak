// Derived from upstream-wechat index.tsx; UI sections retained, backend replaced.
import { Action, ActionPanel, Icon, launchCommand, LaunchType, List } from "@raycast/api";
import { SearchListItem } from "./components/searchListltem.tsx";
import { useSearch } from "./hooks/useSearch.ts";
import type { SearchResult } from "./types/index.ts";

export default function Command() {
  const { state, search, reload, togglePin, clearRecentContacts, service } = useSearch();
  const pinnedIDs = new Set(state.pinnedContacts.map((item) => item.id));
  const pinned = state.searchText ? state.items.filter((item) => pinnedIDs.has(item.id)) : state.pinnedContacts;
  const recent = state.searchText ? [] : state.recentContacts.filter((item) => !pinnedIDs.has(item.id));
  const shown = new Set([...pinned, ...recent].map((item) => item.id));
  const items = state.items.filter((item) => !shown.has(item.id));
  const row = (item: SearchResult, isPinned: boolean) => <SearchListItem key={item.id} searchResult={item} isPinned={isPinned}
    service={service} onTogglePin={() => togglePin(item)} onClearHistory={clearRecentContacts} onRefresh={reload} />;
  const actions = <ActionPanel>
    <Action title="重试搜索" icon={Icon.ArrowClockwise} onAction={reload} />
    <Action title="打开 WeChatTweak 管理" icon={Icon.Gear} onAction={() => launchCommand({ name: "manageTweak", type: LaunchType.UserInitiated })} />
  </ActionPanel>;
  return <List isLoading={state.isLoading} filtering={false} onSearchTextChange={search}
    searchBarPlaceholder="搜索微信联系人：中文、备注、拼音">
    {state.error ? <List.EmptyView title="微信搜索暂不可用" description={state.error} icon={Icon.Warning} actions={actions} /> : <>
      {pinned.length > 0 && <List.Section title="置顶联系人" subtitle={String(pinned.length)}>{pinned.map((item) => row(item, true))}</List.Section>}
      {recent.length > 0 && <List.Section title="最近联系人" subtitle={String(recent.length)}>{recent.map((item) => row(item, false))}</List.Section>}
      <List.Section title="微信已加载的联系人" subtitle="每次搜索最多100条；未加载到缓存的联系人不显示">{items.map((item) => row(item, false))}</List.Section>
      {!state.isLoading && !pinned.length && !recent.length && !items.length && <List.EmptyView title="没有匹配的联系人" description="尝试昵称、备注或拼音；搜索范围为微信已加载的缓存。" actions={actions} />}
    </>}
  </List>;
}
