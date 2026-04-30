/*
 * ReadingPositionStore.ets
 *
 * 单 key 存所有书籍的阅读进度（0..100 百分比）。
 * 数据形如：{ "[bookId]": 23.45, "[bookId2]": 81.0 }
 *
 * 用单 key 而非 N 个 key，方便 clear 与序列化。
 */

import { PreferencesStore } from './PreferencesStore';

const KEY_POSITIONS: string = 'reading_positions';

export type PositionMap = Record<string, number>;

export class ReadingPositionStore {
  static async loadAll(): Promise<PositionMap> {
    return await PreferencesStore.getObject<PositionMap>('settings', KEY_POSITIONS, {});
  }

  /** 读单本进度，返回 0..100 或 undefined。 */
  static async get(bookId: string): Promise<number | undefined> {
    if (bookId.length === 0) {
      return undefined;
    }
    const map = await ReadingPositionStore.loadAll();
    const v: number | undefined = map[bookId];
    return typeof v === 'number' && Number.isFinite(v) ? v : undefined;
  }

  /** 写单本进度。低于 0 视为 0；高于 100 视为 100。 */
  static async save(bookId: string, percent: number): Promise<void> {
    if (bookId.length === 0) {
      return;
    }
    const map = await ReadingPositionStore.loadAll();
    let p: number = percent;
    if (!Number.isFinite(p)) {
      p = 0;
    }
    if (p < 0) {
      p = 0;
    } else if (p > 100) {
      p = 100;
    }
    map[bookId] = Math.round(p * 100) / 100;
    await PreferencesStore.putObject<PositionMap>('settings', KEY_POSITIONS, map);
  }

  static async remove(bookId: string): Promise<void> {
    if (bookId.length === 0) {
      return;
    }
    const map = await ReadingPositionStore.loadAll();
    if (map[bookId] === undefined) {
      return;
    }
    const next: PositionMap = {};
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (k !== bookId) {
        next[k] = map[k];
      }
    }
    await PreferencesStore.putObject<PositionMap>('settings', KEY_POSITIONS, next);
  }

  static async clear(): Promise<void> {
    await PreferencesStore.remove('settings', KEY_POSITIONS);
  }
}
