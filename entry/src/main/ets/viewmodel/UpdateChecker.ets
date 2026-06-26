/*
 * UpdateChecker.ets — 检查更新（按 versionCode 比对）
 *
 * 方式（对齐 AMCL 标准）：
 *   - 仓库内维护 `docs/update.json`（GitHub 托管），声明最新 versionCode / versionName /
 *     releaseUrl / notes，与 AppScope/app.json5 的 versionCode 同数轴。
 *   - App 拉取该 manifest，与本地 versionCode（bundleManager 读取）比对；
 *     远程 > 本地即有新版，提示用户并打开 Release 页。
 *   - 拉取走「直连 raw + 国内代理镜像 + GitHub Pages 兜底」多候选，解决国内直连 raw 被阻断。
 *
 * 维护约定：每次发版把 update.json 的 versionCode/versionName 同步到 app.json5 与 CHANGELOG.md。
 */

import { http } from '@kit.NetworkKit';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';
import { PreferencesStore } from '../storage/PreferencesStore';
import { AppStorageKeys } from '../storage/AppStorageKeys';

const TAG: string = 'UpdateChecker';

/** 远程版本清单（docs/update.json）。 */
export interface UpdateManifest {
  versionCode: number;
  versionName: string;
  releaseUrl: string;
  notes?: string;
  changelogUrl?: string;
}

/** 检查结果。 */
export interface UpdateCheckResult {
  /** 是否成功取到清单。 */
  ok: boolean;
  /** 是否有新版本（latest > current）。 */
  hasUpdate: boolean;
  /** 本地 versionCode。 */
  current: number;
  /** 远程 versionCode。 */
  latest: number;
  manifest?: UpdateManifest;
}

const RAW_PATH: string = 'LZZLHY/hlib/master/docs/update.json';
/** 候选 URL：直连 + 代理镜像 + Pages 兜底，按顺序首个成功即用。 */
const CANDIDATE_URLS: string[] = [
  `https://raw.githubusercontent.com/${RAW_PATH}`,
  `https://ghfast.top/https://raw.githubusercontent.com/${RAW_PATH}`,
  `https://gh-proxy.com/https://raw.githubusercontent.com/${RAW_PATH}`,
  `https://ghproxy.net/https://raw.githubusercontent.com/${RAW_PATH}`,
  'https://lzzlhy.github.io/hlib/update.json',
];
const DEFAULT_RELEASE_URL: string = 'https://github.com/LZZLHY/hlib/releases';
const FETCH_TIMEOUT_MS: number = 8000;

/** 自动检查节流：24 小时内最多联网一次。 */
const AUTO_CHECK_THROTTLE_MS: number = 24 * 60 * 60 * 1000;
const KEY_LAST_TS: string = 'update_last_check_ts';
const KEY_AVAIL: string = 'update_available';
const KEY_LATEST_NAME: string = 'update_latest_name';

export class UpdateChecker {
  /** 本地 versionCode（与 app.json5 一致）。失败回退 0。 */
  static async currentVersionCode(): Promise<number> {
    try {
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT,
      );
      return info.versionCode;
    } catch (e) {
      Logger.w(TAG, `read versionCode failed: ${(e as Error).message}`);
      return 0;
    }
  }

  /** 检查更新；永不抛异常。 */
  static async check(): Promise<UpdateCheckResult> {
    const current: number = await UpdateChecker.currentVersionCode();
    const manifest: UpdateManifest | null = await UpdateChecker.fetchManifest();
    if (manifest === null) {
      const fail: UpdateCheckResult = { ok: false, hasUpdate: false, current: current, latest: 0 };
      return fail;
    }
    const latest: number = manifest.versionCode;
    const result: UpdateCheckResult = {
      ok: true,
      hasUpdate: latest > current,
      current: current,
      latest: latest,
      manifest: manifest,
    };
    Logger.i(TAG, `check: current=${current} latest=${latest} hasUpdate=${result.hasUpdate}`);
    return result;
  }

  /** 用系统浏览器打开 Release 页。 */
  static async openRelease(ctx: common.UIAbilityContext, url: string): Promise<void> {
    const target: string = url.length > 0 ? url : DEFAULT_RELEASE_URL;
    const want: Want = { action: 'ohos.want.action.viewData', uri: target };
    await ctx.startAbility(want);
  }

  /**
   * 启动时静默自动检查（24h 节流）。永不抛异常。
   * 流程：① 先把上次缓存的红点状态回灌 AppStorage（即时显示，无需联网）；
   *      ② 距上次检查不足 24h 直接返回；③ 否则联网刷新并写回缓存 + AppStorage。
   * UI 通过 @StorageProp(UPDATE_AVAILABLE / UPDATE_LATEST_NAME) 订阅显示小红点。
   */
  static async autoCheck(): Promise<void> {
    try {
      // ① 缓存回灌（即时红点）
      const cachedAvail: boolean = await PreferencesStore.getBoolean('settings', KEY_AVAIL, false);
      const cachedName: string = await PreferencesStore.getString('settings', KEY_LATEST_NAME, '');
      AppStorage.setOrCreate<boolean>(AppStorageKeys.UPDATE_AVAILABLE, cachedAvail);
      AppStorage.setOrCreate<string>(AppStorageKeys.UPDATE_LATEST_NAME, cachedName);

      // ② 节流
      const last: number = await PreferencesStore.getNumber('settings', KEY_LAST_TS, 0);
      if (Date.now() - last < AUTO_CHECK_THROTTLE_MS) {
        Logger.i(TAG, `autoCheck throttled (age=${Date.now() - last}ms)`);
        return;
      }

      // ③ 联网刷新
      const r: UpdateCheckResult = await UpdateChecker.check();
      if (!r.ok) {
        // 失败不更新时间戳，下次启动继续尝试
        return;
      }
      await PreferencesStore.putNumber('settings', KEY_LAST_TS, Date.now());
      await PreferencesStore.putBoolean('settings', KEY_AVAIL, r.hasUpdate);
      AppStorage.setOrCreate<boolean>(AppStorageKeys.UPDATE_AVAILABLE, r.hasUpdate);
      const name: string = r.hasUpdate && r.manifest !== undefined ? r.manifest.versionName : '';
      await PreferencesStore.putString('settings', KEY_LATEST_NAME, name);
      AppStorage.setOrCreate<string>(AppStorageKeys.UPDATE_LATEST_NAME, name);
      Logger.i(TAG, `autoCheck done: hasUpdate=${r.hasUpdate} latest=${name}`);
    } catch (e) {
      Logger.w(TAG, `autoCheck failed: ${(e as Error).message}`);
    }
  }

  // ─── 内部 ───────────────────────────────────────────

  private static async fetchManifest(): Promise<UpdateManifest | null> {
    for (let i = 0; i < CANDIDATE_URLS.length; i++) {
      const m: UpdateManifest | null = await UpdateChecker.fetchOne(CANDIDATE_URLS[i]);
      if (m !== null) {
        return m;
      }
    }
    return null;
  }

  private static async fetchOne(url: string): Promise<UpdateManifest | null> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/json' },
        connectTimeout: FETCH_TIMEOUT_MS,
        readTimeout: FETCH_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      };
      const resp: http.HttpResponse = await req.request(url, opts);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        return null;
      }
      const text: string = typeof resp.result === 'string' ? resp.result : '';
      return UpdateChecker.parse(text);
    } catch (e) {
      Logger.d(TAG, `fetch ${url} failed: ${(e as Error).message}`);
      return null;
    } finally {
      req.destroy();
    }
  }

  private static parse(text: string): UpdateManifest | null {
    const trimmed: string = text.trim();
    if (trimmed.length === 0 || trimmed.charAt(0) !== '{') {
      return null;
    }
    try {
      const json: UpdateManifest = JSON.parse(trimmed) as UpdateManifest;
      if (typeof json.versionCode !== 'number' || !Number.isFinite(json.versionCode)) {
        return null;
      }
      const out: UpdateManifest = {
        versionCode: Math.trunc(json.versionCode),
        versionName: typeof json.versionName === 'string' ? json.versionName : '',
        releaseUrl: typeof json.releaseUrl === 'string' && json.releaseUrl.length > 0
          ? json.releaseUrl
          : DEFAULT_RELEASE_URL,
        notes: typeof json.notes === 'string' ? json.notes : undefined,
        changelogUrl: typeof json.changelogUrl === 'string' ? json.changelogUrl : undefined,
      };
      return out;
    } catch (e) {
      Logger.d(TAG, `parse manifest failed: ${(e as Error).message}`);
      return null;
    }
  }
}
