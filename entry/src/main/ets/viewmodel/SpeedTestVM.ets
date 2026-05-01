/*
 * SpeedTestVM.ets
 *
 * 镜像并发测速：
 *   - 6 路并行 ping，结果实时回写 AppStorage[SPEED_RESULTS]，UI 即时刷新。
 *   - 测完按延迟升序排序，写入 PreferencesStore 持久化。
 *   - 同时只允许一次测速（重复调用时返回当前结果）。
 *
 * 调用约定：
 *   - SplashPage 启动后台 testAll(); 不阻塞引导。
 *   - DomainSelectorDialog 提供"重测"按钮 -> testAll(force=true)。
 *   - 设置页"重新测速" -> testAll(force=true)。
 */

import { DomainTestResult } from '../model/DomainTestResult';
import { DomainManifest } from '../api/DomainManifest';
import { HttpClient } from '../api/HttpClient';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { PreferencesStore } from '../storage/PreferencesStore';
import { Logger } from '../utils/Logger';

const TAG: string = 'SpeedTestVM';
const KEY_RESULTS: string = 'speed_test_results';
const KEY_RESULTS_TS: string = 'speed_test_results_ts';
const CONCURRENCY: number = 6;
const PING_TIMEOUT_MS: number = 6000;
const SLOW_LATENCY: number = 999999; // 排序兜底
/** 缓存 TTL：6 小时。超过后 testAll(false) 会强制重测。 */
const RESULTS_TTL_MS: number = 6 * 60 * 60 * 1000;

export class SpeedTestVM {
  private static running: boolean = false;

  static isRunning(): boolean {
    return SpeedTestVM.running;
  }

  /** 从持久层加载上次结果 -> AppStorage。启动时调用一次让 UI 立即有数据。 */
  static async loadCached(): Promise<DomainTestResult[]> {
    const arr: DomainTestResult[] = await PreferencesStore.getObject<DomainTestResult[]>(
      'settings',
      KEY_RESULTS,
      [] as DomainTestResult[]
    );
    AppStorage.setOrCreate<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS, arr);

    const ts: number = await PreferencesStore.getNumber('settings', KEY_RESULTS_TS, 0);
    AppStorage.setOrCreate<number>(AppStorageKeys.SPEED_LAST_TS, ts);
    return arr;
  }

  /** 当前 AppStorage 快照。 */
  static getResults(): DomainTestResult[] {
    const r: DomainTestResult[] | undefined = AppStorage.get<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS);
    return r !== undefined ? r : [];
  }

  /** 上次测速完成时间戳（ms）；0 表示从未测过。 */
  static getLastTs(): number {
    const t: number | undefined = AppStorage.get<number>(AppStorageKeys.SPEED_LAST_TS);
    return t !== undefined ? t : 0;
  }

  /** 缓存是否在 TTL 有效期内。 */
  static isCacheFresh(): boolean {
    const ts: number = SpeedTestVM.getLastTs();
    return ts > 0 && (Date.now() - ts) < RESULTS_TTL_MS;
  }

  /**
   * 全量测速。
   *   - force=true：总是重测。
   *   - force=false：若缓存命中当前域列表且在 6h TTL 内直接返回；否则继续测速。
   */
  static async testAll(force: boolean = true, domains?: string[]): Promise<DomainTestResult[]> {
    if (SpeedTestVM.running) {
      Logger.w(TAG, 'already running, skip');
      return SpeedTestVM.getResults();
    }
    const list: string[] = domains !== undefined ? domains.slice() : DomainManifest.getActiveDomains();

    if (!force) {
      const cached: DomainTestResult[] = SpeedTestVM.getResults();
      if (cached.length === list.length && SpeedTestVM.isCacheFresh()) {
        Logger.i(TAG, `cache hit (age=${Date.now() - SpeedTestVM.getLastTs()} ms), skip`);
        return cached;
      }
      if (cached.length === list.length) {
        Logger.i(TAG, `cache stale (age=${Date.now() - SpeedTestVM.getLastTs()} ms), retesting`);
      }
    }

    SpeedTestVM.running = true;
    try {
      // 初始化结果数组（latencyMs=null 表示未测）
      const results: DomainTestResult[] = [];
      for (let i = 0; i < list.length; i++) {
        results.push(new DomainTestResult(list[i], null));
      }
      AppStorage.setOrCreate<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS, results.slice());

      // 共享游标 + N 路并发
      let nextIdx: number = 0;
      const worker = async (): Promise<void> => {
        while (true) {
          const i: number = nextIdx;
          nextIdx = nextIdx + 1;
          if (i >= list.length) {
            return;
          }
          const domain: string = list[i];
          const ms: number = await HttpClient.instance.ping(domain, PING_TIMEOUT_MS);
          results[i].latencyMs = ms;
          // 回写一次让 UI 增量刷新
          AppStorage.setOrCreate<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS, results.slice());
        }
      };

      const workers: Promise<void>[] = [];
      for (let i = 0; i < CONCURRENCY; i++) {
        workers.push(worker());
      }
      await Promise.all(workers);

      // 排序：可用域名按延迟升序，失败统一在末尾
      results.sort((a: DomainTestResult, b: DomainTestResult): number => {
        const la: number = a.latencyMs !== null && a.latencyMs > 0 ? a.latencyMs : SLOW_LATENCY;
        const lb: number = b.latencyMs !== null && b.latencyMs > 0 ? b.latencyMs : SLOW_LATENCY;
        return la - lb;
      });

      AppStorage.setOrCreate<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS, results.slice());
      await PreferencesStore.putObject<DomainTestResult[]>('settings', KEY_RESULTS, results);
      const now: number = Date.now();
      AppStorage.setOrCreate<number>(AppStorageKeys.SPEED_LAST_TS, now);
      await PreferencesStore.putNumber('settings', KEY_RESULTS_TS, now);
      const fastestDomain: string = results.length > 0 ? results[0].domain : 'n/a';
      Logger.i(TAG, `speed test done: ${results.length} domains, fastest=${fastestDomain}`);
      return results;
    } finally {
      SpeedTestVM.running = false;
    }
  }

  /** 取最佳域名。无可用结果时返回 null。 */
  static fastest(): DomainTestResult | null {
    const list: DomainTestResult[] = SpeedTestVM.getResults();
    for (let i = 0; i < list.length; i++) {
      const ms: number | null = list[i].latencyMs;
      if (ms !== null && ms > 0) {
        return list[i];
      }
    }
    return null;
  }
}
