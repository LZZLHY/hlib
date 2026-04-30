/*
 * UrlUtils.ets
 * URL 拼接与 reader 域名重写工具。
 */

const LANGUAGE_PREFIXES = new Set<string>([
  'zh', 'en', 'de', 'fr', 'es', 'it', 'pt', 'ja', 'ko', 'ru', 'ar',
]);

export class UrlUtils {
  /**
   * 拼接 query string；undefined / null / 空数组 会被剔除。
   */
  static buildQuery(params?: Record<string, string | number | boolean | string[] | number[] | undefined | null>): string {
    if (!params) {
      return '';
    }
    const parts: string[] = [];
    const keys = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const v = params[k];
      if (v === undefined || v === null) {
        continue;
      }
      if (Array.isArray(v)) {
        if (v.length === 0) {
          continue;
        }
        for (let j = 0; j < v.length; j++) {
          parts.push(`${encodeURIComponent(k)}[]=${encodeURIComponent(String(v[j]))}`);
        }
      } else {
        parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
      }
    }
    return parts.length ? '?' + parts.join('&') : '';
  }

  /**
   * 将一个表单对象编码为 application/x-www-form-urlencoded。
   * 支持数组：序列化为 key[]=v1&key[]=v2（与 PHP / Z-Library API 默认习惯一致）。
   */
  static encodeForm(form: Record<string, string | number | boolean | undefined | null | string[] | number[]>): string {
    const parts: string[] = [];
    const keys = Object.keys(form);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const v = form[k];
      if (v === undefined || v === null) {
        continue;
      }
      if (Array.isArray(v)) {
        if (v.length === 0) {
          continue;
        }
        for (let j = 0; j < v.length; j++) {
          parts.push(`${encodeURIComponent(k)}[]=${encodeURIComponent(String(v[j]))}`);
        }
      } else {
        parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
      }
    }
    return parts.join('&');
  }

  /** 把 path 与 base domain 拼成完整 URL（支持传入绝对 URL 直接返回）。 */
  static joinUrl(domain: string, path: string): string {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    const cleanDomain = domain.replace(/^https?:\/\//, '').replace(/\/$/, '');
    if (path.startsWith('/')) {
      return `https://${cleanDomain}${path}`;
    }
    return `https://${cleanDomain}/${path}`;
  }

  /**
   * 复刻 olib `book_detail_screen.dart` 的 reader 域名重写逻辑。
   *
   * - book.readOnlineUrl 形如 https://reader.z-library.sk/book/...
   * - 我们要把 reader.{某域} 替换成 reader.{当前镜像域}（或语言前缀域）
   * - 把 z-library.sk 替换成当前域
   * - 末尾拼上 ?remix_userkey=&remix_userid=
   */
  static rewriteReaderUrl(originalUrl: string, currentDomain: string, userId?: string, userKey?: string): string {
    if (!originalUrl) {
      return originalUrl;
    }
    let readerDomain: string;
    const dotIdx = currentDomain.indexOf('.');
    if (dotIdx > 0) {
      const prefix = currentDomain.substring(0, dotIdx);
      if (LANGUAGE_PREFIXES.has(prefix)) {
        readerDomain = `reader${currentDomain.substring(dotIdx)}`;
      } else {
        readerDomain = `reader.${currentDomain}`;
      }
    } else {
      readerDomain = `reader.${currentDomain}`;
    }

    let url = originalUrl;
    url = url.replace(/cdn\.reader\./g, 'reader.');
    url = url.replace(/reader\.[a-zA-Z0-9.-]+/g, readerDomain);
    url = url.replace(/z-library\.[a-zA-Z]+/g, currentDomain);

    if (userId && userKey) {
      const sep = url.indexOf('?') >= 0 ? '&' : '?';
      url = `${url}${sep}remix_userkey=${userKey}&remix_userid=${userId}`;
    }
    return url;
  }
}
