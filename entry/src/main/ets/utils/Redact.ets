/*
 * Redact.ets — 日志脱敏工具
 *
 * 防止凭证经 hilog 泄漏。Z-Library 的阅读器 URL 末尾会拼 remix_userkey/remix_userid，
 * 下载链接可能带签名 token，HTTP 头里有 Cookie/Set-Cookie——这些一旦进 hilog
 * 就可能被第三方工具读取。所有"打印 URL / headers / cookie"的日志都应先过本工具。
 *
 * 设计：只替换敏感字段的"值"，保留"键名"，方便排查时仍能看出结构。
 */

const SENSITIVE_QUERY_KEYS: string[] = [
  'remix_userkey', 'remix_userid', 'userkey', 'userid', 'user_key', 'user_id', 'key', 'token',
];
const SENSITIVE_HEADER_KEYS: string[] = [
  'cookie', 'set-cookie', 'authorization', 'x-auth-token', 'proxy-authorization',
];
const MASK: string = '***';

export class Redact {
  /** 脱敏 URL：把敏感 query 参数的值替换为 ***，保留 path 与 key 名。 */
  static url(input: string): string {
    if (input.length === 0) {
      return input;
    }
    const qIdx: number = input.indexOf('?');
    if (qIdx < 0) {
      return input;
    }
    const base: string = input.substring(0, qIdx);
    const query: string = input.substring(qIdx + 1);
    const parts: string[] = query.split('&');
    const out: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const seg: string = parts[i];
      const eq: number = seg.indexOf('=');
      if (eq <= 0) {
        out.push(seg);
        continue;
      }
      const k: string = seg.substring(0, eq);
      if (Redact.isSensitiveKey(k, SENSITIVE_QUERY_KEYS)) {
        out.push(`${k}=${MASK}`);
      } else {
        out.push(seg);
      }
    }
    return `${base}?${out.join('&')}`;
  }

  /** 脱敏 cookie 串（name=value; name2=value2）：所有值一律打码（cookie 默认敏感）。 */
  static cookie(input: string): string {
    if (input.length === 0) {
      return input;
    }
    const parts: string[] = input.split(';');
    const out: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const seg: string = parts[i].trim();
      if (seg.length === 0) {
        continue;
      }
      const eq: number = seg.indexOf('=');
      if (eq <= 0) {
        out.push(seg);
        continue;
      }
      const k: string = seg.substring(0, eq).trim();
      out.push(`${k}=${MASK}`);
    }
    return out.join('; ');
  }

  /**
   * 脱敏 headers：返回新对象，敏感头的值替换为 ***。
   * 入参用 Object 以兼容 http 响应头（值可能是 string 或 string[]）。
   */
  static headers(h: Object | null | undefined): Record<string, string> {
    const out: Record<string, string> = {};
    if (h === null || h === undefined) {
      return out;
    }
    const obj: Record<string, string | string[]> = h as Record<string, string | string[]>;
    const keys: string[] = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (Redact.isSensitiveKey(k, SENSITIVE_HEADER_KEYS)) {
        out[k] = MASK;
      } else {
        const v: string | string[] = obj[k];
        out[k] = Array.isArray(v) ? v.join(',') : String(v);
      }
    }
    return out;
  }

  private static isSensitiveKey(key: string, list: string[]): boolean {
    const k: string = key.toLowerCase();
    for (let i = 0; i < list.length; i++) {
      if (k === list[i]) {
        return true;
      }
    }
    return false;
  }
}
