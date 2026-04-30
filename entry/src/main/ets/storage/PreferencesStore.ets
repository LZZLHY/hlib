/*
 * PreferencesStore.ets
 *
 * 基于 @kit.ArkData 的 preferences 单例封装。
 * 提供两个独立分组：
 *   - 'settings'：偏好、收藏、下载历史等业务数据
 *   - 'auth'    ：登录凭证及账号列表（敏感信息）
 *
 * 设计要点：
 *   1. 必须先在 EntryAbility.onCreate 中调用 init(context)，之后才能用任何静态方法。
 *   2. 所有写操作都会自动 flush；调用方无需手动持久化。
 *   3. 复杂对象用 JSON 字符串存放，读出时自动 parse；解析失败返回 fallback。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../utils/Logger';

const TAG: string = 'PreferencesStore';

export type PrefGroup = 'settings' | 'auth';

export class PreferencesStore {
  private static settings: preferences.Preferences | null = null;
  private static auth: preferences.Preferences | null = null;
  private static initialized: boolean = false;

  /** 必须最早在 EntryAbility.onCreate 中调用一次 */
  static async init(context: common.Context): Promise<void> {
    if (PreferencesStore.initialized) {
      return;
    }
    try {
      const settingsOptions: preferences.Options = { name: 'settings' };
      const authOptions: preferences.Options = { name: 'auth' };
      PreferencesStore.settings = await preferences.getPreferences(context, settingsOptions);
      PreferencesStore.auth = await preferences.getPreferences(context, authOptions);
      PreferencesStore.initialized = true;
      Logger.i(TAG, 'preferences initialized');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(TAG, 'init failed', e);
      throw new Error(e.message ?? 'preferences_init_failed');
    }
  }

  static isReady(): boolean {
    return PreferencesStore.initialized;
  }

  /** ─── 基础 KV ─── */

  static async putString(group: PrefGroup, key: string, value: string): Promise<void> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      await p.put(key, value);
      await p.flush();
    } catch (err) {
      PreferencesStore.logErr(`putString(${key})`, err);
    }
  }

  static async getString(group: PrefGroup, key: string, defaultValue: string = ''): Promise<string> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      const v: preferences.ValueType = await p.get(key, defaultValue);
      return typeof v === 'string' ? v : defaultValue;
    } catch (err) {
      PreferencesStore.logErr(`getString(${key})`, err);
      return defaultValue;
    }
  }

  static async putNumber(group: PrefGroup, key: string, value: number): Promise<void> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      await p.put(key, value);
      await p.flush();
    } catch (err) {
      PreferencesStore.logErr(`putNumber(${key})`, err);
    }
  }

  static async getNumber(group: PrefGroup, key: string, defaultValue: number = 0): Promise<number> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      const v: preferences.ValueType = await p.get(key, defaultValue);
      return typeof v === 'number' ? v : defaultValue;
    } catch (err) {
      PreferencesStore.logErr(`getNumber(${key})`, err);
      return defaultValue;
    }
  }

  static async putBoolean(group: PrefGroup, key: string, value: boolean): Promise<void> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      await p.put(key, value);
      await p.flush();
    } catch (err) {
      PreferencesStore.logErr(`putBoolean(${key})`, err);
    }
  }

  static async getBoolean(group: PrefGroup, key: string, defaultValue: boolean = false): Promise<boolean> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      const v: preferences.ValueType = await p.get(key, defaultValue);
      return typeof v === 'boolean' ? v : defaultValue;
    } catch (err) {
      PreferencesStore.logErr(`getBoolean(${key})`, err);
      return defaultValue;
    }
  }

  /** ─── 复杂对象（JSON 化） ─── */

  static async putObject<T>(group: PrefGroup, key: string, value: T): Promise<void> {
    try {
      const json: string = JSON.stringify(value);
      await PreferencesStore.putString(group, key, json);
    } catch (err) {
      PreferencesStore.logErr(`putObject(${key})`, err);
    }
  }

  static async getObject<T>(group: PrefGroup, key: string, fallback: T): Promise<T> {
    const json: string = await PreferencesStore.getString(group, key, '');
    if (json.length === 0) {
      return fallback;
    }
    try {
      return JSON.parse(json) as T;
    } catch (err) {
      Logger.w(TAG, `getObject(${key}) parse failed, returning fallback`);
      return fallback;
    }
  }

  /** ─── 删除 / 清空 ─── */

  static async remove(group: PrefGroup, key: string): Promise<void> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      await p.delete(key);
      await p.flush();
    } catch (err) {
      PreferencesStore.logErr(`remove(${key})`, err);
    }
  }

  static async clear(group: PrefGroup): Promise<void> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      await p.clear();
      await p.flush();
    } catch (err) {
      PreferencesStore.logErr(`clear(${group})`, err);
    }
  }

  static async hasKey(group: PrefGroup, key: string): Promise<boolean> {
    const p: preferences.Preferences = PreferencesStore.pick(group);
    try {
      return await p.has(key);
    } catch (err) {
      PreferencesStore.logErr(`hasKey(${key})`, err);
      return false;
    }
  }

  // ─── 内部 ───
  private static pick(group: PrefGroup): preferences.Preferences {
    if (!PreferencesStore.initialized) {
      throw new Error('PreferencesStore.init() not called');
    }
    if (group === 'settings') {
      return PreferencesStore.settings as preferences.Preferences;
    }
    return PreferencesStore.auth as preferences.Preferences;
  }

  private static logErr(label: string, err: Object): void {
    const e: BusinessError = err as BusinessError;
    Logger.w(TAG, `${label} failed: code=${e.code} msg=${e.message}`);
  }
}
