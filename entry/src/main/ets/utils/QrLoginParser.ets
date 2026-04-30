/*
 * QrLoginParser.ets
 *
 * 把扫到的二维码字符串解析为 Z-Library 凭证 { userId, userKey }。
 *
 * 兼容三种常见格式：
 *   1) JSON     —— {"userId":"...","userKey":"..."} 或 {"remix_userid":"...","remix_userkey":"..."}
 *   2) URL/query —— 任意含 remix_userid / remix_userkey （或 userId / userKey）查询参数
 *                     例如 https://z-library.sk/login?remix_userid=123&remix_userkey=abc
 *   3) Cookie 串 —— "remix_userid=123; remix_userkey=abc"（任意分隔符）
 *
 * 实现思路：先尝试 JSON.parse，失败则按字符串扫两个 key。两个值都解析到才算成功。
 */

export interface QrCredential {
  userId: string;
  userKey: string;
}

const KEYS_USER_ID: string[] = ['remix_userid', 'userId', 'user_id', 'uid'];
const KEYS_USER_KEY: string[] = ['remix_userkey', 'userKey', 'user_key', 'key'];

export class QrLoginParser {
  /** 失败返回 null。成功 userId/userKey 都非空。 */
  static parse(raw: string | undefined | null): QrCredential | null {
    if (raw === undefined || raw === null) {
      return null;
    }
    const text: string = raw.trim();
    if (text.length === 0) {
      return null;
    }

    // 1) JSON
    if (text.startsWith('{') && text.endsWith('}')) {
      const fromJson: QrCredential | null = QrLoginParser.fromJson(text);
      if (fromJson !== null) {
        return fromJson;
      }
    }

    // 2) URL with query
    if (text.indexOf('?') >= 0 || text.startsWith('http://') || text.startsWith('https://')) {
      const fromUrl: QrCredential | null = QrLoginParser.fromUrl(text);
      if (fromUrl !== null) {
        return fromUrl;
      }
    }

    // 3) cookie / kv 串：包含 = 即可尝试
    if (text.indexOf('=') >= 0) {
      return QrLoginParser.fromKv(text);
    }

    return null;
  }

  private static fromJson(text: string): QrCredential | null {
    try {
      const obj = JSON.parse(text) as Record<string, string>;
      const userId: string = QrLoginParser.pickKey(obj, KEYS_USER_ID);
      const userKey: string = QrLoginParser.pickKey(obj, KEYS_USER_KEY);
      if (userId.length > 0 && userKey.length > 0) {
        return { userId, userKey };
      }
    } catch {
      // ignore
    }
    return null;
  }

  private static fromUrl(text: string): QrCredential | null {
    const queryIdx: number = text.indexOf('?');
    const query: string = queryIdx >= 0 ? text.substring(queryIdx + 1) : text;
    return QrLoginParser.fromKv(query);
  }

  /** 解析任意 "k=v[&; ,]k=v" 形式。 */
  private static fromKv(text: string): QrCredential | null {
    const map: Record<string, string> = {};
    const parts: string[] = text.split(/[&;,\s]+/);
    for (let i = 0; i < parts.length; i++) {
      const seg: string = parts[i];
      const eq: number = seg.indexOf('=');
      if (eq <= 0) continue;
      const k: string = seg.substring(0, eq).trim();
      const v: string = seg.substring(eq + 1).trim();
      if (k.length > 0 && v.length > 0) {
        try {
          map[k] = decodeURIComponent(v);
        } catch {
          map[k] = v;
        }
      }
    }
    const userId: string = QrLoginParser.pickKey(map, KEYS_USER_ID);
    const userKey: string = QrLoginParser.pickKey(map, KEYS_USER_KEY);
    if (userId.length > 0 && userKey.length > 0) {
      return { userId, userKey };
    }
    return null;
  }

  private static pickKey(obj: Record<string, string>, keys: string[]): string {
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const v: string | undefined = obj[k];
      if (typeof v === 'string' && v.length > 0) {
        return v;
      }
    }
    return '';
  }
}
