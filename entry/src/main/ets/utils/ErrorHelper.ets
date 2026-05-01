/*
 * ErrorHelper.ets
 *
 * 统一错误归一：把任意 throw 的对象映射为本地化的人类可读文案。
 *
 * 调用方传 i18n context key（如 'ctx_login' / 'ctx_load_detail' / 'ctx_download'），
 * 用于在通用文案前加语境化前缀，避免每个 page 重复实现 describeError。
 *
 * 所有文案走 string.json，由系统按 locale 自动选择中英；
 * 依赖 I18n.bindContext 已被 EntryAbility 在 onCreate 注入。
 */

import {
  ApiError,
  CfBlockedError,
  HttpStatusError,
  NetworkError,
  UnauthorizedError,
} from '../api/ApiTypes';
import { I18n } from './I18n';

export class ErrorHelper {
  /**
   * 把异常映射为本地化文案。
   * - CfBlockedError 由调用方单独处理（弹切线路对话框）；这里仍兜底返回文案。
   * - ctxKey 是 string.json 中的 i18n 键，例如 'ctx_login' / 'ctx_load_detail'。
   *   不传时默认 'ctx_op'（=「操作」/「Operation」）。
   */
  static describe(err: Object, ctxKey: string = 'ctx_op'): string {
    if (err instanceof CfBlockedError) {
      return I18n.ts('err_cf_blocked');
    }
    if (err instanceof UnauthorizedError) {
      return I18n.ts('err_unauthorized');
    }
    const ctx: string = I18n.ts(ctxKey);
    if (err instanceof HttpStatusError) {
      const httpErr: HttpStatusError = err as HttpStatusError;
      switch (httpErr.statusCode) {
        case 400:
          return I18n.format('err_op_failed_param_fmt', [ctx]);
        case 401:
          return I18n.ts('err_http_401');
        case 403:
          return I18n.ts('err_http_403');
        case 404:
          return I18n.ts('err_http_404');
        case 429:
          return I18n.ts('err_http_429');
        case 500:
        case 502:
        case 503:
        case 504:
          return I18n.ts('err_http_5xx');
        default:
          return I18n.format('err_op_failed_http_fmt', [ctx, httpErr.statusCode]);
      }
    }
    if (err instanceof NetworkError) {
      return I18n.ts('err_network');
    }
    if (err instanceof ApiError) {
      const apiErr: ApiError = err as ApiError;
      if (apiErr.message.length > 0) {
        return apiErr.message;
      }
      return I18n.format('err_op_failed_fmt', [ctx]);
    }
    const e: Error = err as Error;
    if (e.message.length > 0) {
      return e.message;
    }
    return I18n.format('err_op_failed_fmt', [ctx]);
  }
}
