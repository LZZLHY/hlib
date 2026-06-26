/*
 * CookieJar.ets — HTTP cookie 容器与 set-cookie 解析
 *
 * 从 HttpClient 抽出。仅负责存储服务端写回的 cookie（name -> value）与解析 set-cookie；
 * 业务语义（remix_* 登录态、siteLanguageV2 偏好的注入与覆盖策略）仍由 HttpClient 决定。
 *
 * 注意：siteLanguageV2 由 HttpClient.setSiteLanguage 独占控制，因此本 jar 在解析 set-cookie 时
 * 主动忽略服务端写入的 siteLanguageV2，避免反向覆盖用户偏好。
 */

const IGNORED_SET_COOKIE_NAMES: string[] = ['siteLanguageV2'];

export class CookieJar {
  private store: Map<string, string> = new Map<string, string>();

  set(name: string, value: string): void {
    this.store.set(name, value);
  }

  has(name: string): boolean {
    return this.store.has(name);
  }

  delete(name: string): void {
    this.store.delete(name);
  }

  clear(): void {
    this.store.clear();
  }

  /** 遍历所有 cookie（用于拼 Cookie 头）。 */
  forEach(cb: (value: string, key: string) => void): void {
    this.store.forEach(cb);
  }

  /** 解析响应头里的 set-cookie，写入 jar。忽略由上层独占管理的 cookie 名。 */
  captureFrom(headers: Record<string, string | string[]>): void {
    if (headers === null || headers === undefined) {
      return;
    }
    let raw: string | string[] | undefined = undefined;
    const keys: string[] = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === 'set-cookie') {
        raw = headers[keys[i]];
        break;
      }
    }
    if (raw === undefined) {
      return;
    }
    const lines: string[] = Array.isArray(raw) ? raw : raw.split(/,(?=[^;]+=)/);
    for (let i = 0; i < lines.length; i++) {
      const segment: string = lines[i].split(';')[0].trim();
      const eqIdx: number = segment.indexOf('=');
      if (eqIdx <= 0) {
        continue;
      }
      const name: string = segment.substring(0, eqIdx).trim();
      const value: string = segment.substring(eqIdx + 1).trim();
      if (CookieJar.isIgnored(name)) {
        continue;
      }
      if (name.length > 0 && value.length > 0) {
        this.store.set(name, value);
      }
    }
  }

  private static isIgnored(name: string): boolean {
    for (let i = 0; i < IGNORED_SET_COOKIE_NAMES.length; i++) {
      if (IGNORED_SET_COOKIE_NAMES[i] === name) {
        return true;
      }
    }
    return false;
  }
}
