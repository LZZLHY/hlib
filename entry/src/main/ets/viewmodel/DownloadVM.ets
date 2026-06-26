/*
 * DownloadVM.ets
 *
 * 下载编排门面。参照 olib `download_provider.dart` 的 dio.download 实现，
 * 使用 @ohos.net.http 的 requestInStream + fileIo 流式落盘。
 *
 * 弃用 @ohos.request.agent 的原因：
 *   1) cookie 在 request.agent.Config.headers 中部分 SDK 版本不生效（→ 503 PROTOCOL）；
 *   2) 任务调度有"等待"阶段，无法立即拉起，UI 上"一直等待中"；
 *   3) failure 只暴露 enum Faults，难以拿到服务端真实 reason。
 *
 * 职责拆分（重构后）：
 *   - 文件名/路径         → download/DownloadPaths
 *   - 真实下载链接解析    → download/DownloadUrlResolver
 *   - 魔术字节校验        → download/FileValidator
 *   - MIME / UTD 映射     → download/FileTypes
 *   - 任务列表 / 历史持久化 → download/DownloadRepository
 *   - 本文件只保留：流式下载引擎 + 自动镜像漂移重试 + 打开/分享
 *
 * 状态架构：
 *   - 进行中/失败：AppStorage[DOWNLOAD_TASKS]（经 DownloadRepository）
 *   - 已完成：DownloadHistoryStore + AppStorage[DOWNLOAD_HISTORY] 镜像
 *   - http.HttpRequest 实例仅活在内存（Map<bookId, HttpRequest>），重启丢失（MVP 接受）
 */

import { http } from '@kit.NetworkKit';
import common from '@ohos.app.ability.common';
import { Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { Book } from '../model/Book';
import { DownloadTask } from '../model/DownloadTask';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { DownloadHistoryItem } from '../storage/DownloadHistoryStore';
import { HttpClient } from '../api/HttpClient';
import { DOMAINS } from '../api/Domains';
import { DomainTestResult } from '../model/DomainTestResult';
import { UrlUtils } from '../utils/UrlUtils';
import { I18n } from '../utils/I18n';
import { Logger } from '../utils/Logger';
import { Redact } from '../utils/Redact';
import { PublicDirAccess } from '../utils/PublicDirAccess';
import { FileTypes } from './download/FileTypes';
import { FileValidator } from './download/FileValidator';
import { DownloadPaths } from './download/DownloadPaths';
import { DownloadUrlResolver } from './download/DownloadUrlResolver';
import { DownloadRepository } from './download/DownloadRepository';

const TAG: string = 'DownloadVM';

/** 单个下载任务用于自动镜像漂移的上下文（仅内存）。 */
interface DownloadRetryCtx {
  book: Book;
  ctx: common.UIAbilityContext;
  /** 已尝试过的域名，避免来回切。 */
  attemptedDomains: Set<string>;
  /** 已重试次数（不含首次），上限 MAX_DOMAIN_RETRIES。 */
  retried: number;
}

/** 一个 download task 失败后最多自动换域重试的次数。 */
const MAX_DOMAIN_RETRIES: number = 2;

/** http.dataReceiveProgress 回调参数（不同 SDK 版本字段微差，自定义结构以兼容）。 */
interface DataReceiveProgressLike {
  receiveSize: number;
  totalSize: number;
}

export class DownloadVM {
  /** 内存中的 http stream 句柄；重启会丢，但任务记录还在。 */
  private static handles: Map<string, http.HttpRequest> = new Map<string, http.HttpRequest>();

  /** bookId → 重试上下文。仅当前进程内有效，重启丢失（用户重启后手动重试即可）。 */
  private static retryCtxs: Map<string, DownloadRetryCtx> = new Map<string, DownloadRetryCtx>();

  /** bookId → 用户主动取消标记。downloadStream 中检测到则不触发 mirror retry。 */
  private static cancelled: Set<string> = new Set<string>();

  // ─── 启动时把持久化的历史回灌 AppStorage ───

  static async init(ctx?: common.UIAbilityContext): Promise<void> {
    try {
      await DownloadRepository.loadHistoryToStorage();
      // 重接未完成任务
      await DownloadVM.restoreTasks(ctx);
    } catch (e) {
      Logger.w(TAG, `init failed: ${(e as Error).message}`);
    }
  }

  /**
   * 应用启动时清理残留：之前进程跑到一半的下载任务无法跨进程恢复（http stream 是进程内对象），
   * 把任务列表清空，让用户重新触发。
   */
  static async restoreTasks(_ctx?: common.UIAbilityContext): Promise<void> {
    AppStorage.setOrCreate<DownloadTask[]>(AppStorageKeys.DOWNLOAD_TASKS, []);
  }

  // ─── 进行中任务 ────────────────────────────────────

  /**
   * 判断一本书是否可下载：有 hash（eAPI file 端点）或 dl（旧路径兜底）。
   */
  static canDownload(book: Book): boolean {
    const hasHash: boolean = book.hash !== undefined && book.hash.length > 0;
    const hasDl: boolean = book.dl !== undefined && book.dl.length > 0;
    return hasHash || hasDl;
  }

  /** 启动下载。返回 task。失败抛错。 */
  static async start(book: Book, ctx: common.UIAbilityContext): Promise<DownloadTask> {
    if (!DownloadVM.canDownload(book)) {
      throw new Error('no_download_link');
    }
    // 注册重试上下文：首次入口标记当前域为 attempted。
    const bookId: string = String(book.id);
    const initial: Set<string> = new Set<string>();
    initial.add(HttpClient.instance.getDomain());
    DownloadVM.retryCtxs.set(bookId, {
      book: book,
      ctx: ctx,
      attemptedDomains: initial,
      retried: 0,
    });
    return await DownloadVM.startInternal(book, ctx, undefined);
  }

  /**
   * 实际启动逻辑。`overrideDomain` 非空时用它拼下载 URL（自动镜像漂移路径用），
   * 否则用 HttpClient 当前 domain。
   */
  private static async startInternal(
    book: Book,
    ctx: common.UIAbilityContext,
    overrideDomain: string | undefined,
  ): Promise<DownloadTask> {
    if (!DownloadVM.canDownload(book)) {
      throw new Error('no_download_link');
    }
    const bookId: string = String(book.id);
    const hashId: string = book.hash !== undefined && book.hash.length > 0 ? book.hash : '';

    // 已有同 bookId 任务
    const existing: DownloadTask | undefined = DownloadRepository.findActive(bookId);
    if (existing !== undefined && (existing.status === 'downloading' || existing.status === 'pending')) {
      Logger.i(TAG, `download(${book.id}) already in progress`);
      return existing;
    }

    const filename: string = DownloadPaths.buildFilename(book);
    const filePath: string = DownloadPaths.buildFilePath(ctx, filename);

    // 父目录必须存在
    const lastSlash: number = filePath.lastIndexOf('/');
    if (lastSlash > 0) {
      await DownloadVM.ensureDirExists(filePath.substring(0, lastSlash));
    }
    // 同名残留先删
    await DownloadVM.removeIfExists(filePath);

    // 选择域名：自动镜像漂移时 overrideDomain 非空
    const useDomain: string = overrideDomain !== undefined && overrideDomain.length > 0
      ? overrideDomain
      : HttpClient.instance.getDomain();

    // headers：与 HttpClient.attemptOnce 对齐，确保服务端视为浏览器请求
    const headers: Record<string, string> = {};
    headers['User-Agent'] = HttpClient.instance.defaultUserAgent();
    headers['Accept'] = '*/*';
    headers['Accept-Encoding'] = 'identity'; // 禁止 gzip，防止二进制文件被压缩存储导致"损坏"
    headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    const cookie: string = HttpClient.instance.exportCookieHeader();
    if (cookie.length > 0) {
      headers['Cookie'] = cookie;
    }

    /*
     * 两步下载：
     *   Step 1 — 先请求 /file 端点解析真正的下载链接（DownloadUrlResolver）。
     *   Step 2 — 用 requestInStream 从链接流式落盘。
     */
    let absoluteUrl: string;
    if (hashId.length > 0) {
      absoluteUrl = await DownloadUrlResolver.resolve(bookId, hashId, useDomain, headers);
    } else if (book.dl !== undefined && book.dl.length > 0) {
      absoluteUrl = UrlUtils.joinUrl(useDomain, book.dl);
    } else {
      throw new Error('no_download_link');
    }
    Logger.i(TAG, `start download(${book.id}) url=${Redact.url(absoluteUrl)}`);

    // 若下载到用户选择的公共目录（file:// URI），写入前唤醒其持久化写授权（FILE_ACCESS_PERSIST）。
    const dlDir: string | undefined = AppStorage.get<string>(AppStorageKeys.DOWNLOAD_PATH);
    if (dlDir !== undefined && PublicDirAccess.isManagedUri(dlDir)) {
      await PublicDirAccess.activateWrite(dlDir);
    }

    // 打开目标文件（READ_WRITE | CREATE | TRUNC）
    let file: fileIo.File;
    try {
      file = fileIo.openSync(
        filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      );
    } catch (e) {
      Logger.e(TAG, `openFile failed: ${filePath}`, e as Error);
      throw new Error(`open_file_failed: ${(e as Error).message}`);
    }

    // 创建 dt 记录并入队
    const dt: DownloadTask = {
      bookId: bookId,
      hashId: book.hash !== undefined ? book.hash : '',
      title: book.title,
      author: book.author,
      cover: book.cover,
      extension: book.extension,
      url: absoluteUrl,
      filePath: filePath,
      status: 'downloading',
      progress: 0,
      receivedBytes: 0,
      totalBytes: book.filesize !== undefined ? book.filesize : 0,
      createdAt: Date.now(),
    };
    DownloadRepository.addToList(dt);

    // 创建 http 流式请求
    const req: http.HttpRequest = http.createHttp();
    DownloadVM.handles.set(bookId, req);

    let bytesWritten: number = 0;
    let totalSize: number = dt.totalBytes;
    let statusCode: number = 0;
    let finished: boolean = false;
    let badContentType: boolean = false;
    /** 关闭文件 + 销毁请求；幂等。 */
    const teardown = (): void => {
      if (finished) return;
      finished = true;
      try { fileIo.closeSync(file); } catch (e) { Logger.w(TAG, `closeFile: ${(e as Error).message}`); }
      try { req.destroy(); } catch (e) { Logger.w(TAG, `req.destroy: ${(e as Error).message}`); }
      DownloadVM.handles.delete(bookId);
    };

    // 收到响应头：检查 Content-Type，如果是 HTML/JSON 而非文件流，标记为非文件响应
    req.on('headersReceive', (h: Object): void => {
      Logger.i(TAG, `headers(${bookId}): ${JSON.stringify(Redact.headers(h))}`);
      try {
        const hStr: string = JSON.stringify(h).toLowerCase();
        if (hStr.indexOf('text/html') >= 0 || hStr.indexOf('application/json') >= 0) {
          badContentType = true;
          Logger.w(TAG, `download(${bookId}) got non-file content-type, will abort`);
          teardown();
          DownloadVM.removeIfExists(dt.filePath).catch((): void => {});
          DownloadVM.handleStreamFailure(dt, 'non_file_response', true);
        }
      } catch (_e) {
        // 解析 header 失败不影响主流程
      }
    });

    // 进度
    req.on('dataReceiveProgress', (info: DataReceiveProgressLike): void => {
      if (info.totalSize > 0) {
        totalSize = info.totalSize;
      }
      const next: DownloadTask = DownloadRepository.cloneTask(dt);
      next.totalBytes = totalSize;
      next.receivedBytes = info.receiveSize;
      next.progress = totalSize > 0 ? Math.floor((info.receiveSize / totalSize) * 100) : 0;
      next.status = 'downloading';
      DownloadRepository.updateInList(next);
    });

    // 数据块写入文件
    req.on('dataReceive', (data: ArrayBuffer): void => {
      if (badContentType || finished) {
        return;
      }
      try {
        fileIo.writeSync(file.fd, data);
        bytesWritten = bytesWritten + data.byteLength;
      } catch (e) {
        Logger.e(TAG, `writeSync failed`, e as Error);
        teardown();
        DownloadVM.handleStreamFailure(dt, `write_failed: ${(e as Error).message}`, false);
      }
    });

    // 数据接收完成
    req.on('dataEnd', (): void => {
      Logger.i(TAG, `dataEnd(${bookId}): bytes=${bytesWritten} total=${totalSize}`);
    });

    // 启动流式请求
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      readTimeout: 0,        // 不限制单次读超时（大文件）
      connectTimeout: 30000, // 30s 连接超时
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
    };
    // 代理：与 HttpClient.attemptOnce 保持一致
    if (HttpClient.instance.hasProxy()) {
      opts.usingProxy = {
        host: HttpClient.instance.getProxyHost(),
        port: HttpClient.instance.getProxyPort(),
        exclusionList: [],
      };
    }

    req.requestInStream(absoluteUrl, opts, (err: Error | null | undefined, code: number): void => {
      // 此回调在 dataEnd 之后（成功路径）或异常时触发
      if (badContentType) {
        return; // 已在 headersReceive 中处理
      }
      statusCode = code;
      if (err !== null && err !== undefined) {
        Logger.w(TAG, `requestInStream(${bookId}) network err: ${err.message}`);
        teardown();
        DownloadVM.handleStreamFailure(dt, `network_error: ${err.message}`, true);
        return;
      }
      if (statusCode < 200 || statusCode >= 300) {
        Logger.w(TAG, `requestInStream(${bookId}) http ${statusCode} bytes=${bytesWritten}`);
        teardown();
        // 清理写了 HTML / 错误体的残留文件
        DownloadVM.removeIfExists(dt.filePath).catch((): void => {});
        DownloadVM.handleStreamFailure(dt, `http_${statusCode}`, statusCode >= 500 || statusCode === 0);
        return;
      }
      // 2xx：关闭文件后校验内容
      teardown();
      const ext: string = dt.extension !== undefined ? dt.extension : '';
      const valid: boolean = FileValidator.validateSync(dt.filePath, ext, bytesWritten);
      if (!valid) {
        Logger.w(TAG, `download(${bookId}) file invalid (likely HTML/JSON/empty), bytes=${bytesWritten}`);
        DownloadVM.removeIfExists(dt.filePath).catch((): void => {});
        DownloadVM.handleStreamFailure(dt, 'file_invalid', true);
        return;
      }
      DownloadVM.markCompleted(dt, bytesWritten, totalSize);
    });

    return dt;
  }

  /**
   * 流式下载失败处理：
   *   - `retryable=true` 时（5xx / 网络错误）触发自动镜像漂移；
   *   - 否则直接 markFailed。
   *   - 用户主动 cancel 不触发重试。
   */
  private static handleStreamFailure(dt: DownloadTask, detail: string, retryable: boolean): void {
    if (DownloadVM.cancelled.has(dt.bookId)) {
      DownloadVM.cancelled.delete(dt.bookId);
      DownloadVM.retryCtxs.delete(dt.bookId);
      // cancel 已经从列表移除，无需 markFailed
      return;
    }
    if (retryable) {
      const retryCtx: DownloadRetryCtx | undefined = DownloadVM.retryCtxs.get(dt.bookId);
      if (retryCtx !== undefined && retryCtx.retried < MAX_DOMAIN_RETRIES) {
        const next: string | undefined = DownloadVM.pickNextDomain(retryCtx.attemptedDomains);
        if (next !== undefined) {
          retryCtx.attemptedDomains.add(next);
          retryCtx.retried = retryCtx.retried + 1;
          Logger.i(TAG, `mirror retry ${dt.bookId} on ${next} (#${retryCtx.retried}) reason=${detail}`);
          DownloadRepository.removeFromList(dt.bookId);
          DownloadVM.startInternal(retryCtx.book, retryCtx.ctx, next).catch((e: Error): void => {
            Logger.w(TAG, `retry start failed: ${e.message}`);
            DownloadRepository.markFailed(dt, `${detail} retry_failed=${e.message}`);
            DownloadVM.retryCtxs.delete(dt.bookId);
          });
          return;
        }
        Logger.w(TAG, `no alternate domain available for ${dt.bookId}`);
      }
    }
    DownloadRepository.markFailed(dt, detail);
    DownloadVM.retryCtxs.delete(dt.bookId);
  }

  /** 流式下载完成：搬入历史 + 清状态。 */
  private static markCompleted(dt: DownloadTask, written: number, total: number): void {
    const next: DownloadTask = DownloadRepository.cloneTask(dt);
    next.status = 'completed';
    next.progress = 100;
    next.receivedBytes = written;
    next.totalBytes = total > 0 ? total : written;
    DownloadRepository.updateInList(next);
    DownloadRepository.persistCompleted(next);
    DownloadVM.retryCtxs.delete(dt.bookId);
    DownloadRepository.removeFromList(dt.bookId);
  }

  /** 取消下载 + 从列表移除。 */
  static async cancel(bookId: string): Promise<void> {
    DownloadVM.cancelled.add(bookId);
    const req: http.HttpRequest | undefined = DownloadVM.handles.get(bookId);
    if (req !== undefined) {
      try {
        req.destroy();
      } catch (e) {
        Logger.w(TAG, `req.destroy(${bookId}) failed: ${(e as Error).message}`);
      }
      DownloadVM.handles.delete(bookId);
    }
    DownloadVM.retryCtxs.delete(bookId);
    DownloadRepository.removeFromList(bookId);
  }

  // ─── 已完成历史（委托 DownloadRepository） ────────────

  static async refreshHistory(): Promise<DownloadHistoryItem[]> {
    return await DownloadRepository.refreshHistory();
  }

  static async removeHistory(bookId: string): Promise<void> {
    await DownloadRepository.removeHistory(bookId);
  }

  static async clearHistory(): Promise<void> {
    await DownloadRepository.clearHistory();
  }

  // ─── 文件打开 / 分享 ───────────────────────────────

  /**
   * 用能处理该文件类型的应用打开（阅读器 / 编辑器）。
   * 使用 ohos.want.action.viewData，系统仅展示注册了对应 MIME 类型的应用。
   */
  static async openFile(item: DownloadHistoryItem, ctx: common.UIAbilityContext): Promise<void> {
    const exists: boolean = await DownloadVM.fileExists(item.filePath);
    if (!exists) {
      throw new Error(I18n.ts('downloads_file_missing'));
    }
    const uri: string = fileUri.getUriFromPath(item.filePath);
    const mime: string = FileTypes.mime(item.extension !== undefined ? item.extension : '');
    Logger.i(TAG, `openFile uri=${uri}, mime=${mime}`);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: uri,
      type: mime,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
    };
    try {
      await ctx.startAbility(want);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      Logger.w(TAG, `openFile startAbility failed: code=${be.code}, msg=${be.message}`);
      // 16000001 = 无匹配 Ability；16000002 = 内部错误
      if (be.code === 16000001) {
        throw new Error(I18n.ts('downloads_open_no_app'));
      }
      throw new Error(I18n.format('downloads_open_failed_fmt', [be.message]));
    }
  }

  /**
   * 调起系统分享面板（ShareKit）。
   */
  static async shareFile(item: DownloadHistoryItem, ctx: common.UIAbilityContext): Promise<void> {
    const exists: boolean = await DownloadVM.fileExists(item.filePath);
    if (!exists) {
      throw new Error(I18n.ts('downloads_file_missing'));
    }
    const uri: string = fileUri.getUriFromPath(item.filePath);
    const utdType: string = FileTypes.utd(item.extension !== undefined ? item.extension : '');
    Logger.i(TAG, `shareFile uri=${uri}, utd=${utdType}`);
    try {
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utdType,
        uri: uri,
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE,
      });
    } catch (e) {
      Logger.w(TAG, `shareFile show panel failed: ${(e as Error).message}`);
      throw new Error(I18n.format('downloads_share_failed_fmt', [(e as Error).message]));
    }
  }

  private static async fileExists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_e) {
      return false;
    }
  }

  // ─── 私有：目录 / 镜像选择 ───────────────────────────

  /** 确保目录存在；不存在则递归创建。 */
  private static async ensureDirExists(dir: string): Promise<void> {
    try {
      const exists: boolean = await fileIo.access(dir);
      if (!exists) {
        await fileIo.mkdir(dir, true);
        Logger.i(TAG, `mkdir ${dir}`);
      }
    } catch (e) {
      Logger.w(TAG, `ensureDir(${dir}) failed: ${(e as Error).message}`);
    }
  }

  /** 删旧文件（如存在）。 */
  private static async removeIfExists(filePath: string): Promise<void> {
    try {
      const exists: boolean = await fileIo.access(filePath);
      if (exists) {
        await fileIo.unlink(filePath);
      }
    } catch (e) {
      Logger.w(TAG, `removeIfExists(${filePath}) failed: ${(e as Error).message}`);
    }
  }

  /**
   * 从 SPEED_RESULTS / 内置 DOMAINS 中选一个 alive 且未尝试过的域名。
   * 优先用测速结果（latencyMs 小的在前），其次按内置顺序回退。
   */
  private static pickNextDomain(attempted: Set<string>): string | undefined {
    const speeds: DomainTestResult[] | undefined =
      AppStorage.get<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS);
    if (speeds !== undefined && speeds.length > 0) {
      const aliveSorted: DomainTestResult[] = speeds
        .filter((r: DomainTestResult): boolean => {
          return r.latencyMs !== null && r.latencyMs > 0 && !attempted.has(r.domain);
        })
        .sort((a: DomainTestResult, b: DomainTestResult): number => {
          const la: number = a.latencyMs !== null ? a.latencyMs : 999999;
          const lb: number = b.latencyMs !== null ? b.latencyMs : 999999;
          return la - lb;
        });
      if (aliveSorted.length > 0) {
        return aliveSorted[0].domain;
      }
    }
    // 回退：按内置顺序找第一个未尝试的
    for (let i = 0; i < DOMAINS.length; i++) {
      const d: string = DOMAINS[i];
      if (!attempted.has(d)) {
        return d;
      }
    }
    return undefined;
  }
}
