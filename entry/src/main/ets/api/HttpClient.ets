/*
 * HttpClient.ets
 *
 * 基于 @kit.NetworkKit 的轻量 HTTP 客户端。
 *
 * 特性：
 *   - 单实例 + setDomain / setAuth：所有业务 API 共享同一个底座。
 *   - Cookie 自管：解析响应 set-cookie，与登录后的 remix_* 一并注入下次请求。
 *   - 超时：连接 10s / 读取 30s（可配置）。
 *   - Cloudflare 检测：抛 CfBlockedError，UI 决定是否提示换线。
 *   - JSON 自动解析：传 expectDataType=STRING，根据响应头 content-type 解析。
 *   - 网络错误归一为 NetworkError；4xx/5xx 抛 HttpStatusError。
 *
 * 不在本类内做：下载（统一走 P3 的 DownloadVM + request.agent）；
 * 复杂 multipart 上传（暂不需要）。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../utils/Logger';
import { UrlUtils } from '../utils/UrlUtils';
import { DohResolver } from '../utils/DohResolver';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { DomainTestResult } from '../model/DomainTestResult';
import {
  ApiError,
  CfBlockedError,
  HttpStatusError,
  NetworkError,
  UnauthorizedError,
} from './ApiTypes';

const TAG: string = 'HttpClient';

/**
 * UA 候选池（与 olib release 包逆向所得一致：浏览器伪装）。
 * 每次请求随机选一条，避免被针对单一 UA 限流。
 */
const UA_POOL: string[] = [
  'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 11; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 14; SM-A536U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36',
];

/** 首选 UA（用于 ping 等纯探针场景，不轮换以保持探测一致性）。 */
const UA: string = UA_POOL[0];

function pickUA(): string {
  return UA_POOL[Math.floor(Math.random() * UA_POOL.length)];
}

/** 退避重试上限（含首请求，总共 RETRY_LIMIT+1 次尝试）。 */
const RETRY_LIMIT: number = 3;
/** 重试基准延迟（ms），实际延迟 = BASE * 2^(attempt-1)。 */
const RETRY_BASE_DELAY_MS: number = 800;
/** 触发自动切换备用域名的连续失败阈值。 */
const FALLBACK_FAIL_THRESHOLD: number = 3;

/**
 * 请求频率随机拖延（jitter）范围：每个请求入口点随机 sleep [JITTER_MIN, JITTER_MAX] ms。
 * 目的是打乱连续并发请求的整齐节奏，模拟人类访问节奏，避免被服务端 batch 识别。
 * 仅加在业务请求入口（request<T>最外层），重试路径不叠加（重试自带 backoff），ping 探针不加（保持测速准确）。
 */
const JITTER_MIN_MS: number = 25;
const JITTER_MAX_MS: number = 150;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => resolve(), ms);
  });
}

function jitterMs(): number {
  return JITTER_MIN_MS + Math.floor(Math.random() * (JITTER_MAX_MS - JITTER_MIN_MS + 1));
}

const CF_MARKERS: string[] = [
  'Just a moment...',
  'cf-mitigated',
  'Attention Required! | Cloudflare',
  '__cf_chl_',
  'cdn-cgi/challenge-platform',
];

/**
 * Z-Library 首页内容语言偏好。
 * 服务端主要看 `siteLanguageV2` cookie（来自 olib release 包字符串逆向），
 * 同时 Accept-Language header 作为兜底。
 *
 * key 用 LANGUAGE_FILTERS 的 key（如 'chinese'/'english'）；'all' 表示不主动声明（用浏览器默认）。
 */
interface LangProfile {
  /** siteLanguageV2 cookie 值。 */
  cookieValue: string;
  /** Accept-Language header 值。 */
  acceptLanguage: string;
}

const LANG_PROFILES: Record<string, LangProfile> = {
  'chinese':             { cookieValue: 'chinese',             acceptLanguage: 'zh-CN,zh;q=0.9,en;q=0.8' },
  'traditional_chinese': { cookieValue: 'traditional chinese', acceptLanguage: 'zh-TW,zh;q=0.9,en;q=0.8' },
  'english':             { cookieValue: 'english',             acceptLanguage: 'en-US,en;q=0.9' },
  'japanese':            { cookieValue: 'japanese',            acceptLanguage: 'ja-JP,ja;q=0.9,en;q=0.8' },
  'korean':              { cookieValue: 'korean',              acceptLanguage: 'ko-KR,ko;q=0.9,en;q=0.8' },
  'french':              { cookieValue: 'french',              acceptLanguage: 'fr-FR,fr;q=0.9,en;q=0.8' },
  'german':              { cookieValue: 'german',              acceptLanguage: 'de-DE,de;q=0.9,en;q=0.8' },
  'russian':             { cookieValue: 'russian',             acceptLanguage: 'ru-RU,ru;q=0.9,en;q=0.8' },
  'spanish':             { cookieValue: 'spanish',             acceptLanguage: 'es-ES,es;q=0.9,en;q=0.8' },
};

/** Accept-Language 默认值（'all' 或未识别 key 时使用）。 */
const DEFAULT_ACCEPT_LANGUAGE: string = 'zh-CN,zh;q=0.9,en;q=0.8';

/** GET / POST 通用查询参数值类型。 */
export type QueryValue = string | number | boolean | string[] | number[] | undefined | null;
export type QueryParams = Record<string, QueryValue>;

/** POST 表单字段类型。支持数组（序列化为 key[]=v1&key[]=v2）。 */
export type FormValue = string | number | boolean | undefined | null | string[] | number[];
export type FormParams = Record<string, FormValue>;

export interface HttpRequestOptions {
  /** 是否显式跳过登录 cookie（如登录请求自身）。默认 false。 */
  skipAuthCookie?: boolean;
  /** 自定义 header（会覆盖默认 UA / Cookie 之外的项）。 */
  headers?: Record<string, string>;
  /** 连接超时（ms） */
  connectTimeoutMs?: number;
  /** 读取超时（ms） */
  readTimeoutMs?: number;
}

export class HttpClient {
  private static _instance: HttpClient | null = null;

  private domain: string = 'pkuedu.online';
  /** 登录态（注入为 remix_userid/remix_userkey cookie） */
  private remixUserId: string = '';
  private remixUserKey: string = '';
  /** 服务端 set-cookie 解析后的 cookie jar：name -> value */
  private cookieJar: Map<string, string> = new Map<string, string>();

  /** 当前域名连续失败计数（仅 NetworkError / HttpStatusError 5xx 计入；4xx 业务错不计）。 */
  private consecutiveFails: number = 0;
  /** 自动漂移使用的 "已尝试过" 域名集合，避免短时间内来回切换。 */
  private triedDomains: Set<string> = new Set<string>();

  /** HTTP 代理（可选）。设置后所有 request / ping 均走代理。 */
  private proxyHost: string = '';
  private proxyPort: number = 0;

  /**
   * 站点语言偏好（LANGUAGE_FILTERS key，如 'chinese'/'english'/'all'）。
   * 影响每次请求的 `siteLanguageV2` cookie 与 Accept-Language header。
   * 'all' 或空串表示不主动声明（服务端用账号默认 / 浏览器默认）。
   */
  private siteLanguage: string = '';

  private constructor() {}

  static get instance(): HttpClient {
    if (HttpClient._instance === null) {
      HttpClient._instance = new HttpClient();
    }
    return HttpClient._instance;
  }

  // ─── 配置 ───────────────────────────────────────────

  setDomain(domain: string): void {
    const cleaned: string = domain.replace(/^https?:\/\//, '').replace(/\/$/, '');
    if (cleaned !== this.domain) {
      Logger.i(TAG, `domain switched: ${this.domain} -> ${cleaned}`);
      this.domain = cleaned;
      // 切换域名后清空 cookie，避免跨域携带
      this.cookieJar.clear();
      this.consecutiveFails = 0;
      this.triedDomains.clear();
    }
  }

  getDomain(): string {
    return this.domain;
  }

  /**
   * 设置 HTTP 代理。host 为空串或 port<=0 表示不使用代理。
   * 代理 URL 示例：127.0.0.1:7890 （Clash 本地端口）、vps.example.com:8080。
   */
  setProxy(host: string, port: number): void {
    const cleanedHost: string = host.trim().replace(/^https?:\/\//, '').replace(/\/+$/, '');
    if (cleanedHost.length === 0 || port <= 0 || port > 65535) {
      this.clearProxy();
      return;
    }
    if (cleanedHost !== this.proxyHost || port !== this.proxyPort) {
      Logger.i(TAG, `proxy set: ${cleanedHost}:${port}`);
      this.proxyHost = cleanedHost;
      this.proxyPort = port;
    }
  }

  clearProxy(): void {
    if (this.proxyHost.length > 0) {
      Logger.i(TAG, 'proxy cleared');
    }
    this.proxyHost = '';
    this.proxyPort = 0;
  }

  hasProxy(): boolean {
    return this.proxyHost.length > 0 && this.proxyPort > 0;
  }

  getProxyHost(): string {
    return this.proxyHost;
  }

  getProxyPort(): number {
    return this.proxyPort;
  }

  /**
   * 设置站点内容语言偏好。
   * 影响 `siteLanguageV2` cookie 和 Accept-Language header，从而决定首页热门 / 近期上传等推荐内容的语言。
   * 接受 LANGUAGE_FILTERS 的 key，如 'chinese'/'english'；'all' 或空串表示不主动声明。
   */
  setSiteLanguage(langKey: string): void {
    const cleaned: string = langKey.trim();
    if (cleaned !== this.siteLanguage) {
      Logger.i(TAG, `siteLanguage: ${this.siteLanguage} -> ${cleaned}`);
      this.siteLanguage = cleaned;
      // 清除 cookieJar 里被服务端写过的旧 siteLanguageV2，避免锁死老偏好。
      // 下次请求 buildCookieHeader 会按新 siteLanguage 重新注入。
      if (this.cookieJar.has('siteLanguageV2')) {
        this.cookieJar.delete('siteLanguageV2');
      }
    }
  }

  getSiteLanguage(): string {
    return this.siteLanguage;
  }

  setAuth(userId: string, userKey: string): void {
    this.remixUserId = userId;
    this.remixUserKey = userKey;
  }

  clearAuth(): void {
    this.remixUserId = '';
    this.remixUserKey = '';
    this.cookieJar.clear();
  }

  hasAuth(): boolean {
    return this.remixUserId.length > 0 && this.remixUserKey.length > 0;
  }

  getRemixUserId(): string {
    return this.remixUserId;
  }

  getRemixUserKey(): string {
    return this.remixUserKey;
  }

  /** 给 WebView/阅读器复用的整段 cookie 字符串。 */
  exportCookieHeader(): string {
    return this.buildCookieHeader(false);
  }

  /**
   * 默认 User-Agent（与 olib release 包逆向得到的 Android Chrome UA 一致）。
   * 给下载（request.agent）/ 阅读器（ArkWeb）等不走 attemptOnce 的场景复用，
   * 避免使用 HarmonyOS 默认 UA 暴露客户端身份导致被服务端 403 / 429。
   */
  defaultUserAgent(): string {
    return UA;
  }

  // ─── 请求 ───────────────────────────────────────────

  async get<T>(path: string, query?: QueryParams, options?: HttpRequestOptions): Promise<T> {
    const url: string = UrlUtils.joinUrl(this.domain, path) + UrlUtils.buildQuery(query);
    return await this.request<T>(url, http.RequestMethod.GET, undefined, options);
  }

  async postForm<T>(path: string, form: FormParams, options?: HttpRequestOptions): Promise<T> {
    const url: string = UrlUtils.joinUrl(this.domain, path);
    const body: string = UrlUtils.encodeForm(form);

    // 显式合并 headers（避免 Object.assign 触发 arkts-limited-stdlib）
    const merged: Record<string, string> = {};
    if (options !== undefined && options.headers !== undefined) {
      const baseKeys: string[] = Object.keys(options.headers);
      for (let i = 0; i < baseKeys.length; i++) {
        merged[baseKeys[i]] = options.headers[baseKeys[i]];
      }
    }
    merged['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';

    const opts: HttpRequestOptions = {
      skipAuthCookie: options?.skipAuthCookie,
      connectTimeoutMs: options?.connectTimeoutMs,
      readTimeoutMs: options?.readTimeoutMs,
      headers: merged,
    };
    return await this.request<T>(url, http.RequestMethod.POST, body, opts);
  }

  /**
   * 简单可达性探测。返回延迟（ms）；失败返回 -1。
   * 不会污染 cookie jar，不抛异常。
   */
  async ping(domain: string, timeoutMs: number = 8000): Promise<number> {
    const cleanedDomain: string = domain.replace(/^https?:\/\//, '').replace(/\/$/, '');
    const url: string = `https://${cleanedDomain}/eapi/info/languages`;
    const req: http.HttpRequest = http.createHttp();
    const start: number = Date.now();
    try {
      const pingHeaders: Record<string, string> = { 'User-Agent': UA };
      const reqOpts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: pingHeaders,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
      };
      if (this.proxyHost.length > 0 && this.proxyPort > 0) {
        reqOpts.usingProxy = {
          host: this.proxyHost,
          port: this.proxyPort,
          exclusionList: [],
        };
      }
      const resp: http.HttpResponse = await req.request(url, reqOpts);
      const elapsed: number = Date.now() - start;
      const body: string = typeof resp.result === 'string' ? resp.result : '';
      const ok: boolean = resp.responseCode >= 200 && resp.responseCode < 300
        && (body.indexOf('"success":1') >= 0
          || body.indexOf('"success": 1') >= 0
          || body.indexOf('"success":true') >= 0);
      return ok ? elapsed : -1;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.d(TAG, `ping ${domain} failed: ${e.message}`);
      return -1;
    } finally {
      req.destroy();
    }
  }

  // ─── 内部 ───────────────────────────────────────────

  /**
   * 带退避重试 + 自动域名漂移的请求入口。
   *
   * 重试规则：
   *   - 重试：NetworkError / HttpStatusError 5xx / 429
   *   - 不重试：UnauthorizedError / CfBlockedError / 4xx 其他状态码
   *   - 退避：800ms × 2^attempt（1、2、4 秒）
   *
   * 漂移规则：
   *   - 连续失败 ≥ FALLBACK_FAIL_THRESHOLD 且处于重试过程中，则从 SPEED_RESULTS 挑下一个 alive 域名
   *   - 切换后原请求 url 取 path 部分与新 domain 拼接重试
   */
  private async request<T>(
    url: string,
    method: http.RequestMethod,
    body?: string,
    options?: HttpRequestOptions
  ): Promise<T> {
    let lastError: ApiError = new NetworkError('no_attempt');
    let currentUrl: string = url;

    // 请求入口 jitter：每次业务请求随机拖延 25-150ms，打乱并发节奏
    await sleep(jitterMs());

    for (let attempt = 0; attempt <= RETRY_LIMIT; attempt++) {
      try {
        const result: T = await this.attemptOnce<T>(currentUrl, method, body, options);
        // 成功：重置失败计数 + 清空 triedDomains、告知驱动面当前域名是健康的
        this.consecutiveFails = 0;
        if (this.triedDomains.size > 0) {
          this.triedDomains.clear();
        }
        return result;
      } catch (err) {
        lastError = err as ApiError;

        // 业务错（不重试）——直接抛
        if (err instanceof UnauthorizedError) {
          throw err as UnauthorizedError;
        }
        if (err instanceof CfBlockedError) {
          throw err as CfBlockedError;
        }
        if (err instanceof HttpStatusError) {
          const httpErr: HttpStatusError = err as HttpStatusError;
          // 4xx 除 429 不重试
          if (httpErr.statusCode >= 400 && httpErr.statusCode < 500 && httpErr.statusCode !== 429) {
            throw httpErr;
          }
        }

        // 应当重试：累计连续失败
        this.consecutiveFails++;
        Logger.w(TAG, `attempt ${attempt + 1} failed (${lastError.name}): ${lastError.message}`);

        // 到阈值 → 尝试漂移到备用域名
        if (this.consecutiveFails >= FALLBACK_FAIL_THRESHOLD) {
          const newDomain: string | null = this.pickFallbackDomain();
          if (newDomain !== null) {
            const oldDomain: string = this.domain;
            this.triedDomains.add(oldDomain);
            Logger.w(TAG, `auto-fallback domain: ${oldDomain} -> ${newDomain}`);
            // 后台 DoH 诊断旧域名，帮助分析失败原因（不阻塞重试）
            DohResolver.diagnoseAsync(oldDomain).catch((): void => { /* swallow */ });
            this.domain = newDomain;
            this.cookieJar.clear();
            this.consecutiveFails = 0;
            // url 里的 oldDomain 替为 newDomain，后续重试使新域名
            currentUrl = currentUrl.split(oldDomain).join(newDomain);
          }
        }

        // 如果还有机会重试 → 退避后继续
        if (attempt < RETRY_LIMIT) {
          const delayMs: number = RETRY_BASE_DELAY_MS * Math.pow(2, attempt);
          await sleep(delayMs);
          continue;
        }
      }
    }

    // 重试耗尽——lastError 始终是 ApiError（初值 与 attemptOnce 抛出的都是）
    throw lastError;
  }

  /** 单次请求（不重试）。仅被 request<T> 调用。 */
  private async attemptOnce<T>(
    url: string,
    method: http.RequestMethod,
    body?: string,
    options?: HttpRequestOptions
  ): Promise<T> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'User-Agent': pickUA(),
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': this.resolveAcceptLanguage(),
      };
      const cookie: string = this.buildCookieHeader(options?.skipAuthCookie === true);
      if (cookie.length > 0) {
        headers['Cookie'] = cookie;
      }
      if (options !== undefined && options.headers !== undefined) {
        const customKeys: string[] = Object.keys(options.headers);
        for (let i = 0; i < customKeys.length; i++) {
          headers[customKeys[i]] = options.headers[customKeys[i]];
        }
      }

      Logger.d(TAG, `${method} ${url}`);

      const reqOpts: http.HttpRequestOptions = {
        method,
        header: headers,
        extraData: body,
        connectTimeout: options?.connectTimeoutMs ?? 10000,
        readTimeout: options?.readTimeoutMs ?? 30000,
        expectDataType: http.HttpDataType.STRING,
      };
      if (this.proxyHost.length > 0 && this.proxyPort > 0) {
        reqOpts.usingProxy = {
          host: this.proxyHost,
          port: this.proxyPort,
          exclusionList: [],
        };
      }
      const resp: http.HttpResponse = await req.request(url, reqOpts);

      // 解析 set-cookie 入 jar（同域或上游 reader 域我们都收下）
      this.captureSetCookie(resp.header as Record<string, string | string[]>);

      const status: number = resp.responseCode;
      const text: string = typeof resp.result === 'string' ? resp.result : '';

      // Cloudflare 检测优先于状态码
      if (HttpClient.isCfBlocked(status, text, resp.header as Record<string, string | string[]>)) {
        throw new CfBlockedError();
      }

      if (status === 401) {
        throw new UnauthorizedError(text.length > 0 ? text : 'unauthorized');
      }
      if (status < 200 || status >= 400) {
        throw new HttpStatusError(status, text);
      }

      // 尝试 JSON
      const trimmed: string = text.trim();
      if (trimmed.length > 0 && (trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[')) {
        try {
          return JSON.parse(trimmed) as T;
        } catch (parseErr) {
          // 不是合法 JSON，按字符串返回
          return trimmed as Object as T;
        }
      }
      return trimmed as Object as T;
    } catch (err) {
      if (err instanceof ApiError) {
        // CfBlockedError / HttpStatusError / UnauthorizedError 全部走这里
        throw err as ApiError;
      }
      const e: BusinessError = err as BusinessError;
      const msg: string = e.message !== undefined && e.message !== null ? e.message : 'network_error';
      Logger.w(TAG, `request error ${url}: ${msg}`);
      throw new NetworkError(msg);
    } finally {
      req.destroy();
    }
  }

  /**
   * 从 SpeedTestVM 的全局结果中挑下一个可用且未尝试过的域名。
   * 只在 request 内部自动漂移使用；返回 null 表示没有可选。
   */
  private pickFallbackDomain(): string | null {
    const results: DomainTestResult[] | undefined =
      AppStorage.get<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS);
    if (results === undefined || results.length === 0) {
      return null;
    }
    // results 已按延迟升序；找第一个 alive 且不是当前且未尝试过的
    for (let i = 0; i < results.length; i++) {
      const r: DomainTestResult = results[i];
      const ms: number | null = r.latencyMs;
      if (ms !== null && ms > 0 && r.domain !== this.domain && !this.triedDomains.has(r.domain)) {
        return r.domain;
      }
    }
    return null;
  }

  private buildCookieHeader(skipAuth: boolean): string {
    const items: string[] = [];
    if (!skipAuth && this.remixUserId.length > 0 && this.remixUserKey.length > 0) {
      items.push(`remix_userid=${this.remixUserId}`);
      items.push(`remix_userkey=${this.remixUserKey}`);
    }
    // 注入站点语言偏好（zlib 服务端按此返回首页热门 / 近期等本地化内容）。
    // 若 cookieJar 已有同名 cookie（服务端 set-cookie 写过），跳过本地注入由 jar 接管。
    if (this.siteLanguage.length > 0 && this.siteLanguage !== 'all'
        && !this.cookieJar.has('siteLanguageV2')) {
      const profile: LangProfile | undefined = LANG_PROFILES[this.siteLanguage];
      if (profile !== undefined) {
        items.push(`siteLanguageV2=${profile.cookieValue}`);
      }
    }
    this.cookieJar.forEach((value: string, key: string) => {
      // remix_* 已显式注入，避免重复
      if (key === 'remix_userid' || key === 'remix_userkey') {
        return;
      }
      items.push(`${key}=${value}`);
    });
    return items.join('; ');
  }

  /**
   * 根据当前 siteLanguage 解析 Accept-Language 头。
   * 'all' / 空 / 未知 key 都退回默认 zh-CN，保证至少不暴露成纯英文环境。
   */
  private resolveAcceptLanguage(): string {
    if (this.siteLanguage.length === 0 || this.siteLanguage === 'all') {
      return DEFAULT_ACCEPT_LANGUAGE;
    }
    const profile: LangProfile | undefined = LANG_PROFILES[this.siteLanguage];
    return profile !== undefined ? profile.acceptLanguage : DEFAULT_ACCEPT_LANGUAGE;
  }

  private captureSetCookie(headers: Record<string, string | string[]>): void {
    if (headers === null || headers === undefined) {
      return;
    }
    let raw: string | string[] | undefined = undefined;
    const keys: string[] = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === 'set-cookie') {
        raw = headers[keys[i]];
        break;
      }
    }
    if (raw === undefined) {
      return;
    }
    const lines: string[] = Array.isArray(raw) ? raw : raw.split(/,(?=[^;]+=)/);
    for (let i = 0; i < lines.length; i++) {
      const segment: string = lines[i].split(';')[0].trim();
      const eqIdx: number = segment.indexOf('=');
      if (eqIdx <= 0) {
        continue;
      }
      const name: string = segment.substring(0, eqIdx).trim();
      const value: string = segment.substring(eqIdx + 1).trim();
      // siteLanguageV2 由 setSiteLanguage 独占控制；忽略服务端写入，避免反向覆盖用户偏好。
      // 否则切换语言后第一次请求生效，但响应的 set-cookie 会把 jar 改回旧值，导致后续请求被服务端锁死。
      if (name === 'siteLanguageV2') {
        continue;
      }
      if (name.length > 0 && value.length > 0) {
        this.cookieJar.set(name, value);
      }
    }
  }

  private static isCfBlocked(status: number, body: string, headers: Record<string, string | string[]>): boolean {
    if (status === 403 || status === 503) {
      if (headers !== null && headers !== undefined) {
        const headerKeys: string[] = Object.keys(headers);
        for (let i = 0; i < headerKeys.length; i++) {
          const lk: string = headerKeys[i].toLowerCase();
          if (lk === 'cf-mitigated') {
            return true;
          }
        }
      }
    }
    for (let i = 0; i < CF_MARKERS.length; i++) {
      if (body.indexOf(CF_MARKERS[i]) >= 0) {
        return true;
      }
    }
    return false;
  }
}
