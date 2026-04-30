/*
 * SearchVM.ets
 *
 * 搜索门面：把 ZLibraryClient.search 包装成更友好的入口；
 * 状态（query / books / page / total / loading）由 SearchTab 自己用 @State 维护，
 * 因为搜索结果是临时的、不需要全局共享。
 *
 * 这里只做：参数标准化、异常归一为字符串文案。
 */

import { ZLibraryClient, SearchOptions, SearchPage } from '../api/ZLibraryClient';
import { HttpStatusError } from '../api/ApiTypes';
import { ErrorHelper } from '../utils/ErrorHelper';
import { Logger } from '../utils/Logger';

const TAG: string = 'SearchVM';

export class SearchVM {
  /** 单次搜索调用；上层捕获 ApiError 自行决定弹窗。 */
  static async run(options: SearchOptions): Promise<SearchPage> {
    Logger.i(TAG, `search: q=${options.message} page=${options.page} order=${options.order}`);
    const page: SearchPage = await ZLibraryClient.instance.search(options);
    return page;
  }

  /**
   * 把异常映射为人类可读文案。CfBlockedError 由调用方单独处理（弹切线路对话框）。
   * 区分 HTTP 状态码与网络错误，给用户具体可执行的提示。
   */
  static describeError(err: Object): string {
    // 搜索特殊化：HttpStatusError 400 在搜索语境下通常是关键词/筛选问题
    if (err instanceof HttpStatusError) {
      const httpErr: HttpStatusError = err as HttpStatusError;
      if (httpErr.statusCode === 400) {
        return '搜索参数无效，请尝试更换关键词或筛选条件';
      }
    }
    return ErrorHelper.describe(err, '搜索');
  }
}
