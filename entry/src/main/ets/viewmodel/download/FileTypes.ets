/*
 * FileTypes.ets — 扩展名 → MIME / UTD 映射（纯函数）
 *
 * 从 DownloadVM 抽出：openFile 用 MIME（ohos.want.action.viewData），
 * shareFile 用 UTD（ShareKit）。集中一处便于补充新格式。
 */

export class FileTypes {
  /** 扩展名 → MIME 类型（系统"打开方式"匹配用）。 */
  static mime(ext: string): string {
    const e: string = ext.toLowerCase();
    if (e === 'pdf') return 'application/pdf';
    if (e === 'epub') return 'application/epub+zip';
    if (e === 'mobi') return 'application/x-mobipocket-ebook';
    if (e === 'azw' || e === 'azw3') return 'application/vnd.amazon.ebook';
    if (e === 'djvu') return 'image/vnd.djvu';
    if (e === 'fb2') return 'application/x-fictionbook+xml';
    if (e === 'txt') return 'text/plain';
    return 'application/octet-stream';
  }

  /** 扩展名 → UTD 类型（ShareKit 用）。 */
  static utd(ext: string): string {
    const e: string = ext.toLowerCase();
    if (e === 'pdf') return 'general.pdf';
    if (e === 'epub') return 'general.epub';
    if (e === 'txt') return 'general.plain-text';
    return 'general.file';
  }
}
