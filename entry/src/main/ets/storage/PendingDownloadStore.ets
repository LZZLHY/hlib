/*
 * PendingDownloadStore.ets
 *
 * 持久化"未完成"下载任务的元数据。重启后用 request.agent.getTask 重接。
 *
 * 与 DownloadHistoryStore（已完成）成对：
 *   - PendingDownloadStore：进行中 / 暂停 / 失败 等还没收尾的任务
 *   - DownloadHistoryStore：已完成的下载历史
 *
 * 单 key（'pending_downloads'），map: bookId → DownloadTask
 */

import { PreferencesStore } from './PreferencesStore';
import { DownloadTask } from '../model/DownloadTask';

const KEY_PENDING: string = 'pending_downloads';

export type PendingMap = Record<string, DownloadTask>;

export class PendingDownloadStore {
  static async loadAll(): Promise<PendingMap> {
    return await PreferencesStore.getObject<PendingMap>('settings', KEY_PENDING, {});
  }

  static async upsert(item: DownloadTask): Promise<void> {
    if (item.bookId.length === 0) {
      return;
    }
    const map = await PendingDownloadStore.loadAll();
    map[item.bookId] = item;
    await PreferencesStore.putObject<PendingMap>('settings', KEY_PENDING, map);
  }

  static async remove(bookId: string): Promise<void> {
    if (bookId.length === 0) {
      return;
    }
    const map = await PendingDownloadStore.loadAll();
    if (map[bookId] === undefined) {
      return;
    }
    const next: PendingMap = {};
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (k !== bookId) {
        next[k] = map[k];
      }
    }
    await PreferencesStore.putObject<PendingMap>('settings', KEY_PENDING, next);
  }

  static async clear(): Promise<void> {
    await PreferencesStore.remove('settings', KEY_PENDING);
  }
}
