/*
 * AppStorageKeys.ets
 * AppStorage / PersistentStorage 中使用的全部键名常量化，避免拼写错误。
 */

export class AppStorageKeys {
  // ── 与 PersistentStorage 关联（自动持久化为 ArkUI 内部文件） ──
  static readonly DOMAIN: string         = 'pref_domain';        // 当前 Z-Library 镜像域
  static readonly THEME_MODE: string     = 'pref_themeMode';     // 'system' | 'light' | 'dark'
  static readonly LOCALE: string         = 'pref_locale';        // '' | 'zh-Hans' | 'en-US'
  static readonly DOWNLOAD_PATH: string  = 'pref_downloadPath';  // 自定义下载目录（空字符串=默认沙箱）

  // ── 协议层加固偏好（存 settings 分组） ──
  static readonly PROXY_ENABLED: string          = 'pref_proxyEnabled';        // boolean
  static readonly PROXY_HOST: string             = 'pref_proxyHost';           // string，例 '127.0.0.1'
  static readonly PROXY_PORT: string             = 'pref_proxyPort';           // number
  static readonly DOH_ENABLED: string            = 'pref_dohEnabled';          // boolean，是否走 DoH 解析
  static readonly DOMAIN_MANIFEST_ENABLED: string = 'pref_domainManifestEnabled'; // boolean
  static readonly DOMAIN_MANIFEST_URL: string     = 'pref_domainManifestUrl';     // 远程镜像列表 URL

  /** 首页推荐内容地区/语言。'' = 跟随 UI 语言推断；'all' = 不限；'zh'/'en'/'ja'/... = 指定。独立于 UI 语言。 */
  static readonly CONTENT_LANG: string           = 'pref_contentLang';

  // ── 仅 AppStorage 内存态（由各 Store 自己负责持久化到 preferences） ──
  static readonly USER: string             = 'state_user';            // User | null
  static readonly FAVORITE_IDS: string     = 'state_favoriteIds';     // number[]
  static readonly FAVORITE_BOOKS: string   = 'state_favoriteBooks';   // Book[]
  static readonly DOWNLOAD_TASKS: string   = 'state_downloadTasks';   // DownloadTask[]
  static readonly DOWNLOAD_HISTORY: string = 'state_downloadHistory'; // DownloadHistoryItem[]
  static readonly SPEED_RESULTS: string    = 'state_speedResults';    // DomainTestResult[]

  // ── 首页缓存 ──
  static readonly HOME_RECOMMENDED: string = 'state_homeRecommended'; // Book[]
  static readonly HOME_POPULAR: string     = 'state_homePopular';     // Book[]
  static readonly HOME_RECENT: string      = 'state_homeRecent';      // Book[]
  static readonly HOME_LOADING: string     = 'state_homeLoading';     // boolean
}

export type ThemeMode = 'system' | 'light' | 'dark';
export const DEFAULT_DOMAIN: string = 'pkuedu.online';
