/*
 * HomeVM.ets
 *
 * 首页门面：并发拉 recommended / popular / recent。
 * 任一接口失败不影响其它（catch 后存入 []）。
 * 状态通过 AppStorage 暴露给 HomeTab 订阅。
 *
 * 内容地区策略（基于 olib 二进制逆向 + 实测）：
 *   - `/eapi/user/book/recommended` 是按账号 profile.language 过滤的（账号绑了中文就出中文）
 *   - `/eapi/book/most-popular` 与 `/eapi/book/recently` 是**全站统计**，
 *     **不按 cookie / Accept-Language / query 过滤**——永远返回全站最热（英文为主）
 *   - 因此当用户指定了内容地区偏好时，"热门"和"近期"必须走 `/eapi/book/search`
 *     （`order=popular` / `order=date` + `languages[]`）模拟 zlib 官方 app 行为
 *
 *   - 设置页 CONTENT_LANG 偏好同步通过 HttpClient.setSiteLanguage 注入
 *     `siteLanguageV2` cookie 与动态 Accept-Language（兜底信号，对 recommended 有效）
 *   - 搜索独立用 SearchOptions.languages，不受 cookie 影响
 */

import { Book } from '../model/Book';
import { ZLibraryClient, SearchOptions, SearchPage } from '../api/ZLibraryClient';
import { LANGUAGE_FILTERS, FilterItem } from '../api/SearchFilters';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { PreferencesStore } from '../storage/PreferencesStore';
import { Logger } from '../utils/Logger';

const TAG: string = 'HomeVM';

export class HomeVM {
  /** 全量并发刷新。 */
  static async refresh(): Promise<void> {
    AppStorage.setOrCreate<boolean>(AppStorageKeys.HOME_LOADING, true);
    // 切换内容地区 / 主动刷新时先清空三个数据 key，
    // 强制 @StorageLink 触发一次 UI 重渲（避免数组整体替换时偶发不刷新）。
    AppStorage.setOrCreate<Book[]>(AppStorageKeys.HOME_RECOMMENDED, []);
    AppStorage.setOrCreate<Book[]>(AppStorageKeys.HOME_POPULAR, []);
    AppStorage.setOrCreate<Book[]>(AppStorageKeys.HOME_RECENT, []);
    try {
      const langs: string[] | undefined = await HomeVM.resolveLanguages();
      const langLog: string = langs !== undefined ? langs.join(',') : 'all';
      Logger.i(TAG, `home fetch: lang=${langLog}`);

      // 推荐：始终调 user/book/recommended——zlib 服务端按账号 profile.language 给个性化推荐，
      //       与内容地区偏好独立（地区只控制热门/近期）。
      // 热门 / 近期：有地区偏好走 search 模拟（按 query 过滤）；无偏好回退原 endpoint。
      const recommendedTask: Promise<Book[]> =
        ZLibraryClient.instance.getUserRecommended().catch((e: Object) => HomeVM.empty('recommended', e));

      const popularTask: Promise<Book[]> = langs !== undefined
        ? ZLibraryClient.instance.getPopularByLanguage(langs).catch((e: Object) => HomeVM.empty('popular', e))
        : ZLibraryClient.instance.getMostPopular().catch((e: Object) => HomeVM.empty('popular', e));

      const recentTask: Promise<Book[]> = langs !== undefined
        ? ZLibraryClient.instance.getRecentByLanguage(langs).catch((e: Object) => HomeVM.empty('recent', e))
        : ZLibraryClient.instance.getRecently().catch((e: Object) => HomeVM.empty('recent', e));

      const tasks: Promise<Book[]>[] = [recommendedTask, popularTask, recentTask];
      const results: Book[][] = await Promise.all(tasks);
      AppStorage.setOrCreate<Book[]>(AppStorageKeys.HOME_RECOMMENDED, results[0]);
      AppStorage.setOrCreate<Book[]>(AppStorageKeys.HOME_POPULAR, results[1]);
      AppStorage.setOrCreate<Book[]>(AppStorageKeys.HOME_RECENT, results[2]);
      Logger.i(TAG, `home refreshed: rec=${results[0].length} pop=${results[1].length} rec2=${results[2].length}`);
    } finally {
      AppStorage.setOrCreate<boolean>(AppStorageKeys.HOME_LOADING, false);
    }
  }

  /**
   * 读取 CONTENT_LANG 偏好并转成 API 的 languages 数组。
   * - '' / 'all' → undefined（不过滤；走原 endpoint）
   * - 'chinese'/'english'/... → 单值数组（走 search-based endpoint）
   */
  private static async resolveLanguages(): Promise<string[] | undefined> {
    const key: string = await PreferencesStore.getString('settings', AppStorageKeys.CONTENT_LANG, '');
    if (key.length === 0 || key === 'all') {
      return undefined;
    }
    for (let i = 0; i < LANGUAGE_FILTERS.length; i++) {
      const f: FilterItem = LANGUAGE_FILTERS[i];
      if (f.key === key && f.apiValue !== undefined) {
        return [f.apiValue];
      }
    }
    return undefined;
  }

  static getRecommended(): Book[] {
    const v: Book[] | undefined = AppStorage.get<Book[]>(AppStorageKeys.HOME_RECOMMENDED);
    return v !== undefined ? v : [];
  }

  static getPopular(): Book[] {
    const v: Book[] | undefined = AppStorage.get<Book[]>(AppStorageKeys.HOME_POPULAR);
    return v !== undefined ? v : [];
  }

  static getRecent(): Book[] {
    const v: Book[] | undefined = AppStorage.get<Book[]>(AppStorageKeys.HOME_RECENT);
    return v !== undefined ? v : [];
  }

  /**
   * 分页加载更多（热度 / 上传日期 tab）。
   * section: 1 = popular, 2 = recent
   */
  static async loadMoreSection(section: number, page: number): Promise<LoadMoreResult> {
    const langs: string[] | undefined = await HomeVM.resolveLanguages();
    const order: string = section === 1 ? 'popular' : 'date';
    const opts: SearchOptions = {
      order: order,
      page: page,
      limit: 30,
    };
    if (langs !== undefined) {
      opts.languages = langs;
    }
    const result: SearchPage = await ZLibraryClient.instance.search(opts);
    const hasMore: boolean = result.currentPage < result.totalPages;
    const out: LoadMoreResult = { books: result.books, hasMore: hasMore };
    return out;
  }

  private static empty(label: string, err: Object): Book[] {
    const e: Error = err as Error;
    Logger.w(TAG, `fetch ${label} failed: ${e.message}`);
    return [];
  }
}

export interface LoadMoreResult {
  books: Book[];
  hasMore: boolean;
}
