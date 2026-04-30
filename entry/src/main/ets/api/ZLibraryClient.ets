/*
 * ZLibraryClient.ets
 *
 * 业务层 API：封装 olib-mobile lib/services/zlibrary_api.dart 同语义的方法集合。
 * 单实例，依赖底层 HttpClient 单例。
 *
 * 设计说明：
 *   - 端点路径优先采用 /eapi/* 命名空间（与 olib speed_test 探针一致）。
 *   - 鉴权类接口（login/profile/save/...）依赖 HttpClient 注入的 cookie。
 *   - 输出统一为强类型对象（Book / User）；服务端返回 success!=1 时抛 ApiError，让上层判定文案。
 *   - 下载方法仅返回元信息；真正的字节流落盘走 P3 的 DownloadVM（基于 request.agent）。
 */

import { Book } from '../model/Book';
import { User } from '../model/User';
import { HttpClient, QueryParams, FormParams, HttpRequestOptions } from './HttpClient';
import { ApiError, ApiResponse } from './ApiTypes';
import { Logger } from '../utils/Logger';

const TAG: string = 'ZLibraryClient';

interface BooksEnvelope extends ApiResponse {
  books?: object[];
  pagination?: PaginationJson;
}
interface BookEnvelope extends ApiResponse {
  book?: object;
}
interface UserEnvelope extends ApiResponse {
  user?: object;
}
interface InfoEnvelope extends ApiResponse {}
interface PaginationJson {
  total_pages?: number | string;
  current_page?: number | string;
  total_items?: number | string;
}

export interface SearchPage {
  books: Book[];
  totalPages: number;
  currentPage: number;
}

export interface SearchOptions {
  message?: string;
  yearFrom?: number;
  yearTo?: number;
  languages?: string[];
  extensions?: string[];
  order?: string;
  page?: number;
  limit?: number;
}

export class ZLibraryClient {
  private static _instance: ZLibraryClient | null = null;

  static get instance(): ZLibraryClient {
    if (!ZLibraryClient._instance) {
      ZLibraryClient._instance = new ZLibraryClient();
    }
    return ZLibraryClient._instance;
  }

  private get http(): HttpClient {
    return HttpClient.instance;
  }

  // ─── 鉴权 ───────────────────────────────────────────

  /**
   * 用户名/邮箱 + 密码登录。成功后会自动给 HttpClient 注入 cookie。
   *
   * 字段名 `user_email` / `user_password` 与 olib 二进制 release 包逆向得到的字段一致。
   * 同时透传 email/password 作为兼容（部分镜像两套字段都接受）。
   */
  async login(email: string, password: string): Promise<User> {
    const form: FormParams = {};
    form['user_email'] = email;
    form['user_password'] = password;
    form['email'] = email;
    form['password'] = password;
    const opts: HttpRequestOptions = { skipAuthCookie: true };
    const json: UserEnvelope = await this.http.postForm<UserEnvelope>(
      '/eapi/user/login', form, opts
    );
    ZLibraryClient.assertOk(json);
    const user: User = User.fromJson(json.user as object);
    this.http.setAuth(user.id, user.remixUserkey);
    return user;
  }

  /** Token 登录：以已知的 userId / userKey 直接拉 profile。 */
  async loginWithToken(userId: string, userKey: string): Promise<User> {
    this.http.setAuth(userId, userKey);
    return await this.getProfile();
  }

  /** 当前账户信息。 */
  async getProfile(): Promise<User> {
    const json = await this.http.get<UserEnvelope>('/eapi/user/profile');
    ZLibraryClient.assertOk(json);
    return User.fromJson(json.user as object);
  }

  /** 退登：清空内存中的 cookie。 */
  logout(): void {
    this.http.clearAuth();
  }

  // ─── 浏览 / 搜索 ────────────────────────────────────

  /**
   * 推荐书目（首页 Trending）。
   * 注：此 endpoint 是基于登录账号历史的个性化推荐，languages 参数可能不被服务端尊重，
   * 但仍透传以保持调用一致性。
   */
  async getUserRecommended(languages?: string[]): Promise<Book[]> {
    const query: QueryParams = {};
    if (languages !== undefined && languages.length > 0) {
      query['languages'] = languages;
    }
    const json = await this.http.get<BooksEnvelope>('/eapi/user/book/recommended', query);
    ZLibraryClient.assertOk(json);
    return Book.fromJsonList(json.books as object[]);
  }

  /**
   * 站内最热门书目（全站统计，**不按用户语言过滤**）。
   * 不推荐直接给首页用——zlib 服务端这个 endpoint 永远返回全站最热（英文为主），
   * cookie/Accept-Language/languages query 都被忽略。建议使用 `getPopularByLanguage` 替代。
   */
  async getMostPopular(languages?: string[]): Promise<Book[]> {
    const query: QueryParams = {};
    if (languages !== undefined && languages.length > 0) {
      query['languages'] = languages;
    }
    const json = await this.http.get<BooksEnvelope>('/eapi/book/most-popular', query);
    ZLibraryClient.assertOk(json);
    return Book.fromJsonList(json.books as object[]);
  }

  /**
   * 近期上传（全站统计，同上不按语言过滤）。
   * 建议使用 `getRecentByLanguage` 替代。
   */
  async getRecently(languages?: string[]): Promise<Book[]> {
    const query: QueryParams = {};
    if (languages !== undefined && languages.length > 0) {
      query['languages'] = languages;
    }
    const json = await this.http.get<BooksEnvelope>('/eapi/book/recently', query);
    ZLibraryClient.assertOk(json);
    return Book.fromJsonList(json.books as object[]);
  }

  /**
   * 按语言过滤的热门书（首页推荐用）。
   *
   * 等价于 zlib 官方 app 行为：调 `/eapi/book/search?message=*&languages[]=chinese&order=popular`。
   * 由于 most-popular endpoint 不尊重 languages 过滤，必须走 search 替代。
   */
  async getPopularByLanguage(languages: string[], limit: number = 30): Promise<Book[]> {
    const result: SearchPage = await this.search({
      languages: languages,
      order: 'popular',
      page: 1,
      limit: limit,
    });
    return result.books;
  }

  /**
   * 按语言过滤的近期上传（首页推荐用）。
   * 走 search endpoint，order=date 按时间倒序。
   */
  async getRecentByLanguage(languages: string[], limit: number = 30): Promise<Book[]> {
    const result: SearchPage = await this.search({
      languages: languages,
      order: 'date',
      page: 1,
      limit: limit,
    });
    return result.books;
  }

  /**
   * 搜索 + 筛选 + 分页。
   *
   * 用 POST application/x-www-form-urlencoded（与 olib 内部 _makePostRequest 一致）。
   * 早期 hlib 用 GET，中文 query + languages[] 数组在 URL 中过长 → 触发 400。改 POST 解决。
   */
  async search(options: SearchOptions): Promise<SearchPage> {
    const form: FormParams = {};
    if (options.message !== undefined) form['message'] = options.message;
    if (options.yearFrom !== undefined) form['yearFrom'] = options.yearFrom;
    if (options.yearTo !== undefined) form['yearTo'] = options.yearTo;
    if (options.languages !== undefined && options.languages.length > 0) form['languages'] = options.languages;
    if (options.extensions !== undefined && options.extensions.length > 0) form['extensions'] = options.extensions;
    if (options.order !== undefined) form['order'] = options.order;
    form['page'] = options.page !== undefined ? options.page : 1;
    form['limit'] = options.limit !== undefined ? options.limit : 20;

    const json: BooksEnvelope = await this.http.postForm<BooksEnvelope>('/eapi/book/search', form);
    ZLibraryClient.assertOk(json);
    const books: Book[] = Book.fromJsonList(json.books as object[]);
    const totalPages: number = ZLibraryClient.toInt(json.pagination?.total_pages, 1);
    const currentPage: number = ZLibraryClient.toInt(
      json.pagination?.current_page,
      options.page !== undefined ? options.page : 1
    );
    const result: SearchPage = { books: books, totalPages: totalPages, currentPage: currentPage };
    return result;
  }

  /** 书籍详情（包含 description / readOnlineUrl 等首屏列表里没有的字段）。 */
  async getBookInfo(bookId: number | string, hashId: string): Promise<Book> {
    const json = await this.http.get<BookEnvelope>(`/eapi/book/${bookId}/${hashId}`);
    ZLibraryClient.assertOk(json);
    return Book.fromJson(json.book as object);
  }

  /** 相似书籍。 */
  async similar(bookId: number | string, hashId: string): Promise<Book[]> {
    const json = await this.http.get<BooksEnvelope>(`/eapi/book/${bookId}/${hashId}/similar`);
    ZLibraryClient.assertOk(json);
    return Book.fromJsonList(json.books as object[]);
  }

  // ─── 用户图书馆 ─────────────────────────────────────

  async getUserSaved(limit: number = 100): Promise<Book[]> {
    const query: QueryParams = {};
    query['limit'] = limit;
    const json: BooksEnvelope = await this.http.get<BooksEnvelope>('/eapi/user/book/saved', query);
    ZLibraryClient.assertOk(json);
    return Book.fromJsonList(json.books as object[]);
  }

  async getUserDownloaded(limit: number = 100): Promise<Book[]> {
    const query: QueryParams = {};
    query['limit'] = limit;
    const json: BooksEnvelope = await this.http.get<BooksEnvelope>('/eapi/user/book/downloaded', query);
    ZLibraryClient.assertOk(json);
    return Book.fromJsonList(json.books as object[]);
  }

  async saveBook(bookId: number | string, hash?: string): Promise<void> {
    const form: FormParams = ZLibraryClient.bookIdForm(bookId);
    // 优先使用 /eapi/book/{id}/{hash}/save（与 /file、/similar 同级），兼容旧路径
    if (hash !== undefined && hash.length > 0) {
      try {
        const json: ApiResponse = await this.http.postForm<ApiResponse>(
          `/eapi/book/${bookId}/${hash}/save`, form);
        ZLibraryClient.assertOk(json);
        return;
      } catch (e) {
        Logger.w(TAG, `saveBook /eapi/book/${bookId}/${hash}/save failed: ${(e as Error).message}, trying fallback`);
      }
    }
    const json: ApiResponse = await this.http.postForm<ApiResponse>('/eapi/user/book/save', form);
    ZLibraryClient.assertOk(json);
  }

  async unsaveBook(bookId: number | string, hash?: string): Promise<void> {
    const form: FormParams = ZLibraryClient.bookIdForm(bookId);
    if (hash !== undefined && hash.length > 0) {
      try {
        const json: ApiResponse = await this.http.postForm<ApiResponse>(
          `/eapi/book/${bookId}/${hash}/unsave`, form);
        ZLibraryClient.assertOk(json);
        return;
      } catch (e) {
        Logger.w(TAG, `unsaveBook /eapi/book/${bookId}/${hash}/unsave failed: ${(e as Error).message}, trying fallback`);
      }
    }
    const json: ApiResponse = await this.http.postForm<ApiResponse>('/eapi/user/book/unsave', form);
    ZLibraryClient.assertOk(json);
  }

  /** 同时携带 camelCase / snake_case bookId 字段，兼容服务端不同命名约定。 */
  private static bookIdForm(bookId: number | string): FormParams {
    const id: string = String(bookId);
    const form: FormParams = {};
    form['bookId'] = id;
    form['book_id'] = id;
    return form;
  }

  // ─── 探针 ───────────────────────────────────────────

  /** 探测某域名是否可达；不污染 cookie jar，不抛异常。 */
  async pingDomain(domain: string, timeoutMs: number = 8000): Promise<number> {
    return await this.http.ping(domain, timeoutMs);
  }

  /** 切换镜像域；登录态会被保留（cookie 之外的 set-cookie 会清掉以避免跨域）。 */
  setDomain(domain: string): void {
    this.http.setDomain(domain);
  }

  // ─── 内部 ───────────────────────────────────────────

  private static assertOk(resp: ApiResponse): void {
    const ok = resp.success === true || resp.success === 1;
    if (!ok) {
      const msg = resp.error || resp.message || 'api_failed';
      throw new ApiError(msg);
    }
  }

  private static toInt(v: number | string | undefined | null, def: number): number {
    if (v === undefined || v === null) {
      return def;
    }
    if (typeof v === 'number') {
      return Number.isFinite(v) ? Math.trunc(v) : def;
    }
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : def;
  }
}
