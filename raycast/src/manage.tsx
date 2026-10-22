import { Action, ActionPanel, Color, getPreferenceValues, Icon, List } from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import { homebrewPath, readDiagnosis } from "./diagnostics.ts";
import type { Diagnosis } from "./diagnostics.ts";

const patchLabels: Record<string, string> = {
  ready: "预检通过，尚未应用", applied: "字节补丁已应用", partiallyApplied: "部分字节已应用",
  unsupportedBuild: "此构建没有补丁配置", error: "检查失败",
};

export default function Manage() {
  const { cliPath } = getPreferenceValues<{ cliPath: string }>();
  const [report, setReport] = useState<Diagnosis>();
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(true);
  const refresh = useCallback(async () => {
    setLoading(true); setError(undefined);
    try { setReport(await readDiagnosis(cliPath)); }
    catch (error) { setReport(undefined); setError(String(error)); }
    finally { setLoading(false); }
  }, [cliPath]);
  useEffect(() => { void refresh(); }, [refresh]);
  const brew = homebrewPath();
  const actions = (
    <ActionPanel>
      <Action title="刷新状态" icon={Icon.ArrowClockwise} onAction={refresh} shortcut={{ modifiers: ["cmd"], key: "r" }} />
      {report && <Action.CopyToClipboard title="复制诊断结果" content={JSON.stringify(report, null, 2)} />}
      <Action.ShowInFinder title="在 Finder 中显示 CLI" path={cliPath} />
    </ActionPanel>
  );
  return (
    <List isLoading={loading} searchBarPlaceholder="微信兼容性诊断">
      <List.Section title="安装状态">
        <List.Item title="Homebrew" subtitle={brew ?? "未找到；此诊断工具可直接使用本地 CLI"} icon={brew ? Icon.CheckCircle : Icon.Info} actions={actions} />
        <List.Item title="WeChatTweak CLI" subtitle={report?.cliVersion ?? error ?? "检查中"} icon={report ? Icon.CheckCircle : Icon.Info} actions={actions} />
        {report?.app && <List.Item title="微信" subtitle={`${report.app.displayVersion} (${report.app.build})`} icon={Icon.Message} actions={actions} />}
      </List.Section>
      {report && <List.Section title="独立能力状态">
        <List.Item title="二进制补丁" subtitle={patchLabels[report.patchState] ?? report.patchState} icon={Icon.Hammer} actions={actions} />
        <List.Item title="配置包含的功能" subtitle={report.configuredFeatures.join("、") || "无"} actions={actions} />
        <List.Item title="联系人搜索与打开聊天" subtitle={report.contactsBridgeAvailable ? "CLI 报告可用；需配套桥接客户端" : "尚未提供微信 4 的原生适配器"} icon={{ source: Icon.Info, tintColor: Color.Orange }} actions={actions} />
        <List.Item title="验证范围" subtitle="预检与补丁字节状态不代表已完成真实消息和会话验收" actions={actions} />
      </List.Section>}
      {report?.errors.map((message, index) => <List.Item key={index} title="诊断错误" subtitle={message} icon={Icon.Warning} actions={actions} />)}
    </List>
  );
}
