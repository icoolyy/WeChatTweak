import { accessSync, constants, statSync } from "node:fs";
import { delimiter, isAbsolute, join } from "node:path";
import { execFile } from "node:child_process";

export interface Diagnosis {
  schemaVersion: 1;
  cliVersion: string;
  patchState: string;
  pendingWrites: number;
  alreadyPatched: number;
  configuredFeatures: string[];
  contactsBridgeAvailable: boolean;
  contactsBridgeReason?: string;
  errors: string[];
  distribution: "appStore" | "unknown";
  automaticUpdates: { status: "managedByAppStore" | "unsupported"; independentlyBlocked: false };
  app?: { displayVersion: string; build: string; bundleID: string };
}

export function findExecutable(candidates: string[]): string | null {
  for (const path of candidates) {
    if (!isAbsolute(path)) continue;
    try {
      accessSync(path, constants.X_OK);
      if (statSync(path).isFile()) return path;
    } catch { /* Try the next explicit candidate. */ }
  }
  return null;
}

export function homebrewPath(): string | null {
  return findExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew",
    ...(process.env.PATH ?? "").split(delimiter).filter(Boolean).map((dir) => join(dir, "brew"))]);
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function strings(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}
function count(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

export function parseDiagnosis(text: string): Diagnosis {
  const value: unknown = JSON.parse(text);
  if (!object(value) || value.schemaVersion !== 1 || typeof value.cliVersion !== "string" ||
    typeof value.patchState !== "string" || !["ready", "applied", "partiallyApplied", "unsupportedBuild", "error"].includes(value.patchState) ||
    !count(value.pendingWrites) || !count(value.alreadyPatched) || !strings(value.configuredFeatures) ||
    typeof value.contactsBridgeAvailable !== "boolean" || !strings(value.errors) ||
    (value.contactsBridgeReason !== undefined && typeof value.contactsBridgeReason !== "string")) {
    throw new Error("CLI 诊断协议不兼容，请选择本分支构建的 dist/wechattweak");
  }
  let app: Diagnosis["app"];
  const distribution = value.distribution ?? "unknown";
  const updates = value.automaticUpdates ?? { status: "unsupported", independentlyBlocked: false };
  if (!["appStore", "unknown"].includes(String(distribution)) || !object(updates) ||
    updates.independentlyBlocked !== false || updates.status !== (distribution === "appStore" ? "managedByAppStore" : "unsupported")) {
    throw new Error("CLI 返回了无效的自动更新能力信息");
  }
  if (value.app !== undefined) {
    if (!object(value.app) || typeof value.app.displayVersion !== "string" || typeof value.app.build !== "string" || typeof value.app.bundleID !== "string") {
      throw new Error("CLI 返回了无效的微信版本信息");
    }
    app = { displayVersion: value.app.displayVersion, build: value.app.build, bundleID: value.app.bundleID };
  }
  return { schemaVersion: 1, cliVersion: value.cliVersion, patchState: value.patchState,
    pendingWrites: value.pendingWrites, alreadyPatched: value.alreadyPatched,
    configuredFeatures: value.configuredFeatures, contactsBridgeAvailable: value.contactsBridgeAvailable,
    contactsBridgeReason: value.contactsBridgeReason, errors: value.errors, app,
    distribution: distribution as Diagnosis["distribution"], automaticUpdates: updates as Diagnosis["automaticUpdates"] };
}

export async function readDiagnosis(cliPath: string, appPath?: string, credentialPath?: string): Promise<Diagnosis> {
  if (!isAbsolute(cliPath)) throw new Error("CLI 必须使用绝对路径");
  if (!findExecutable([cliPath])) throw new Error("CLI 不存在或不可执行，请选择本分支构建的 dist/wechattweak");
  return new Promise((resolve, reject) => {
    const args = ["doctor", "--json", ...(appPath ? ["--app", appPath] : []), ...(credentialPath ? ["--credential-file", credentialPath] : [])];
    execFile(cliPath, args, { encoding: "utf8", timeout: 10_000, maxBuffer: 1024 * 1024 }, (error, stdout) => {
      try {
        const report = parseDiagnosis(stdout);
        if (error && report.errors.length === 0) throw error;
        resolve(report);
      } catch {
        reject(new Error("无法读取兼容诊断，请选择本分支构建的 dist/wechattweak；官方 2.0.1 不提供 doctor 命令"));
      }
    });
  });
}
