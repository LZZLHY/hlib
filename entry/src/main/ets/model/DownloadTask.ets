/*
 * DownloadTask.ets
 *
 * 下载任务模型。
 *   - 进行中 / 暂停 / 失败 三态保存在 AppStorage[state_downloadTasks]（DownloadTask[]）；
 *   - 完成态搬运到 DownloadHistoryStore（preferences 持久化）。
 */

export type DownloadStatus = 'pending' | 'downloading' | 'paused' | 'completed' | 'failed' | 'canceled';

export interface DownloadTask {
  /** Z-Library 书籍 ID（字符串形式以兼容 history store）。 */
  bookId: string;
  hashId: string;
  title: string;
  author?: string;
  cover?: string;
  extension?: string;
  /** 下载源 URL（来自 Book.dl）。 */
  url: string;
  /** 落盘路径（沙箱内）。 */
  filePath: string;
  status: DownloadStatus;
  /** 0..100 */
  progress: number;
  receivedBytes: number;
  totalBytes: number;
  errorMessage?: string;
  /** 创建时刻 ms */
  createdAt: number;
  /** request.agent task id；用于 stop/pause/resume。 */
  taskId?: string;
}
