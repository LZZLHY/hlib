/*
 * Format.ets — 通用展示格式化（纯函数）
 *
 * 抽出原先在 DownloadsTab / HistoryPage 重复实现的 formatSize / formatDate，
 * 避免两份实现日后出现口径漂移。
 */

const KB: number = 1024;
const MB: number = 1024 * 1024;
const GB: number = 1024 * 1024 * 1024;

export class Format {
  /** 字节数 → 人类可读（GB/MB/KB/B）。<=0 返回 "—"。 */
  static size(bytes: number): string {
    if (bytes <= 0) {
      return '—';
    }
    if (bytes >= GB) {
      return `${(bytes / GB).toFixed(2)} GB`;
    }
    if (bytes >= MB) {
      return `${(bytes / MB).toFixed(1)} MB`;
    }
    if (bytes >= KB) {
      return `${(bytes / KB).toFixed(0)} KB`;
    }
    return `${bytes} B`;
  }

  /** ISO 时间戳 → YYYY-MM-DD。空串返回空串。 */
  static date(iso: string): string {
    if (iso.length === 0) {
      return '';
    }
    return iso.slice(0, 10);
  }
}
