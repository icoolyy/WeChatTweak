// Derived from upstream-wechat; upstream MIT notice is in LICENSE.upstream.
import { Action, ActionPanel, closeMainWindow, environment, Icon, List, showToast, Toast } from "@raycast/api";
import { useRef, useState } from "react";
import path from "node:path";
import { storageService } from "../services/runtime.ts";
import type { ContactService } from "../services/contactService.ts";
import type { SearchResult } from "../types/index.ts";

interface Props { searchResult: SearchResult; isPinned: boolean; service: ContactService;
  onTogglePin: () => Promise<void>; onClearHistory: () => Promise<void>; onRefresh: () => void }
export function SearchListItem({ searchResult, isPinned, service, onTogglePin, onClearHistory, onRefresh }: Props) {
  const [opening, setOpening] = useState(false);
  const inFlight = useRef(false);
  async function startWeChat() {
    if (inFlight.current) return;
    inFlight.current = true; setOpening(true);
    const toast = await showToast({ style: Toast.Style.Animated, title: "正在打开微信会话" });
    try {
      const result = await service.startChat(searchResult, storageService);
      toast.style = Toast.Style.Success; toast.title = result.historySaved ? "微信已选中会话" : "会话已打开，但历史记录未保存";
      await closeMainWindow({ clearRootSearch: true });
    } catch (error) {
      toast.style = Toast.Style.Failure; toast.title = "打开微信会话失败";
      toast.message = error instanceof Error ? error.message : String(error);
    } finally { inFlight.current = false; setOpening(false); }
  }
  return <List.Item title={searchResult.title || searchResult.subtitle || searchResult.arg} subtitle={searchResult.subtitle}
      accessories={[{ text: searchResult.arg, icon: isPinned ? Icon.Pin : undefined }]}
      icon={path.join(environment.assetsPath, "avatar.png")} actions={<ActionPanel>
        <ActionPanel.Section>
          <Action icon={Icon.Message} title={opening ? "正在打开会话" : "打开微信会话"} onAction={startWeChat} />
          <Action.CopyToClipboard icon={Icon.Clipboard} title="复制微信号" content={searchResult.arg} shortcut={{ modifiers: ["cmd"], key: "c" }} />
          <Action icon={isPinned ? Icon.PinDisabled : Icon.Pin} title={isPinned ? "取消置顶" : "置顶联系人"}
            onAction={onTogglePin} shortcut={{ modifiers: ["cmd", "shift"], key: "p" }} />
          <Action icon={Icon.Trash} title="清除最近联系人" onAction={onClearHistory} shortcut={{ modifiers: ["cmd", "shift"], key: "x" }} />
          <Action icon={Icon.ArrowClockwise} title="重新搜索" onAction={onRefresh} shortcut={{ modifiers: ["cmd"], key: "r" }} />
        </ActionPanel.Section>
      </ActionPanel>} />;
}
