/*
 * FavoritesStore.ets
 * 本地收藏 ID 索引（按 bookId 去重）。服务端拉取的列表与之合并。
 */

import { PreferencesStore } from './PreferencesStore';

const KEY_FAVORITES: string = 'favorite_ids';

export class FavoritesStore {
  static async list(): Promise<number[]> {
    return await PreferencesStore.getObject<number[]>('settings', KEY_FAVORITES, []);
  }

  static async add(bookId: number): Promise<void> {
    const ids = await FavoritesStore.list();
    if (ids.indexOf(bookId) >= 0) {
      return;
    }
    ids.push(bookId);
    await PreferencesStore.putObject<number[]>('settings', KEY_FAVORITES, ids);
  }

  static async remove(bookId: number): Promise<void> {
    const ids = await FavoritesStore.list();
    const filtered = ids.filter(id => id !== bookId);
    await PreferencesStore.putObject<number[]>('settings', KEY_FAVORITES, filtered);
  }

  static async has(bookId: number): Promise<boolean> {
    const ids = await FavoritesStore.list();
    return ids.indexOf(bookId) >= 0;
  }

  static async clear(): Promise<void> {
    await PreferencesStore.remove('settings', KEY_FAVORITES);
  }
}
