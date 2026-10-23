import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { request } from "node:http";

export interface Contact { id: string; arg: string; title: string; subtitle?: string }
const enhancedCapabilities = ["accountContext", "contactPagination", "persistentContacts", "avatars", "quicklinks", "fullContacts"] as const;
type EnhancedCapability = typeof enhancedCapabilities[number];
export interface Health {
  state: string; session: string; build: string; contactsSource: string;
  capabilities: { contacts: boolean; openChat: boolean } & Partial<Record<EnhancedCapability, boolean>>;
}
export interface SearchResult { items: Contact[]; session: string; source: string }
const messages: Record<string, string> = {
  unauthorized: "桥接凭证不匹配，请重启微信后重试", not_logged_in: "请先登录微信",
  not_ready: "微信尚未就绪，请稍后重试", unsupported_build: "当前微信构建尚未支持",
  native_busy: "微信正在更新联系人，请重试", invalid_native_layout: "微信内存布局不匹配，请停止使用并检查版本",
  stale_session: "微信登录会话已变化，请重新搜索", contact_not_found: "联系人已不在微信加载的缓存中，请重新搜索",
  operation_timeout: "微信操作超时，请检查微信是否有弹窗", open_not_confirmed: "微信尚未确认打开会话",
};
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function text(value: unknown, max = 4096): value is string {
  return typeof value === "string" && Buffer.byteLength(value) <= max;
}

class BridgeError extends Error {
  code: string;
  constructor(code: string) { super(messages[code] ?? "微信桥接请求失败，请运行兼容性诊断"); this.code = code; }
}
export class BridgeClient {
  private readonly credential: string;
  private readonly port: number;
  constructor(credential?: string, port = 48065) {
    this.credential = credential || join(homedir(), "Library/Application Support/WeChatTweak/bridge-token");
    this.port = port;
    if (!isAbsolute(this.credential)) throw new Error("桥接凭证必须使用绝对路径");
  }
  private async token(): Promise<string> {
    let file;
    try {
      file = await open(this.credential, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      const metadata = await file.stat();
      if (!metadata.isFile() || metadata.uid !== process.getuid?.() || (metadata.mode & 0o777) !== 0o600 || metadata.size < 64 || metadata.size > 65)
        throw new Error("unsafe");
      const buffer = Buffer.alloc(66);
      const { bytesRead } = await file.read(buffer, 0, 66, 0);
      const token = buffer.subarray(0, bytesRead).toString("ascii");
      if (!/^[0-9a-f]{64}\n?$/.test(token)) throw new Error("malformed");
      return token.trimEnd();
    } catch { throw new Error("无法读取安全的桥接凭证，请启动已安装本分支桥接库的微信（文件须归当前用户所有、权限 600）"); }
    finally { await file?.close(); }
  }
  private async json(path: string, token?: string, signal?: AbortSignal): Promise<Record<string, unknown>> {
    return new Promise((resolve, reject) => {
      const req = request({ hostname: "127.0.0.1", port: this.port, method: "GET", path, signal,
        headers: token ? { Authorization: `Bearer ${token}` } : {} }, (response) => {
        const buffers: Buffer[] = []; let size = 0;
        response.on("data", (chunk: Buffer) => {
          size += chunk.length;
          if (size > 2 * 1024 * 1024) { req.destroy(new Error("桥接响应过大")); return; }
          buffers.push(chunk);
        });
        response.on("error", reject);
        response.on("end", () => {
          try {
            if (!response.headers["content-type"]?.startsWith("application/json")) throw new Error("48065 端口不是兼容的微信桥接服务");
            const value: unknown = JSON.parse(Buffer.concat(buffers).toString("utf8"));
            if (!object(value)) throw new Error("桥接响应无效");
            if (response.statusCode !== 200) {
              const code = object(value.error) && typeof value.error.code === "string" ? value.error.code : "";
              throw new BridgeError(code);
            }
            resolve(value);
          } catch (error) { reject(error); }
        });
      });
      const timer = setTimeout(() => req.destroy(new Error("微信桥接连接超时")), 6500);
      req.on("close", () => clearTimeout(timer));
      req.on("error", (error: NodeJS.ErrnoException) => reject(error.code === "ECONNREFUSED" ? new Error("微信桥接未启动，请启动已安装桥接库的微信") : error));
      req.end();
    });
  }
  private async verified(signal?: AbortSignal): Promise<{ token: string; health: Health }> {
    const token = await this.token();
    const challenge = randomBytes(32).toString("hex");
    const value = await this.json(`/health?challenge=${challenge}`, undefined, signal);
    const proof = createHmac("sha256", token).update(`wechattweak-health-v1:${challenge}`).digest();
    if (!text(value.proof, 64) || !/^[0-9a-f]{64}$/.test(value.proof) ||
      !timingSafeEqual(proof, Buffer.from(value.proof, "hex"))) throw new Error("桥接身份校验失败，未发送凭证；请检查 48065 端口冲突");
    if (value.protocol !== 1 || value.service !== "WeChatTweak" || !text(value.state, 128) ||
      !text(value.session, 128) || !value.session || value.build !== "269602" || !text(value.contactsSource, 128) ||
      !object(value.capabilities) || typeof value.capabilities.contacts !== "boolean" || typeof value.capabilities.openChat !== "boolean")
      throw new Error("微信桥接协议或构建不兼容");
    const capabilities: Health["capabilities"] = { contacts: value.capabilities.contacts, openChat: value.capabilities.openChat };
    for (const name of enhancedCapabilities) {
      const flag = value.capabilities[name];
      if (flag !== undefined && typeof flag !== "boolean") throw new Error("微信桥接协议或构建不兼容");
      capabilities[name] = flag === true;
    }
    return { token, health: { state: value.state, session: value.session, build: value.build,
      contactsSource: value.contactsSource, capabilities } };
  }
  async health(signal?: AbortSignal): Promise<Health> { return (await this.verified(signal)).health; }
  async search(keyword: string, signal?: AbortSignal): Promise<SearchResult> {
    const { token, health } = await this.verified(signal);
    if (!health.capabilities.contacts) throw new Error(messages[health.state] ?? "微信联系人服务尚未就绪");
    const value = await this.json(`/wechat/search?${new URLSearchParams({ keyword, usePinyin: "1", fuzzy: "1" })}`, token, signal);
    if (value.ok !== true || !text(value.session, 128) || !value.session || !text(value.source, 128) ||
      !Array.isArray(value.items) || value.items.length > 100) throw new Error("联系人响应格式无效");
    const items = value.items.map((item: unknown): Contact => {
      if (!object(item) || !text(item.id, 1024) || !item.id || item.arg !== item.id || !text(item.title) ||
        (item.subtitle !== undefined && !text(item.subtitle))) throw new Error("联系人条目格式无效");
      return { id: item.id, arg: item.id, title: item.title, subtitle: item.subtitle as string | undefined };
    });
    return { items, session: value.session, source: value.source };
  }
  async avatar(id: string, session: string, signal?: AbortSignal): Promise<string | undefined> {
    const { token, health } = await this.verified(signal);
    if (health.session !== session) throw new Error(messages.stale_session);
    if (!health.capabilities.avatars) return undefined;
    let value: Record<string, unknown>;
    try { value = await this.json(`/wechat/avatar?${new URLSearchParams({ id, epoch: session })}`, token, signal); }
    catch (error) { if (error instanceof BridgeError && error.code === "avatar_not_found") return undefined; throw error; }
    if (value.ok !== true || value.id !== id || value.session !== session || value.mime !== "image/png" ||
      !text(value.data, 174764) || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value.data) ||
      !text(value.digest, 64) || !/^[0-9a-f]{64}$/.test(value.digest)) throw new Error("头像响应无效");
    const bytes = Buffer.from(value.data, "base64");
    if (bytes.length < 33 || bytes.length > 128 * 1024 || bytes.toString("base64") !== value.data ||
      !bytes.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex")) || bytes.toString("ascii", 12, 16) !== "IHDR" ||
      !bytes.readUInt32BE(16) || !bytes.readUInt32BE(20) || bytes.readUInt32BE(16) > 128 || bytes.readUInt32BE(20) > 128 ||
      createHash("sha256").update(bytes).digest("hex") !== value.digest) throw new Error("头像响应无效");
    return `data:image/png;base64,${value.data}`;
  }
  async open(id: string, session: string, signal?: AbortSignal): Promise<void> {
    const { token, health } = await this.verified(signal);
    if (health.session !== session) throw new Error(messages.stale_session);
    if (!health.capabilities.openChat) throw new Error(messages[health.state] ?? "微信打开会话服务尚未就绪");
    const value = await this.json(`/wechat/start?${new URLSearchParams({ session: id, epoch: session })}`, token, signal);
    if (value.ok !== true || value.confirmed !== true) throw new Error("微信没有确认打开会话");
  }
}
