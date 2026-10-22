// Derived from upstream-wechat manageTweak.tsx; uses this branch's CLI only.
import { Action, ActionPanel, Color, Detail, Icon, List, Toast, confirmAlert, open, openExtensionPreferences, showToast, useNavigation } from "@raycast/api";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { homebrewPath, readDiagnosis } from "./diagnostics.ts";
import type { Diagnosis } from "./diagnostics.ts";
import type { Health } from "./bridge.ts";
import { createBridge, preferences } from "./services/runtime.ts";
import { ManagementService } from "./services/management.ts";

const labels: Record<string, string> = { ready: "预检通过，待应用", applied: "字节补丁已应用", partiallyApplied: "部分字节已应用", unsupportedBuild: "未支持此构建", error: "检查失败" };
export default function ManageTweak() {
  const values = preferences();
  const { push } = useNavigation();
  const manager = useMemo(() => new ManagementService(values), [values.cliPath, values.appPath, values.backupPath]);
  const bridge = useMemo(createBridge, [values.credentialPath]);
  const [report, setReport] = useState<Diagnosis>();
  const [health, setHealth] = useState<Health>();
  const [cliError, setCLIError] = useState<string>();
  const [bridgeError, setBridgeError] = useState<string>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false); const inFlight = useRef(false);
  const refresh = useCallback(async () => {
    setLoading(true);
    const [cli, native] = await Promise.allSettled([readDiagnosis(values.cliPath, values.appPath, values.credentialPath), bridge.health()]);
    setReport(cli.status === "fulfilled" ? cli.value : undefined);
    setCLIError(cli.status === "rejected" ? String(cli.reason) : undefined);
    setHealth(native.status === "fulfilled" ? native.value : undefined);
    setBridgeError(native.status === "rejected" ? String(native.reason) : undefined);
    setLoading(false);
  }, [values.cliPath, values.appPath, values.credentialPath, bridge]);
  useEffect(() => { void refresh(); }, [refresh]);
  const detail = (title: string, output: string) => push(<Detail markdown={"# " + title + "\n\n```text\n" + output.replaceAll("```", "` ` `") + "\n```"} />);
  async function execute(kind: "preflight" | "install" | "restore") {
    if (inFlight.current) return;
    inFlight.current = true; setBusy(true);
    try {
      const output = kind === "preflight" ? await manager.preflight() : kind === "install" ? await manager.install(() => confirmAlert({
        title: "安装本分支补丁和桥接", message: `目标：${values.appPath}。请先正常退出全部微信。操作会整包备份、安装桥接并重新签名。`,
        primaryAction: { title: "安装" }, dismissAction: { title: "取消" },
      })) : await manager.restore(() => confirmAlert({
        title: "从完整备份恢复微信", message: `目标：${values.appPath}\n备份：${values.backupPath}\n请先退出全部微信；不同构建的备份会被拒绝。`,
        primaryAction: { title: "恢复" }, dismissAction: { title: "取消" },
      }));
      if (output === undefined) return;
      detail(kind === "preflight" ? "只读预检结果" : "操作结果（请保留备份路径）", output);
      await refresh();
    } catch (error) {
      await showToast({ style: Toast.Style.Failure, title: "操作未完成", message: String(error) });
      detail("操作未完成", String(error) + "\n\n如果是权限错误，可返回管理页面复制终端命令，在正常终端执行。不要从 Raycast 强制退出微信。");
    } finally { inFlight.current = false; setBusy(false); }
  }
  function command(kind: "patch" | "restore"): string | undefined { try { return manager.terminalCommand(kind); } catch { return undefined; } }
  const installCommand = command("patch"), restoreCommand = command("restore");
  const actions = <ActionPanel>
    <Action title="刷新状态" icon={Icon.ArrowClockwise} onAction={refresh} shortcut={{ modifiers: ["cmd"], key: "r" }} />
    <Action title="扩展偏好设置" icon={Icon.Gear} onAction={openExtensionPreferences} />
    {installCommand && <Action.CopyToClipboard title="复制终端安装命令" content={installCommand} />}
    {restoreCommand && <Action.CopyToClipboard title="复制终端恢复命令" content={restoreCommand} />}
  </ActionPanel>;
  const brew = homebrewPath();
  const hasApp = existsSync(values.appPath);
  const hasPayload = existsSync(join(values.appPath, "Contents/Frameworks/WeChatTweakBridge.dylib"));
  const healthy = health?.capabilities.contacts && health?.capabilities.openChat;
  return <List isLoading={loading || busy} searchBarPlaceholder="Manage WeChatTweak…">
    <List.Section title="环境">
      <List.Item title="Homebrew" subtitle={brew ?? "未检测到；使用本地 CLI 不依赖 Homebrew"} icon={Icon.Info} actions={actions} />
      <List.Item title="本项目 CLI" subtitle={report?.cliVersion ?? cliError ?? "检查中"} icon={report ? Icon.CheckCircle : Icon.Warning} actions={actions} />
    </List.Section>
    <List.Section title="微信与桥接状态">
      <List.Item title="WeChat Installation" subtitle={report?.app ? `${report.app.displayVersion} (${report.app.build}) · ${values.appPath}` : hasApp ? values.appPath : "应用不存在"} actions={actions} />
      <List.Item title="字节补丁" subtitle={report ? labels[report.patchState] ?? report.patchState : "无法检查"} actions={actions} />
      <List.Item title="桥接库文件" subtitle={hasPayload ? "目标应用中存在" : "目标应用中未找到"} actions={actions} />
      <List.Item title="运行中的桥接" subtitle={health ? `身份已验证 · ${health.state}` : bridgeError ?? "检查中"} actions={actions} />
      <List.Item title="联系人搜索和打开会话" subtitle={healthy ? "可用；搜索微信已加载的缓存" : "暂不可用，请先启动已安装桥接的微信并登录"}
        icon={{ source: healthy ? Icon.CheckCircle : Icon.Info, tintColor: healthy ? Color.Green : Color.Orange }} actions={actions} />
    </List.Section>
    <List.Section title="操作">
      <List.Item title="只读预检" subtitle="校验版本、补丁字节和桥接安装条件" icon={Icon.MagnifyingGlass} actions={<ActionPanel><Action title="执行只读预检" onAction={() => execute("preflight")} /></ActionPanel>} />
      <List.Item title="安装或更新 WeChatTweak" subtitle="使用本分支 patch --install-bridge" icon={Icon.Download} actions={<ActionPanel><Action title="安装或更新" onAction={() => execute("install")} />{installCommand && <Action.CopyToClipboard title="复制终端安装命令" content={installCommand} />}</ActionPanel>} />
      <List.Item title="恢复原微信" subtitle={values.backupPath || "请在偏好设置填写安装时打印的完整备份目录"} icon={Icon.ArrowCounterClockwise} actions={<ActionPanel><Action title="从备份恢复" onAction={() => execute("restore")} /><Action title="填写备份路径" onAction={openExtensionPreferences} /></ActionPanel>} />
      {hasApp && !health && <List.Item title="启动微信" icon={Icon.Play} actions={<ActionPanel><Action title="启动微信" onAction={() => open(values.appPath)} /></ActionPanel>} />}
    </List.Section>
    {report?.errors.map((message, i) => <List.Item key={i} title="诊断错误" subtitle={message} icon={Icon.Warning} actions={actions} />)}
    <List.Section title="说明">
      <List.Item title="安装目标和运行桥接分别检查" subtitle="临时副本运行时，原安装仍可能显示待应用；两者不是同一状态" actions={actions} />
      <List.Item title="能力范围" subtitle="每次搜索最多100条；防撤回、多开实际效果和主动账号切换仍未验收" actions={actions} />
    </List.Section>
  </List>;
}
