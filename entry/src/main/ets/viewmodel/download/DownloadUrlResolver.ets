/*
 * DownloadUrlResolver.ets — 两步下载的第一步：解析真正的下载链接
 *
 * 从 DownloadVM 抽出。请求 /eapi/book/{id}/{hash}/file 取 JSON，
 * 从 dl / file.dlUrl / file.url 中提取真实下载 URL；失败回退到 /file 端点本身。
 * 日志统一经 Redact 脱敏，避免签名 token 进 hilog。
 */

import { http } from '@kit.NetworkKit';
import { HttpClient } from '../../api/HttpClient';
import { Logger } from '../../utils/Logger';
import { Redact } from '../../utils/Redact';

const TAG: string = 'DownloadUrlResolver';

/** /eapi/book/{id}/{hash}/file 可能返回的 JSON 结构。 */
interface FileApiResponse {
  success?: number | boolean;
  dl?: string;
  file?: FileApiFile;
  error?: string;
  message?: string;
}
interface FileApiFile {
  downloadLink?: string;
  dlUrl?: string;
  dl?: string;
  url?: string;
  description?: string;
  extension?: string;
  allowDownload?: boolean;
}

export class DownloadUrlResolver {
  /**
   * 请求 /file 端点取 JSON 下载信息并提取真实下载 URL。
   * 若端点直接返回二进制 / 非 JSON，回退到 /file 端点 URL（部分镜像会 302 到 CDN）。
   */
  static async resolve(
    bookId: string,
    hashId: string,
    domain: string,
    headers: Record<string, string>,
  ): Promise<string> {
    const fileApiUrl: string = `https://${domain}/eapi/book/${bookId}/${hashId}/file`;
    const req: http.HttpRequest = http.createHttp();
    try {
      const reqHeaders: Record<string, string> = {};
      const hKeys: string[] = Object.keys(headers);
      for (let i = 0; i < hKeys.length; i++) {
        reqHeaders[hKeys[i]] = headers[hKeys[i]];
      }
      reqHeaders['Accept'] = 'application/json, text/plain, */*';

      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: reqHeaders,
        connectTimeout: 15000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING,
      };
      if (HttpClient.instance.hasProxy()) {
        opts.usingProxy = {
          host: HttpClient.instance.getProxyHost(),
          port: HttpClient.instance.getProxyPort(),
          exclusionList: [],
        };
      }
      const resp: http.HttpResponse = await req.request(fileApiUrl, opts);
      const status: number = resp.responseCode;
      const body: string = typeof resp.result === 'string' ? resp.result : '';
      Logger.i(TAG, `resolve status=${status} bodyLen=${body.length}`);

      if (status >= 200 && status < 300 && body.length > 0 && body.length < 50000) {
        const trimmed: string = body.trim();
        if (trimmed.length > 0 && trimmed.charAt(0) === '{') {
          try {
            const json: FileApiResponse = JSON.parse(trimmed) as FileApiResponse;
            let dlPath: string = '';
            if (json.dl !== undefined && json.dl.length > 0) {
              dlPath = json.dl;
            }
            if (dlPath.length === 0 && json.file !== undefined) {
              const f: FileApiFile = json.file;
              if (f.downloadLink !== undefined && f.downloadLink.length > 0) {
                dlPath = f.downloadLink;
              } else if (f.dlUrl !== undefined && f.dlUrl.length > 0) {
                dlPath = f.dlUrl;
              } else if (f.dl !== undefined && f.dl.length > 0) {
                dlPath = f.dl;
              } else if (f.url !== undefined && f.url.length > 0) {
                dlPath = f.url;
              }
            }
            if (dlPath.length > 0) {
              const resolved: string = dlPath.startsWith('http')
                ? dlPath
                : `https://${domain}${dlPath.startsWith('/') ? '' : '/'}${dlPath}`;
              Logger.i(TAG, `resolved download url: ${Redact.url(resolved)}`);
              return resolved;
            }
            Logger.w(TAG, `file endpoint returned JSON but no dl path found`);
          } catch (_e) {
            Logger.d(TAG, `file endpoint body not JSON, using url as-is`);
          }
        }
      }
    } catch (e) {
      Logger.w(TAG, `resolve failed: ${(e as Error).message}`);
    } finally {
      try {
        req.destroy();
      } catch (_e) {
        // ignore
      }
    }
    // 回退：直接用 /file 端点 URL
    return fileApiUrl;
  }
}
