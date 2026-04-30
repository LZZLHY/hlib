/*
 * FavoritesVM.ets
 *
 * 收藏面：
 *   - 本地 ID 索引（FavoritesStore，preferences 持久化）
 *   - 服务端同步（saveBook / unsaveBook / getUserSaved）
 *   - AppStorage[FAVORITE_IDS]: number[] 用于 UI 订阅
 *   - AppStorage[FAVORITE_BOOKS]: Book[] 用于列表展示
 *
 * 服务端调用失败不影响本地状态（离线收藏可读）。
 */

import { Book, BookJson } from '../model/Book';
import { ZLibraryClient } from '../api/ZLibraryClient';
import { FavoritesStore } from '../storage/FavoritesStore';
import { PreferencesStore } from '../storage/PreferencesStore';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Logger } from '../utils/Logger';

const TAG: string = 'FavoritesVM';
const BOOKS_CACHE_KEY: string = 'favorite_books_cache';

export class FavoritesVM {
  /** 启动时把本地 ID + 缓存的 Book 列表刷到 AppStorage，确保重启后不为空。 */
  static async init(): Promise<void> {
    try {
      const ids: number[] = await FavoritesStore.list();
      AppStorage.setOrCreate<number[]>(AppStorageKeys.FAVORITE_IDS, ids);
      // 从本地缓存恢复 Book 列表（即使服务端不可达也能显示）
      const cachedJson: BookJson[] = await PreferencesStore.getObject<BookJson[]>('settings', BOOKS_CACHE_KEY, []);
      if (cachedJson.length > 0) {
        const books: Book[] = Book.fromJsonList(cachedJson as object[]);
        AppStorage.setOrCreate<Book[]>(AppStorageKeys.FAVORITE_BOOKS, books);
        Logger.i(TAG, `restored ${books.length} cached favorite books`);
      } else if (ids.length > 0) {
        // 有 ID 但无缓存 Book → 旧版本遗留的孤立 ID，清除
        Logger.w(TAG, `init: ${ids.length} orphaned IDs without book cache, clearing`);
        await FavoritesStore.clear();
        AppStorage.setOrCreate<number[]>(AppStorageKeys.FAVORITE_IDS, []);
      }
    } catch (e) {
      Logger.w(TAG, `init failed: ${(e as Error).message}`);
    }
  }

  /** 同步 ID 集合到 AppStorage。 */
  private static async syncIdsToStorage(): Promise<void> {
    const ids: number[] = await FavoritesStore.list();
    AppStorage.setOrCreate<number[]>(AppStorageKeys.FAVORITE_IDS, ids);
  }

  /** 当前书是否被收藏（本地源）。 */
  static async isFavorite(bookId: number): Promise<boolean> {
    return await FavoritesStore.has(bookId);
  }

  /** 收藏。本地立即写 + 乐观更新 FAVORITE_BOOKS；服务端尽力。 */
  static async add(book: Book): Promise<void> {
    await FavoritesStore.add(book.id);
    await FavoritesVM.syncIdsToStorage();
    // 乐观更新：将整本 Book 对象即时加到展示列表头部
    const current: Book[] | undefined = AppStorage.get<Book[]>(AppStorageKeys.FAVORITE_BOOKS);
    const list: Book[] = current !== undefined ? current : [];
    // 避免重复
    const exists: boolean = list.some((b: Book): boolean => b.id === book.id);
    if (!exists) {
      const updated: Book[] = [book, ...list];
      AppStorage.setOrCreate<Book[]>(AppStorageKeys.FAVORITE_BOOKS, updated);
      FavoritesVM.persistBooksCache(updated);
    }
    try {
      await ZLibraryClient.instance.saveBook(book.id, book.hash);
      // 服务端成功后后台刷新完整列表（保证数据一致）
      FavoritesVM.refresh().catch((e: Object): void => {
        Logger.w(TAG, `bg refresh after add: ${(e as Error).message}`);
      });
    } catch (e) {
      Logger.w(TAG, `saveBook(${book.id}) failed: ${(e as Error).message}`);
    }
  }

  /** 取消收藏。 */
  static async remove(bookId: number): Promise<void> {
    // 先查 hash（unsave 端点需要），在从列表移除之前
    const current: Book[] | undefined = AppStorage.get<Book[]>(AppStorageKeys.FAVORITE_BOOKS);
    let hash: string | undefined = undefined;
    if (current !== undefined) {
      for (let i = 0; i < current.length; i++) {
        if (current[i].id === bookId) {
          hash = current[i].hash;
          break;
        }
      }
    }
    await FavoritesStore.remove(bookId);
    await FavoritesVM.syncIdsToStorage();
    // 乐观更新：从展示列表中立即移除
    if (current !== undefined) {
      const updated: Book[] = current.filter((b: Book): boolean => b.id !== bookId);
      AppStorage.setOrCreate<Book[]>(AppStorageKeys.FAVORITE_BOOKS, updated);
      FavoritesVM.persistBooksCache(updated);
    }
    try {
      await ZLibraryClient.instance.unsaveBook(bookId, hash);
      FavoritesVM.refresh().catch((e: Object): void => {
        Logger.w(TAG, `bg refresh after remove: ${(e as Error).message}`);
      });
    } catch (e) {
      Logger.w(TAG, `unsaveBook(${bookId}) failed: ${(e as Error).message}`);
    }
  }

  /** 切换收藏态。返回新状态（true=已收藏，false=已取消）。 */
  static async toggle(book: Book): Promise<boolean> {
    const has: boolean = await FavoritesStore.has(book.id);
    if (has) {
      await FavoritesVM.remove(book.id);
      return false;
    }
    await FavoritesVM.add(book);
    return true;
  }

  /** 拉服务端 saved 列表 + 合并本地。 */
  static async refresh(): Promise<Book[]> {
    Logger.i(TAG, `refresh: fetching from server...`);
    let remote: Book[];
    try {
      remote = await ZLibraryClient.instance.getUserSaved(200);
    } catch (e) {
      Logger.w(TAG, `refresh: getUserSaved failed: ${(e as Error).message}`);
      // 服务端不可达时保留本地缓存
      const current: Book[] | undefined = AppStorage.get<Book[]>(AppStorageKeys.FAVORITE_BOOKS);
      return current !== undefined ? current : [];
    }
    Logger.i(TAG, `refresh: server returned ${remote.length} books`);
    const local: number[] = await FavoritesStore.list();
    Logger.i(TAG, `refresh: local has ${local.length} IDs`);

    // 服务端返回空但本地有收藏 → 服务端 save 可能失败过(404)，保留本地缓存
    if (remote.length === 0 && local.length > 0) {
      Logger.w(TAG, `refresh: server empty but local has ${local.length} IDs, keeping local cache`);
      const current: Book[] | undefined = AppStorage.get<Book[]>(AppStorageKeys.FAVORITE_BOOKS);
      return current !== undefined ? current : [];
    }

    // 同步：服务端有但本地没有的，加到本地
    for (let i = 0; i < remote.length; i++) {
      const b: Book = remote[i];
      if (local.indexOf(b.id) < 0) {
        await FavoritesStore.add(b.id);
      }
    }
    await FavoritesVM.syncIdsToStorage();
    AppStorage.setOrCreate<Book[]>(AppStorageKeys.FAVORITE_BOOKS, remote);
    // 持久化到本地缓存，下次重启可直接使用
    FavoritesVM.persistBooksCache(remote);
    return remote;
  }

  /** 将 Book 列表写入本地缓存（异步，不阻塞调用方）。 */
  private static persistBooksCache(books: Book[]): void {
    PreferencesStore.putObject<Book[]>('settings', BOOKS_CACHE_KEY, books).catch((e: Error): void => {
      Logger.w(TAG, `persistBooksCache failed: ${e.message}`);
    });
  }
}
