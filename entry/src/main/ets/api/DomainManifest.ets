/*
 * DomainManifest.ets
 *
 * 镜像域名列表管理：内置 DOMAINS + 远程 manifest 合并 + 持久化。
 *
 * 设计：
 *   1. 默认仅返回内置 DOMAINS。用户在设置中显式开启「在线同步镜像列表」并填写 manifest URL 后，
 *      启动时才拉取远程并合并。
 *   2. 远程 manifest 格式（强约束以防注入）：
 *        {
 *          "version": "2026-04-30",
 *          "domains": ["pkuedu.online", "9libmirror.tech", ...]
 *        }
 *   3. 拉到的 domains 经过严格清洗（小写、去协议、去末尾斜杠、域名字符白名单）才合并。
 *   4. 任何拉取失败都回退到内置列表，不阻塞启动流程。
 *
 * 推荐 manifest 托管位置（用户自选）：
 *   - GitHub raw：`https://raw.githubusercontent.com/<owner>/<repo>/main/domains.json`
 *   - jsdelivr：`https://cdn.jsdelivr.net/gh/<owner>/<repo>@main/domains.json`
 *   - Cloudflare Pages / Workers：`https://<sub>.pages.dev/domains.json`
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DOMAINS } from './Domains';
import { PreferencesStore } from '../storage/PreferencesStore';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Logger } from '../utils/Logger';

const TAG: string = 'DomainManifest';
const KEY_REMOTE_DOMAINS: string = 'remote_domains_v1';
const KEY_REMOTE_DOMAINS_VERSION: string = 'remote_domains_version';
const KEY_REMOTE_DOMAINS_TS: string = 'remote_domains_ts';
const FETCH_TIMEOUT_MS: number = 10000;
/** 单次 manifest 最大字节，防滥发。 */
const MAX_MANIFEST_BYTES: number = 64 * 1024;
/** 域名字符白名单：小写字母 / 数字 / `.` / `-` */
const DOMAIN_REGEX: RegExp = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

interface ManifestPayload {
  version?: string;
  domains?: string[];
}

export class DomainManifest {
  /** 远程同步是否启用（默认关）。 */
  private static enabled: boolean = false;
  /** 用户配置的 manifest URL。 */
  private static manifestUrl: string = '';
  /** 远程同步过的域名（已与内置合并去重）。 */
  private static remoteDomains: string[] = [];
  /** 上一次同步的版本号（用于 UI 显示）。 */
  private static lastVersion: string = '';
  /** 上一次同步的时间戳（毫秒）。 */
  private static lastTs: number = 0;

  // ─── 持久化加载 ───────────────────────────────────────

  /** EntryAbility 初始化阶段调一次：从 preferences 读出用户配置和上次缓存。 */
  static async loadFromStorage(): Promise<void> {
    DomainManifest.enabled = await PreferencesStore.getBoolean(
      'settings',
      AppStorageKeys.DOMAIN_MANIFEST_ENABLED,
      false,
    );
    DomainManifest.manifestUrl = await PreferencesStore.getString(
      'settings',
      AppStorageKeys.DOMAIN_MANIFEST_URL,
      '',
    );
    DomainManifest.remoteDomains = await PreferencesStore.getObject<string[]>(
      'settings',
      KEY_REMOTE_DOMAINS,
      [] as string[],
    );
    DomainManifest.lastVersion = await PreferencesStore.getString('settings', KEY_REMOTE_DOMAINS_VERSION, '');
    DomainManifest.lastTs = await PreferencesStore.getNumber('settings', KEY_REMOTE_DOMAINS_TS, 0);
    Logger.i(TAG, `loaded: enabled=${DomainManifest.enabled} remote=${DomainManifest.remoteDomains.length}`);
  }

  // ─── 配置 ───────────────────────────────────────────

  static isEnabled(): boolean {
    return DomainManifest.enabled;
  }

  static getUrl(): string {
    return DomainManifest.manifestUrl;
  }

  static getLastVersion(): string {
    return DomainManifest.lastVersion;
  }

  static getLastTs(): number {
    return DomainManifest.lastTs;
  }

  static getRemoteCount(): number {
    return DomainManifest.remoteDomains.length;
  }

  static async setEnabled(on: boolean): Promise<void> {
    DomainManifest.enabled = on;
    await PreferencesStore.putBoolean('settings', AppStorageKeys.DOMAIN_MANIFEST_ENABLED, on);
  }

  static async setUrl(url: string): Promise<void> {
    const trimmed: string = url.trim();
    DomainManifest.manifestUrl = trimmed;
    await PreferencesStore.putString('settings', AppStorageKeys.DOMAIN_MANIFEST_URL, trimmed);
  }

  // ─── 关键 API ────────────────────────────────────────

  /**
   * 当前生效的域名列表 = 内置 DOMAINS + 远程拉到的，按内置在前的顺序合并去重。
   * 同步调用，UI / SpeedTestVM / DomainSelectorDialog 直接消费。
   */
  static getActiveDomains(): string[] {
    const merged: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < DOMAINS.length; i++) {
      const d: string = DOMAINS[i];
      if (!seen.has(d)) {
        seen.add(d);
        merged.push(d);
      }
    }
    if (DomainManifest.enabled) {
      for (let i = 0; i < DomainManifest.remoteDomains.length; i++) {
        const d: string = DomainManifest.remoteDomains[i];
        if (!seen.has(d)) {
          seen.add(d);
          merged.push(d);
        }
      }
    }
    return merged;
  }

  /**
   * 异步拉取远程 manifest，写入持久化并合并到内存列表。
   * 失败时不抛异常，只记录日志；返回 true=成功更新，false=未更新。
   */
  static async refreshFromRemote(): Promise<boolean> {
    if (!DomainManifest.enabled) {
      return false;
    }
    if (DomainManifest.manifestUrl.length === 0) {
      Logger.w(TAG, 'refresh skipped: empty manifestUrl');
      return false;
    }
    const url: string = DomainManifest.manifestUrl;
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      Logger.w(TAG, `refresh skipped: invalid url scheme: ${url}`);
      return false;
    }

    const req: http.HttpRequest = http.createHttp();
    try {
      const reqOpts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/json' },
        connectTimeout: FETCH_TIMEOUT_MS,
        readTimeout: FETCH_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      };
      const resp: http.HttpResponse = await req.request(url, reqOpts);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        Logger.w(TAG, `refresh http ${resp.responseCode}`);
        return false;
      }
      const text: string = typeof resp.result === 'string' ? resp.result : '';
      if (text.length === 0 || text.length > MAX_MANIFEST_BYTES) {
        Logger.w(TAG, `refresh body invalid len=${text.length}`);
        return false;
      }
      const parsed: ManifestPayload = JSON.parse(text) as ManifestPayload;
      const cleaned: string[] = DomainManifest.cleanDomains(parsed.domains);
      if (cleaned.length === 0) {
        Logger.w(TAG, 'refresh got 0 valid domains');
        return false;
      }
      DomainManifest.remoteDomains = cleaned;
      DomainManifest.lastVersion = parsed.version !== undefined ? parsed.version : '';
      DomainManifest.lastTs = Date.now();

      await PreferencesStore.putObject<string[]>('settings', KEY_REMOTE_DOMAINS, cleaned);
      await PreferencesStore.putString('settings', KEY_REMOTE_DOMAINS_VERSION, DomainManifest.lastVersion);
      await PreferencesStore.putNumber('settings', KEY_REMOTE_DOMAINS_TS, DomainManifest.lastTs);

      Logger.i(TAG, `refreshed: version=${DomainManifest.lastVersion} count=${cleaned.length}`);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.w(TAG, `refresh failed: code=${e.code} msg=${e.message}`);
      return false;
    } finally {
      req.destroy();
    }
  }

  /** 清空远程缓存（不动 enabled / manifestUrl）。设置页"重置同步"用。 */
  static async clearRemote(): Promise<void> {
    DomainManifest.remoteDomains = [];
    DomainManifest.lastVersion = '';
    DomainManifest.lastTs = 0;
    await PreferencesStore.remove('settings', KEY_REMOTE_DOMAINS);
    await PreferencesStore.remove('settings', KEY_REMOTE_DOMAINS_VERSION);
    await PreferencesStore.remove('settings', KEY_REMOTE_DOMAINS_TS);
  }

  // ─── 内部 ────────────────────────────────────────────

  /** 严格清洗：去 schema、小写、去尾斜杠、白名单匹配。 */
  private static cleanDomains(input?: string[]): string[] {
    if (input === undefined || !Array.isArray(input)) {
      return [];
    }
    const out: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < input.length; i++) {
      const raw: string = input[i];
      if (typeof raw !== 'string') {
        continue;
      }
      let d: string = raw.toLowerCase().trim();
      d = d.replace(/^https?:\/\//, '').replace(/\/+$/, '');
      // 截掉端口与 path
      const slashIdx: number = d.indexOf('/');
      if (slashIdx >= 0) {
        d = d.substring(0, slashIdx);
      }
      const colonIdx: number = d.indexOf(':');
      if (colonIdx >= 0) {
        d = d.substring(0, colonIdx);
      }
      if (d.length === 0 || d.length > 253) {
        continue;
      }
      if (!DOMAIN_REGEX.test(d)) {
        continue;
      }
      if (seen.has(d)) {
        continue;
      }
      seen.add(d);
      out.push(d);
    }
    return out;
  }
}
