/*
 * DownloadHistoryStore.ets
 * 下载历史持久化。键为 bookId（字符串），值为 DownloadHistoryItem。
 */

import { PreferencesStore } from './PreferencesStore';

const KEY_HISTORY: string = 'download_history';

export interface DownloadHistoryItem {
  bookId: string;
  title: string;
  author?: string;
  cover?: string;
  extension?: string;
  filePath: string;
  filesize?: number;
  /** ISO 字符串 */
  downloadedAt: string;
}

export type HistoryMap = Record<string, DownloadHistoryItem>;

export class DownloadHistoryStore {
  static async loadAll(): Promise<HistoryMap> {
    return await PreferencesStore.getObject<HistoryMap>('settings', KEY_HISTORY, {});
  }

  static async upsert(item: DownloadHistoryItem): Promise<void> {
    const map = await DownloadHistoryStore.loadAll();
    map[item.bookId] = item;
    await PreferencesStore.putObject<HistoryMap>('settings', KEY_HISTORY, map);
  }

  static async get(bookId: string): Promise<DownloadHistoryItem | undefined> {
    const map = await DownloadHistoryStore.loadAll();
    return map[bookId];
  }

  static async remove(bookId: string): Promise<void> {
    const map = await DownloadHistoryStore.loadAll();
    if (map[bookId] === undefined) {
      return;
    }
    const next: HistoryMap = {};
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (k !== bookId) {
        next[k] = map[k];
      }
    }
    await PreferencesStore.putObject<HistoryMap>('settings', KEY_HISTORY, next);
  }

  static async clear(): Promise<void> {
    await PreferencesStore.remove('settings', KEY_HISTORY);
  }
}
