import { Action, ActionPanel, getPreferenceValues, Icon, List, showToast, Toast, closeMainWindow } from "@raycast/api";
import { useEffect, useMemo, useState } from "react";
import { BridgeClient } from "./bridge.ts";
import type { SearchResult } from "./bridge.ts";

export default function Search() {
  const { credentialPath } = getPreferenceValues<{ credentialPath?: string }>();
  const client = useMemo(() => new BridgeClient(credentialPath), [credentialPath]);
  const [keyword, setKeyword] = useState("");
  const [result, setResult] = useState<SearchResult>();
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true); setResult(undefined); setError(undefined);
    const timer = setTimeout(() => {
      void client.search(keyword, controller.signal).then((value) => {
        if (!controller.signal.aborted) setResult(value);
      }).catch((error: unknown) => {
        if (!controller.signal.aborted) setError(error instanceof Error ? error.message : String(error));
      }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    }, 200);
    return () => { clearTimeout(timer); controller.abort(); };
  }, [client, keyword]);
  async function open(id: string, session: string) {
    const toast = await showToast({ style: Toast.Style.Animated, title: "正在打开微信会话" });
    try {
      await client.open(id, session);
      toast.style = Toast.Style.Success; toast.title = "微信已选中会话";
      await closeMainWindow();
    } catch (error) {
      toast.style = Toast.Style.Failure; toast.title = "打开会话失败";
      toast.message = error instanceof Error ? error.message : String(error);
    }
  }
  return <List isLoading={loading} filtering={false} onSearchTextChange={setKeyword}
    searchBarPlaceholder="搜索微信已加载的联系人：昵称、备注、拼音">
    {error ? <List.EmptyView icon={Icon.Warning} title="微信搜索暂不可用" description={error} /> :
      <List.Section title="微信已加载的联系人" subtitle="最多 100 条；不包含尚未加载到缓存的联系人">
        {result?.items.map((item) => <List.Item key={item.id} title={item.title} subtitle={item.subtitle}
          icon={Icon.Person} actions={<ActionPanel><Action title="打开微信会话" icon={Icon.Message}
            onAction={() => open(item.id, result.session)} /></ActionPanel>} />)}
      </List.Section>}
  </List>;
}
