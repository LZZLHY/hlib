/*
 * FileValidator.ets — 已下载文件的魔术字节校验（同步，纯本地 IO）
 *
 * 从 DownloadVM 抽出：在 requestInStream callback（2xx 后）调用，
 * 确保落盘的不是 HTML / JSON 错误页或空文件。
 */

import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../../utils/Logger';

const TAG: string = 'FileValidator';

export class FileValidator {
  /**
   * 校验文件首字节是否匹配预期格式。
   * 同步方法，便于在 requestInStream callback 中直接使用。
   */
  static validateSync(path: string, ext: string, bytesWritten: number): boolean {
    if (bytesWritten < 100) {
      return false; // 任何正常书文件不会小于 100 字节
    }
    try {
      const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const buf: ArrayBuffer = new ArrayBuffer(16);
        const read: number = fileIo.readSync(file.fd, buf);
        if (read < 4) {
          return false;
        }
        const bytes: Uint8Array = new Uint8Array(buf);
        const b0: number = bytes[0];
        const b1: number = bytes[1];
        const b2: number = bytes[2];
        const b3: number = bytes[3];

        const e: string = ext.toLowerCase();
        // PDF: %PDF (0x25504446)
        if (e === 'pdf') {
          return b0 === 0x25 && b1 === 0x50 && b2 === 0x44 && b3 === 0x46;
        }
        // EPUB / CBZ / DOCX 均为 ZIP 容器: PK\x03\x04
        if (e === 'epub' || e === 'cbz' || e === 'docx') {
          return b0 === 0x50 && b1 === 0x4B;
        }
        // DJVU: AT&T
        if (e === 'djvu') {
          return b0 === 0x41 && b1 === 0x54 && b2 === 0x26 && b3 === 0x54;
        }

        // 通用检查：首字节不应是 HTML(<) / JSON({[)
        if (b0 === 0x3C || b0 === 0x7B || b0 === 0x5B) {
          Logger.w(TAG, `file starts with '${String.fromCharCode(b0)}', likely non-binary`);
          return false;
        }
        return true;
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      Logger.w(TAG, `validateSync failed: ${(e as Error).message}`);
      return false;
    }
  }
}
