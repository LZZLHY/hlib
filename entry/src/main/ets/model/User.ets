/*
 * User.ets — 已登录用户模型
 */

export interface UserJson {
  id?: number | string;
  name?: string;
  email?: string;
  kindle_email?: string;
  remix_userkey?: string;
  downloads_limit?: number | string;
  downloads_today?: number | string;
  confirmed?: number | string | boolean;
  isPremium?: number | string | boolean;
  /** 站点语言偏好（'chinese'/'english'/...）；服务端通过 profile 返回，控制首页 recommended 语言。 */
  language?: string;
}

export class User {
  id: string = '';
  name: string = '';
  email: string = '';
  kindleEmail?: string;
  remixUserkey: string = '';
  downloadsLimit?: number;
  downloadsToday?: number;
  confirmed?: number;
  isPremium?: number;
  /** 服务端账号语言偏好（与 olib release 包 toString 中 `, language: ` 字段对齐）。 */
  language?: string;

  static fromJson(json: UserJson | undefined | null): User {
    const u = new User();
    if (!json) {
      return u;
    }
    u.id = json.id !== undefined && json.id !== null ? String(json.id) : '';
    u.name = (json.name ?? '').toString();
    u.email = (json.email ?? '').toString();
    u.kindleEmail = json.kindle_email;
    u.remixUserkey = (json.remix_userkey ?? '').toString();
    u.downloadsLimit = User.toInt(json.downloads_limit);
    u.downloadsToday = User.toInt(json.downloads_today);
    u.confirmed = User.toInt(json.confirmed);
    u.isPremium = User.toInt(json.isPremium);
    u.language = json.language;
    return u;
  }

  /** 今日剩余下载次数。limit 缺省按 10 计。 */
  get downloadsLeft(): number {
    return (this.downloadsLimit ?? 10) - (this.downloadsToday ?? 0);
  }

  private static toInt(v: number | string | boolean | undefined | null): number | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v === 'boolean') {
      return v ? 1 : 0;
    }
    if (typeof v === 'number') {
      return Number.isFinite(v) ? Math.trunc(v) : undefined;
    }
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : undefined;
  }
}
