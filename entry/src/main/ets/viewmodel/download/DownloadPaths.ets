/*
 * DownloadPaths.ets — 下载文件名与落盘路径计算（纯函数 + AppStorage 读取）
 *
 * 从 DownloadVM 抽出：根据 Book 生成安全文件名，根据 DOWNLOAD_PATH 偏好解析目标目录。
 */

import common from '@ohos.app.ability.common';
import { Book } from '../../model/Book';
import { AppStorageKeys } from '../../storage/AppStorageKeys';

export class DownloadPaths {
  /** title 清洗非法字符 + 截断 + 拼 id 与扩展名。 */
  static buildFilename(book: Book): string {
    const ext: string = book.extension !== undefined && book.extension.length > 0 ? book.extension : 'epub';
    const safeTitle: string = book.title.replace(/[\\\/:*?"<>|]/g, '_').slice(0, 80);
    return `${safeTitle}_${book.id}.${ext}`;
  }

  /**
   * 解析 AppStorage[DOWNLOAD_PATH]：
   *   '' / 'default' / undefined → ctx.filesDir/Downloads（沙箱内）
   *   'cache'                    → ctx.cacheDir/Downloads（缓存目录）
   *   其它非空                    → 当作绝对路径直接拼
   */
  static buildFilePath(ctx: common.UIAbilityContext, filename: string): string {
    const custom: string | undefined = AppStorage.get<string>(AppStorageKeys.DOWNLOAD_PATH);
    if (custom === 'cache') {
      return `${ctx.cacheDir}/Downloads/${filename}`;
    }
    if (custom !== undefined && custom.length > 0 && custom !== 'default') {
      return `${custom}/${filename}`;
    }
    return `${ctx.filesDir}/Downloads/${filename}`;
  }
}
