/*
 * DownloadRepository.ets — 下载任务列表与历史的持久化/状态读写
 *
 * 从 DownloadVM 抽出纯数据层：
 *   - 进行中/失败任务：AppStorage[DOWNLOAD_TASKS]
 *   - 已完成历史：DownloadHistoryStore（preferences）+ AppStorage[DOWNLOAD_HISTORY] 镜像
 * DownloadVM 只保留下载引擎与重试编排，数据 CRUD 全部委托到这里。
 */

import { AppStorageKeys } from '../../storage/AppStorageKeys';
import { DownloadTask } from '../../model/DownloadTask';
import { DownloadHistoryStore, DownloadHistoryItem } from '../../storage/DownloadHistoryStore';
import { Logger } from '../../utils/Logger';

const TAG: string = 'DownloadRepository';

export class DownloadRepository {
  // ─── 进行中任务列表 ───

  static getList(): DownloadTask[] {
    const list: DownloadTask[] | undefined = AppStorage.get<DownloadTask[]>(AppStorageKeys.DOWNLOAD_TASKS);
    return list !== undefined ? list : [];
  }

  static setList(list: DownloadTask[]): void {
    AppStorage.setOrCreate<DownloadTask[]>(AppStorageKeys.DOWNLOAD_TASKS, list);
  }

  static addToList(dt: DownloadTask): void {
    const list: DownloadTask[] = DownloadRepository.getList();
    const filtered: DownloadTask[] = list.filter((t: DownloadTask): boolean => t.bookId !== dt.bookId);
    filtered.unshift(dt);
    DownloadRepository.setList(filtered);
  }

  static updateInList(dt: DownloadTask): void {
    const list: DownloadTask[] = DownloadRepository.getList();
    const next: DownloadTask[] = list.map((t: DownloadTask): DownloadTask => {
      return t.bookId === dt.bookId ? dt : t;
    });
    DownloadRepository.setList(next);
  }

  static removeFromList(bookId: string): void {
    const list: DownloadTask[] = DownloadRepository.getList();
    const next: DownloadTask[] = list.filter((t: DownloadTask): boolean => t.bookId !== bookId);
    DownloadRepository.setList(next);
  }

  static findActive(bookId: string): DownloadTask | undefined {
    const list: DownloadTask[] = DownloadRepository.getList();
    return list.find((t: DownloadTask): boolean => t.bookId === bookId);
  }

  static cloneTask(t: DownloadTask): DownloadTask {
    const c: DownloadTask = {
      bookId: t.bookId,
      hashId: t.hashId,
      title: t.title,
      author: t.author,
      cover: t.cover,
      extension: t.extension,
      url: t.url,
      filePath: t.filePath,
      status: t.status,
      progress: t.progress,
      receivedBytes: t.receivedBytes,
      totalBytes: t.totalBytes,
      errorMessage: t.errorMessage,
      createdAt: t.createdAt,
      taskId: t.taskId,
    };
    return c;
  }

  static markFailed(dt: DownloadTask, msg: string): void {
    const next: DownloadTask = DownloadRepository.cloneTask(dt);
    next.status = 'failed';
    next.errorMessage = msg;
    DownloadRepository.updateInList(next);
  }

  // ─── 已完成历史 ───

  /** 从持久层加载历史 → AppStorage（按时间倒序）。返回排序后的列表。 */
  static async loadHistoryToStorage(): Promise<DownloadHistoryItem[]> {
    const map = await DownloadHistoryStore.loadAll();
    const items: DownloadHistoryItem[] = [];
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      items.push(map[keys[i]]);
    }
    items.sort((a: DownloadHistoryItem, b: DownloadHistoryItem): number => {
      return a.downloadedAt < b.downloadedAt ? 1 : -1;
    });
    AppStorage.setOrCreate<DownloadHistoryItem[]>(AppStorageKeys.DOWNLOAD_HISTORY, items);
    return items;
  }

  static async refreshHistory(): Promise<DownloadHistoryItem[]> {
    return await DownloadRepository.loadHistoryToStorage();
  }

  static async removeHistory(bookId: string): Promise<void> {
    await DownloadHistoryStore.remove(bookId);
    await DownloadRepository.refreshHistory();
  }

  static async clearHistory(): Promise<void> {
    await DownloadHistoryStore.clear();
    await DownloadRepository.refreshHistory();
  }

  /** 完成态搬入历史并刷新镜像。 */
  static async persistCompleted(dt: DownloadTask): Promise<void> {
    try {
      const item: DownloadHistoryItem = {
        bookId: dt.bookId,
        title: dt.title,
        author: dt.author,
        cover: dt.cover,
        extension: dt.extension,
        filePath: dt.filePath,
        filesize: dt.totalBytes,
        downloadedAt: new Date().toISOString(),
      };
      await DownloadHistoryStore.upsert(item);
      await DownloadRepository.refreshHistory();
    } catch (e) {
      Logger.w(TAG, `persistCompleted failed: ${(e as Error).message}`);
    }
  }
}
