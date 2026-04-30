/*
 * BookDetailVM.ets
 *
 * 详情页面：
 *   - load(id, hash) 并发拉取 detail + similar + 是否收藏
 *   - 不入 AppStorage（每次进详情都重新加载，避免缓存陈旧的 description / readOnlineUrl）
 */

import { Book } from '../model/Book';
import { ZLibraryClient } from '../api/ZLibraryClient';
import { FavoritesStore } from '../storage/FavoritesStore';
import { Logger } from '../utils/Logger';

const TAG: string = 'BookDetailVM';

export interface BookDetailLoadResult {
  detail: Book;
  similar: Book[];
  favorited: boolean;
}

export class BookDetailVM {
  static async load(bookId: string, hashId: string): Promise<BookDetailLoadResult> {
    const idNum: number = Number.parseInt(bookId, 10);
    // 并发：detail / similar / favorited
    const detailP: Promise<Book> = ZLibraryClient.instance.getBookInfo(bookId, hashId);
    const similarP: Promise<Book[]> = BookDetailVM.safeSimilar(bookId, hashId);
    const favP: Promise<boolean> = FavoritesStore.has(idNum);

    const detail: Book = await detailP;
    const similar: Book[] = await similarP;
    const favorited: boolean = await favP;
    const r: BookDetailLoadResult = { detail: detail, similar: similar, favorited: favorited };
    return r;
  }

  /** similar 失败不影响 detail。 */
  private static async safeSimilar(bookId: string, hashId: string): Promise<Book[]> {
    try {
      return await ZLibraryClient.instance.similar(bookId, hashId);
    } catch (e) {
      Logger.w(TAG, `similar failed: ${(e as Error).message}`);
      return [];
    }
  }
}
