/*
 * ApiTypes.ets
 * 全局共享的 API 错误类型与响应壳。
 */

/** 通用响应壳：与 Z-Library 后端 `{success:1|true, ...}` 对齐。 */
export interface ApiResponse {
  success?: number | boolean;
  error?: string;
  message?: string;
}

/** 受控异常基类——便于上层 instanceof 判定。 */
export class ApiError extends Error {
  statusCode: number;

  constructor(message: string, statusCode: number = -1) {
    super(message);
    this.statusCode = statusCode;
    this.name = 'ApiError';
  }
}

/** 网络层错误（DNS / 连接 / 超时 / 中断）。 */
export class NetworkError extends ApiError {
  constructor(message: string) {
    super(message, -1);
    this.name = 'NetworkError';
  }
}

/** 命中 Cloudflare 5 秒盾或 403 cf-mitigated。 */
export class CfBlockedError extends ApiError {
  constructor() {
    super('cf_blocked', 403);
    this.name = 'CfBlockedError';
  }
}

/** 未授权（cookie 失效 / 登录失败）。 */
export class UnauthorizedError extends ApiError {
  constructor(message: string = 'unauthorized') {
    super(message, 401);
    this.name = 'UnauthorizedError';
  }
}

/** HTTP 4xx/5xx。 */
export class HttpStatusError extends ApiError {
  body: string;

  constructor(statusCode: number, body: string = '') {
    super(`http ${statusCode}`, statusCode);
    this.body = body;
    this.name = 'HttpStatusError';
  }
}
