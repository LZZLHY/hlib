/*
 * ErrorHelper.ets
 *
 * 统一错误归一：把任意 throw 的对象映射为人类可读文案。
 *
 * 调用方传一个 `context` 字段（如 "登录"/"加载详情"/"下载"），
 * 用于在通用文案前加语境化前缀，避免每个 page 重复实现 describeError。
 *
 * 与 SearchVM 历史 describeError 兼容（保留中文搜索语境的特化文案，但抽到这里）。
 */

import {
  ApiError,
  CfBlockedError,
  HttpStatusError,
  NetworkError,
  UnauthorizedError,
} from '../api/ApiTypes';

export class ErrorHelper {
  /**
   * 把异常映射为人类可读文案。
   * - CfBlockedError 由调用方单独处理（弹切线路对话框）；这里仍兜底返回文案。
   * - context 用于错误抽象的领域词，例如 "登录" / "加载详情" / "收藏" / "下载"。
   *   不传时默认 "操作"。
   */
  static describe(err: Object, context: string = '操作'): string {
    if (err instanceof CfBlockedError) {
      return '当前线路被 Cloudflare 拦截，请切换线路';
    }
    if (err instanceof UnauthorizedError) {
      return '登录已过期，请重新登录';
    }
    if (err instanceof HttpStatusError) {
      const httpErr: HttpStatusError = err as HttpStatusError;
      switch (httpErr.statusCode) {
        case 400:
          return `${context}失败：请求参数无效`;
        case 401:
          return '账号或密码错误';
        case 403:
          return '当前线路拒绝访问，请切换线路';
        case 404:
          return '资源不存在或已下架';
        case 429:
          return '请求过于频繁，请稍候再试';
        case 500:
        case 502:
        case 503:
        case 504:
          return '服务器临时故障，请稍后重试';
        default:
          return `${context}失败（HTTP ${httpErr.statusCode}）`;
      }
    }
    if (err instanceof NetworkError) {
      return '网络连接失败，请检查网络或切换线路';
    }
    if (err instanceof ApiError) {
      const apiErr: ApiError = err as ApiError;
      return apiErr.message.length > 0 ? apiErr.message : `${context}失败`;
    }
    const e: Error = err as Error;
    return e.message.length > 0 ? e.message : `${context}失败`;
  }
}
