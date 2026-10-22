import { execFile } from "node:child_process";
import { isAbsolute } from "node:path";
import { findExecutable } from "../diagnostics.ts";

export interface ManagementOptions { cliPath: string; appPath: string; backupPath?: string }
type Execute = (cli: string, args: string[]) => Promise<string>;
export function runCLI(cli: string, args: string[]): Promise<string> {
  if (!findExecutable([cli])) return Promise.reject(new Error("请设置本分支 dist/wechattweak 的可执行绝对路径"));
  return new Promise((resolve, reject) => {
    execFile(cli, args, { encoding: "utf8", timeout: 600_000, maxBuffer: 2 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) reject(new Error((stderr || error.message).trim())); else resolve(stdout);
    });
  });
}
function quote(value: string): string { return "'" + value.replaceAll("'", "'\"'\"'") + "'"; }
export class ManagementService {
  private options: ManagementOptions;
  private execute: Execute;
  constructor(options: ManagementOptions, execute: Execute = runCLI) { this.options = options; this.execute = execute; }
  private args(operation: "patch" | "restore"): string[] {
    if (!isAbsolute(this.options.cliPath) || !isAbsolute(this.options.appPath)) throw new Error("CLI 和微信必须使用绝对路径");
    if (operation === "restore") {
      if (!this.options.backupPath || !isAbsolute(this.options.backupPath)) throw new Error("请在偏好设置中填写备份目录的绝对路径");
      return ["restore", "--app", this.options.appPath, "--backup", this.options.backupPath];
    }
    return ["patch", "--app", this.options.appPath, "--install-bridge"];
  }
  async preflight(): Promise<string> { return this.execute(this.options.cliPath, [...this.args("patch"), "--dry-run"]); }
  async install(confirm: () => Promise<boolean>): Promise<string | undefined> {
    const args = this.args("patch"); if (!await confirm()) return; return this.execute(this.options.cliPath, args);
  }
  async restore(confirm: () => Promise<boolean>): Promise<string | undefined> {
    const args = this.args("restore"); if (!await confirm()) return; return this.execute(this.options.cliPath, args);
  }
  terminalCommand(operation: "patch" | "restore"): string {
    return "sudo " + [this.options.cliPath, ...this.args(operation)].map(quote).join(" ");
  }
}
