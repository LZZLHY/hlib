/*
 * AuthStore.ets
 * 凭证 + 多账号列表持久化（基于 PreferencesStore.auth 分组）。
 *
 * 安全模型：
 *   - userId / userKey / password 三个敏感字段在写盘前调 SecretStore.encrypt（HUKS AES-GCM），
 *     读盘后调 SecretStore.decrypt 还原。
 *   - email / name 是 PII 但非凭证，原文存。
 *   - 兼容旧明文条目：SecretStore.decrypt 对非 sec1: 前缀输入原样返回。
 */

import { PreferencesStore } from './PreferencesStore';
import { SecretStore } from '../utils/SecretStore';

const KEY_USER_ID: string   = 'remix_userid';
const KEY_USER_KEY: string  = 'remix_userkey';
const KEY_EMAIL: string     = 'user_email';
const KEY_NAME: string      = 'user_name';
const KEY_PASSWORD: string  = 'user_password';
const KEY_ACCOUNTS: string  = 'saved_accounts';

export interface SavedAccount {
  userId: string;
  userKey: string;
  email?: string;
  name?: string;
  password?: string;
}

export class AuthStore {
  /** 写入完整凭证；同时把账号合并入 saved_accounts。敏感字段经 HUKS 加密。 */
  static async saveCredentials(account: SavedAccount): Promise<void> {
    const encUserId: string = await SecretStore.encrypt(account.userId);
    const encUserKey: string = await SecretStore.encrypt(account.userKey);

    await PreferencesStore.putString('auth', KEY_USER_ID, encUserId);
    await PreferencesStore.putString('auth', KEY_USER_KEY, encUserKey);
    if (account.email !== undefined) {
      await PreferencesStore.putString('auth', KEY_EMAIL, account.email);
    }
    if (account.name !== undefined) {
      await PreferencesStore.putString('auth', KEY_NAME, account.name);
    }
    if (account.password !== undefined) {
      const encPwd: string = await SecretStore.encrypt(account.password);
      await PreferencesStore.putString('auth', KEY_PASSWORD, encPwd);
    }
    await AuthStore.upsertAccount(account);
  }

  static async getCredentials(): Promise<SavedAccount | null> {
    const rawUserId: string = await PreferencesStore.getString('auth', KEY_USER_ID, '');
    const rawUserKey: string = await PreferencesStore.getString('auth', KEY_USER_KEY, '');
    const userId: string = await SecretStore.decrypt(rawUserId);
    const userKey: string = await SecretStore.decrypt(rawUserKey);
    if (!userId || !userKey) {
      return null;
    }
    const email = await PreferencesStore.getString('auth', KEY_EMAIL, '');
    const name = await PreferencesStore.getString('auth', KEY_NAME, '');
    const rawPwd: string = await PreferencesStore.getString('auth', KEY_PASSWORD, '');
    const password: string = rawPwd.length > 0 ? await SecretStore.decrypt(rawPwd) : '';
    return {
      userId,
      userKey,
      email: email || undefined,
      name: name || undefined,
      password: password || undefined,
    };
  }

  static async clearCredentials(): Promise<void> {
    await PreferencesStore.remove('auth', KEY_USER_ID);
    await PreferencesStore.remove('auth', KEY_USER_KEY);
    await PreferencesStore.remove('auth', KEY_EMAIL);
    await PreferencesStore.remove('auth', KEY_NAME);
    await PreferencesStore.remove('auth', KEY_PASSWORD);
  }

  /** 把单条账号 upsert 到 saved_accounts 列表。明文 in-memory 进入，写盘前加密。 */
  static async upsertAccount(account: SavedAccount): Promise<void> {
    const list: SavedAccount[] = await AuthStore.listAccountsRaw();
    // 比较时用解密后的 userId（保证查重正确）
    let foundIdx: number = -1;
    for (let i = 0; i < list.length; i++) {
      const decId: string = await SecretStore.decrypt(list[i].userId);
      if (decId === account.userId) {
        foundIdx = i;
        break;
      }
    }
    const enc: SavedAccount = {
      userId: await SecretStore.encrypt(account.userId),
      userKey: await SecretStore.encrypt(account.userKey),
      email: account.email,
      name: account.name,
      password: account.password !== undefined
        ? await SecretStore.encrypt(account.password)
        : undefined,
    };
    if (foundIdx >= 0) {
      list[foundIdx] = enc;
    } else {
      list.push(enc);
    }
    await PreferencesStore.putObject<SavedAccount[]>('auth', KEY_ACCOUNTS, list);
  }

  /** 对外 API：返回明文 SavedAccount[]（已解密）。 */
  static async listAccounts(): Promise<SavedAccount[]> {
    const list: SavedAccount[] = await AuthStore.listAccountsRaw();
    const out: SavedAccount[] = [];
    for (let i = 0; i < list.length; i++) {
      const a: SavedAccount = list[i];
      const userId: string = await SecretStore.decrypt(a.userId);
      const userKey: string = await SecretStore.decrypt(a.userKey);
      if (!userId || !userKey) {
        continue;
      }
      const password: string | undefined = a.password !== undefined && a.password.length > 0
        ? await SecretStore.decrypt(a.password)
        : undefined;
      out.push({
        userId,
        userKey,
        email: a.email,
        name: a.name,
        password: password !== undefined && password.length > 0 ? password : undefined,
      });
    }
    return out;
  }

  static async removeAccount(userId: string): Promise<void> {
    const list: SavedAccount[] = await AuthStore.listAccountsRaw();
    const filtered: SavedAccount[] = [];
    for (let i = 0; i < list.length; i++) {
      const decId: string = await SecretStore.decrypt(list[i].userId);
      if (decId !== userId) {
        filtered.push(list[i]);
      }
    }
    await PreferencesStore.putObject<SavedAccount[]>('auth', KEY_ACCOUNTS, filtered);
  }

  /** 内部：从盘读出原始（可能加密）的账号列表，不解密。 */
  private static async listAccountsRaw(): Promise<SavedAccount[]> {
    return await PreferencesStore.getObject<SavedAccount[]>('auth', KEY_ACCOUNTS, []);
  }
}
