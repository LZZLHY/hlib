/*
 * ErrorReportStore.ets
 *
 * 错误日志环形缓冲：最多保留最近 50 条。
 * 写入来源：
 *   1) Logger.e()         —— 业务层显式记录
 *   2) errorManager.on()  —— UIAbility 全局未捕获异常
 *
 * 读取来源：SettingsPage 的"错误日志"入口（导出 / 清空）。
 *
 * 单 key（'error_reports'），数组形式。
 */

import { PreferencesStore } from './PreferencesStore';

const KEY_REPORTS: string = 'error_reports';
const MAX_ENTRIES: number = 50;

export interface ErrorReport {
  /** ISO 时间戳 */
  ts: string;
  /** 'error' | 'warn' */
  level: string;
  /** 业务 tag 或异常类名 */
  tag: string;
  /** 主消息 */
  message: string;
  /** 可选堆栈 */
  stack?: string;
}

export class ErrorReportStore {
  /** 内存缓存，避免每次写盘都先读盘。在 init 时填充。 */
  private static cache: ErrorReport[] = [];
  private static loaded: boolean = false;

  /** 启动时调用一次，把磁盘数据加载到内存缓存。失败容错。 */
  static async init(): Promise<void> {
    try {
      const list: ErrorReport[] = await PreferencesStore.getObject<ErrorReport[]>(
        'settings', KEY_REPORTS, [],
      );
      ErrorReportStore.cache = Array.isArray(list) ? list : [];
      ErrorReportStore.loaded = true;
    } catch {
      ErrorReportStore.cache = [];
      ErrorReportStore.loaded = true;
    }
  }

  static getAll(): ErrorReport[] {
    return ErrorReportStore.cache.slice();
  }

  /** 追加一条；同步更新内存，异步写盘。 */
  static append(entry: ErrorReport): void {
    if (!ErrorReportStore.loaded) {
      // init 还没跑就有错，先入内存
      ErrorReportStore.cache = [];
      ErrorReportStore.loaded = true;
    }
    ErrorReportStore.cache.unshift(entry);
    if (ErrorReportStore.cache.length > MAX_ENTRIES) {
      ErrorReportStore.cache = ErrorReportStore.cache.slice(0, MAX_ENTRIES);
    }
    // fire-and-forget
    PreferencesStore.putObject<ErrorReport[]>('settings', KEY_REPORTS, ErrorReportStore.cache)
      .catch((): void => {});
  }

  static async clear(): Promise<void> {
    ErrorReportStore.cache = [];
    await PreferencesStore.remove('settings', KEY_REPORTS);
  }
}
