/*
 * DownloadPaths.ets — 下载文件名与落盘路径计算（纯函数 + AppStorage 读取）
 *
 * 从 DownloadVM 抽出：根据 Book 生成安全文件名，根据 DOWNLOAD_PATH 偏好解析目标目录。
 */

import common from '@ohos.app.ability.common';
import { Book } from '../../model/Book';
import { AppStorageKeys } from '../../storage/AppStorageKeys';
import { PublicDownloadDir } from '../../utils/PublicDownloadDir';

export class DownloadPaths {
  /** title 清洗非法字符 + 截断 + 拼 id 与扩展名。 */
  static buildFilename(book: Book): string {
    const ext: string = book.extension !== undefined && book.extension.length > 0 ? book.extension : 'epub';
    const safeTitle: string = book.title.replace(/[\\\/:*?"<>|]/g, '_').slice(0, 80);
    return `${safeTitle}_${book.id}.${ext}`;
  }

  /**
   * 解析 AppStorage[DOWNLOAD_PATH]：
   *   '' / 'default' / undefined → ctx.filesDir/Downloads（应用沙箱内）
   *   'public'                   → 公共「下载」目录下的应用专属目录（Environment.getUserDownloadDir）；
   *                                不支持 / 未授权时回退沙箱。
   */
  static buildFilePath(ctx: common.UIAbilityContext, filename: string): string {
    const custom: string | undefined = AppStorage.get<string>(AppStorageKeys.DOWNLOAD_PATH);
    if (custom === 'public') {
      const dir: string = PublicDownloadDir.resolveDir();
      if (dir.length > 0 && PublicDownloadDir.isWritable(dir)) {
        return `${dir}/${filename}`;
      }
      // 不支持 / 未授权 / 权限失效 → 回退沙箱
      return `${ctx.filesDir}/Downloads/${filename}`;
    }
    return `${ctx.filesDir}/Downloads/${filename}`;
  }
}
