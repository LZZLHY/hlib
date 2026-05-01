/*
 * AppStorageKeys.ets
 * AppStorage / PersistentStorage 中使用的全部键名常量化，避免拼写错误。
 */

export class AppStorageKeys {
  // ── 与 PersistentStorage 关联（自动持久化为 ArkUI 内部文件） ──
  static readonly DOMAIN: string         = 'pref_domain';        // 当前 Z-Library 镜像域
  static readonly THEME_MODE: string     = 'pref_themeMode';     // 'system' | 'light' | 'dark'
  static readonly LOCALE: string         = 'pref_locale';        // '' | 'zh-Hans' | 'en-US'
  static readonly DOWNLOAD_PATH: string  = 'pref_downloadPath';  // 自定义下载目录（'' / 'default' / 'cache' / 绝对路径）

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
  /** 上次成功测速完成的 ms 时间戳；用于 SpeedTestVM 的 TTL 判定。 */
  static readonly SPEED_LAST_TS: string    = 'state_speedLastTs';
  /** 应用版本号（versionName），EntryAbility 启动时通过 bundleManager 读取写入。 */
  static readonly APP_VERSION: string      = 'state_appVersion';

  // ── 首页缓存 ──
  static readonly HOME_RECOMMENDED: string = 'state_homeRecommended'; // Book[]
  static readonly HOME_POPULAR: string     = 'state_homePopular';     // Book[]
  static readonly HOME_RECENT: string      = 'state_homeRecent';      // Book[]
  static readonly HOME_LOADING: string     = 'state_homeLoading';     // boolean

  // ── 响应式布局（EntryAbility 监听 windowSizeChange 写入；UI 用 @StorageProp 订阅） ──
  /** 当前窗口宽度（vp）。值随窗口大小变化实时更新。 */
  static readonly SCREEN_WIDTH_VP: string  = 'state_screenWidthVp';
  /** 当前断点：'sm' | 'md' | 'lg' | 'xl'，由 SCREEN_WIDTH_VP 派生。 */
  static readonly BREAKPOINT: string       = 'state_breakpoint';
  /** 导航样式偏好：'auto' | 'bottom' | 'side'，平板/折叠用户可在设置切换。 */
  static readonly NAV_STYLE: string        = 'pref_navStyle';

  // ── 合规：隐私政策同意 ──
  /**
   * 用户已同意的隐私政策版本号。空串 / 不存在 → 视为未同意，启动时拉同意弹窗。
   * 改版隐私政策后递增此版本字符串即可强制重新同意。
   */
  static readonly PRIVACY_AGREED_VERSION: string = 'pref_privacyAgreedVersion';

  /**
   * PrivacyPage 卸载时间戳（ms）——作为跨组件信号：
   * SplashPage 监听此值变化以重新拉起同意弹窗（NavDestination.onShown 在某些 SDK 上从子路由返回时不触发）。
   * 仅作信号，不持久化。
   */
  static readonly PRIVACY_PAGE_CLOSED_AT: string = 'state_privacyPageClosedAt';
}

/** 当前隐私政策版本（与 string.json 中 privacy_effective_date 保持一致）。 */
export const PRIVACY_POLICY_VERSION: string = '2026-05-01';

export type ThemeMode = 'system' | 'light' | 'dark';
export type Breakpoint = 'sm' | 'md' | 'lg' | 'xl';
export type NavStyle = 'auto' | 'bottom' | 'side';
export const DEFAULT_DOMAIN: string = 'pkuedu.online';
