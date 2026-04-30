/*
 * Logger.ets
 * 统一 hilog 包装，避免散落使用 hilog.info(...) 写死 domain/tag。
 *
 * P7：error 级日志会同步写入 ErrorReportStore，以便用户在设置页查看与导出。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorReportStore, ErrorReport } from '../storage/ErrorReportStore';

const DOMAIN: number = 0xC0DE;        // app domain
const DEFAULT_TAG: string = 'HLib';

export class Logger {
  static d(tag: string, msg: string, ...args: Object[]): void {
    hilog.debug(DOMAIN, tag || DEFAULT_TAG, '%{public}s', Logger.format(msg, args));
  }

  static i(tag: string, msg: string, ...args: Object[]): void {
    hilog.info(DOMAIN, tag || DEFAULT_TAG, '%{public}s', Logger.format(msg, args));
  }

  static w(tag: string, msg: string, ...args: Object[]): void {
    hilog.warn(DOMAIN, tag || DEFAULT_TAG, '%{public}s', Logger.format(msg, args));
  }

  static e(tag: string, msg: string, error?: Error | object): void {
    let stack: string | undefined;
    let detail: string = msg;
    let extra: string = '';
    if (error) {
      if (error instanceof Error) {
        extra = error.message;
        stack = error.stack;
        detail = `${msg} | ${extra}\n${stack ?? ''}`;
      } else {
        try {
          extra = JSON.stringify(error);
        } catch {
          extra = String(error);
        }
        detail = `${msg} | ${extra}`;
      }
    }
    hilog.error(DOMAIN, tag || DEFAULT_TAG, '%{public}s', detail);
    // 持久化到 ErrorReportStore（fire-and-forget）
    const report: ErrorReport = {
      ts: new Date().toISOString(),
      level: 'error',
      tag: tag || DEFAULT_TAG,
      message: extra.length > 0 ? `${msg} | ${extra}` : msg,
      stack: stack,
    };
    try {
      ErrorReportStore.append(report);
    } catch {
      // never let logging fail business path
    }
  }

  private static format(msg: string, args: Object[]): string {
    if (!args || args.length === 0) {
      return msg;
    }
    try {
      return `${msg} ${args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ')}`;
    } catch {
      return msg;
    }
  }
}
