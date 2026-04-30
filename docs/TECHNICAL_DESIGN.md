# HLib · 鸿蒙 Next 端 Z-Library 第三方客户端 · 技术设计文档

> 版本：v0.1（设计阶段）
> 工作目录：`d:/SystemDefalt/Desktop/hlib`
> 参考项目：`D:/SystemDefalt/Desktop/olib-mobile-main`（Flutter / Dart）
> 目标平台：HarmonyOS Next（API 12+，`compatibleSdkVersion 6.1.0(23)`）
> 主要语言：ArkTS（Stage 模型）+ ArkUI 声明式 UI

---

## 1. 项目目标与范围

复刻并改良 olib-mobile（Flutter 版 Z-Library 三方客户端）的核心功能，输出一个**纯原生鸿蒙**的应用。

### 1.1 必做（MVP）

- **登录态管理**：邮箱+密码登录、Token（`remix_userid`/`remix_userkey`）登录、本地缓存、自动重登、多账号切换。
- **首页**：欢迎语、搜索入口、推荐书目（`recommended` / `most_popular` / `recently`）瀑布流。
- **搜索**：全文搜索 + 语言/格式/排序筛选 + 分页加载（页码-pagination）+ 列表/网格切换。
- **书籍详情**：封面 Hero、元数据胶囊、描述、相似书籍入口；底部"在线阅读 + 下载"双按钮。
- **收藏**：服务端拉取已收藏书目（`getUserSaved`）+ 本地索引；批量删除。
- **下载**：调用 `/dl/...` 接口流式下载到公共下载目录，断点取消、进度持久化、打开/分享/删除。
- **在线阅读**：`Web` 组件加载 `reader.{domain}` 阅读器域名，附带身份 cookie。
- **设置**：主题（系统/浅色/深色）、语言（中/英）、线路切换（域名 + 自定义）、清除缓存、退出登录、关于。
- **线路管理**：内置镜像域名列表 + 并发测速 + 延迟着色 + 自定义域名。

### 1.2 改进点（相对原项目）

| 改进 | 理由 |
|------|------|
| 抛弃 `flutter_inappwebview` 等重度依赖，使用鸿蒙原生 `Web` 组件 | 体积更小、更贴合 HarmonyOS 设计语言 |
| 使用 `Navigation` + `NavPathStack` 替代命名路由 | 更原生的转场动效，支持 1+1 大屏分栏 |
| 状态层用 ArkTS `AppStorage` + `@ObservedV2/@Trace`（V2 装饰器）替代 Riverpod | 框架原生支持，编译期可观测 |
| 主题色与系统 Harmony 配色（`$r('sys.color.brand')` 等）联动 | 跟随系统强调色，符合 HarmonyOS 设计规范 |
| 适配折叠屏 / 平板（`deviceTypes: ["phone", "tablet", "2in1"]`） | `BreakpointSystem` + `GridRow` 自适应 |
| 移除"AI 智阅锦囊"等需要私有后端的特性（v1 暂缓） | 减少发布依赖，避免直接复用作者后端 |
| 移除广告 SDK（Unity Ads） | 无广告策略，符合鸿蒙商店审核要求 |
| 用鸿蒙 `request.agent.create` 替代 Dio 下载 | 系统级断点续传 + 后台下载 + 通知栏进度 |

### 1.3 不做 / 后置

- AI 智阅锦囊（依赖原作者私有后端 `olibai.11xy.cn`）。
- 微信扫码登录（依赖私有 `wxauth.11xy.cn`）。
- 收藏分享 / QR 码生成 / QR 扫码导入（v2 再补，鸿蒙 ScanKit 可平替）。
- 强更新 / 公告 / 内购 / 应用内升级。

---

## 2. 参考项目（olib-mobile）架构总览

### 2.1 技术栈

```
Flutter 3.8 + Dart 3
状态管理：flutter_riverpod
HTTP：dio + dio_cookie_manager + cookie_jar
本地存储：hive + hive_flutter
WebView：flutter_inappwebview
下载位置：path_provider + permission_handler + device_info_plus
```

### 2.2 目录结构

```
lib/
├── main.dart                # MaterialApp + ProviderScope，命名路由
├── routes/app_routes.dart   # 路由常量
├── config/env.dart          # 环境变量（私有后端 URL，鸿蒙端可删）
├── theme/                   # AppColors + AppTheme（明暗主题）
├── l10n/                    # 16+ 语言 ARB 翻译
├── models/                  # Book, User, Prescription, ApiResponse
├── services/
│   ├── zlibrary_api.dart    # 【已 .gitignore】Z-Library HTTP 封装
│   ├── auth_storage.dart    # 凭证 Hive 存取
│   ├── storage_service.dart # 偏好/收藏/下载历史 Hive 存取
│   ├── hive_service.dart    # Hive 初始化
│   ├── update_service.dart  # 升级检测
│   ├── ad_service.dart      # 广告
│   └── ai_service.dart      # AI 锦囊后端
├── providers/               # Riverpod Notifier
│   ├── auth_provider.dart
│   ├── books_provider.dart
│   ├── domain_provider.dart
│   ├── speed_test_provider.dart
│   ├── download_provider.dart
│   ├── settings_provider.dart
│   └── zlibrary_provider.dart
├── widgets/                 # BookCard, BookListTile, GradientAppBar, …
└── screens/
    ├── splash/              # 启动屏 + 网络检测 + 鉴权重定向
    ├── auth/                # 登录 / QR 扫码登录
    ├── home/                # 首页（Tab 容器）
    ├── search/              # 搜索 + 筛选
    ├── book_detail/         # 书籍详情
    ├── similar/             # 相似书
    ├── favorites/           # 收藏
    ├── downloads/           # 本地下载
    ├── reader/              # 在线阅读 WebView
    └── settings/            # 设置 + 历史
```

### 2.3 核心数据流

```
       ┌──────────────────┐
UI ──▶ │ Riverpod Provider│ ──▶ ZLibraryApi (Dio) ──▶ https://{mirror}/eapi/...
       └────────▲─────────┘                                     │
                │                                               ▼
        Hive (settings, auth) ◀────── 持久化（cookie / token / 偏好）
```

---

## 3. Z-Library API 契约（从源码反推）

> `services/zlibrary_api.dart` 在仓库被 `.gitignore` 掩藏，下表是从 `providers/*` 与 `screens/*` 的调用方式逆向推断的接口形态。鸿蒙端将以**等价语义**重新实现为 `ZLibraryClient`。

### 3.1 基础

- **基地址**：`https://{currentDomain}` —— 由 `domain_provider` 持久化于 Hive `settings.domain`，默认 `pkuedu.online`，可由用户改为 50+ 镜像域之一或自定义域。
- **健康/测速探针**：`GET /eapi/info/languages`，预期响应包含 `"success":1`。
- **鉴权**：登录成功后获得 `remix_userid` / `remix_userkey`，作为 Cookie 与下载 URL 查询串携带。
- **响应壳**：`{"success": 1|true, ...payload }` 或 `{"success": 0|false, "error": "...", "message": "..."}`。

### 3.2 已使用的方法（按源码调用归纳）

| TS 方法名（拟） | Dart 调用 | 入参 | 返回关键字段 |
|----|----|----|----|
| `setDomain(domain)` | `_api.setDomain` | 镜像域名（无协议） | — |
| `login(email, pwd)` | `_api.login` | `email`,`password` | `{success, user:{id,name,email,remix_userkey,…}}` |
| `loginWithToken(uid,key)` | `_api.loginWithToken` | `userId`,`userKey` | 同上 |
| `getProfile()` | `_api.getProfile` | — | `{success, user:{…}}` |
| `sendCode/verifyCode` | 注册流程 | email/pwd/name(/code) | `{success, …}`（注：客户端已禁用） |
| `search(...)` | `searchResultsProvider` | `message,yearFrom,yearTo,languages[],extensions[],order,page,limit` | `{success, books:[Book], pagination:{total_pages,…}}` |
| `getBookInfo(id, hash)` | `bookDetailsProvider` | `bookId`,`hashId` | `{success, book:Book}` |
| `getMostPopular()` | `mostPopularBooksProvider` | — | `{success, books:[Book]}` |
| `getUserRecommended()` | `recommendedBooksProvider` | — | 同上 |
| `getRecently()` | `recentBooksProvider` | — | 同上 |
| `getUserSaved(limit)` | `SavedBooksNotifier` | `limit` | 同上 |
| `getUserDownloaded(limit)` | `downloadedBooksProvider` | `limit` | 同上 |
| `saveBook(id)` / `unsaveUserBook(id)` | 同名 | `bookId` | `{success}` |
| `Similar(id, hash)` | `similar_books_screen` | `bookId`,`hashId` | `{success, books:[Book]}` |
| `downloadBook(id, hash, savePath, onProgress, cancelToken)` | `DownloadNotifier` | book id+hash+本地保存路径 | 直接落盘文件 |

### 3.3 Book 实体（核心字段）

```ts
interface Book {
  id: number;
  title: string;
  author?: string;
  year?: number;
  publisher?: string;
  pages?: number;
  language?: string;
  cover?: string;            // 封面 URL
  extension?: string;        // pdf / epub / …
  filesize?: number;         // bytes
  filesizeString?: string;   // 已格式化
  description?: string;
  series?: string;
  identifier?: string;       // ISBN
  hash?: string;             // 详情/相似/下载需要
  href?: string;             // 详情页相对路径
  dl?: string;               // 下载相对路径
  readOnlineUrl?: string;    // 在线阅读 URL
  readOnlineAvailable?: boolean;
  kindleAvailable?: boolean;
  sendToEmailAvailable?: boolean;
  interestScore?: string;    // 评分（字符串）
  qualityScore?: string;
  termsHash?: string;
  md5?: string;
  sha256?: string;
}
```

### 3.4 在线阅读 URL 重写规则（`book_detail_screen.dart` 解读）

读取的 `book.readOnlineUrl` 形如 `https://reader.z-library.sk/book/...`，需要替换为当前镜像所对应的 `reader.{domain}`：

1. 取当前域 `customDomain`，若以 `zh./en./de./…` 等语言前缀开头，则把 `reader` 替换该前缀；否则前置 `reader.`。
2. `cdn.reader.` → `reader.`。
3. `reader.[a-z0-9.-]+` → 上一步得到的 `readerDomain`。
4. `z-library.[a-z]+` → `customDomain`。
5. 拼接 `?remix_userkey=…&remix_userid=…`。

---

## 4. HarmonyOS Next 技术栈选型

### 4.1 Kits / 模块对照

| 能力 | 鸿蒙 API | 替换的 Flutter 包 |
|------|----------|-------------------|
| HTTP 客户端 | `@kit.NetworkKit` → `@ohos.net.http` | `dio` |
| Cookie 持久化 | `web_webview.WebCookieManager`（阅读器复用） + 自管 cookie 头 | `cookie_jar` |
| 大文件下载 | `@kit.BasicServicesKit` → `@ohos.request` 的 `request.agent.create`（后台 + 通知 + 断点） | `dio` 流式下载 + permission_handler |
| 持久化（KV） | `@kit.ArkData` → `@ohos.data.preferences` | `hive` |
| 持久化（结构化大量数据） | `@kit.ArkData` → `@ohos.data.relationalStore`（仅当下载历史超大时启用） | `hive` |
| 文件 I/O | `@kit.CoreFileKit` → `@ohos.file.fs` | `dart:io` |
| 文件选择/打开 | `@kit.CoreFileKit` → `@ohos.file.picker` + `@ohos.app.ability.common` Want 启动 | `file_picker` / `open_filex` |
| WebView | ArkUI `Web` 组件（`@ohos.web.webview`） | `flutter_inappwebview` |
| 二维码扫描 | `@kit.ScanKit` → `@ohos.scan.scanCore` | `mobile_scanner` |
| 二维码生成 | `@kit.ScanKit` → `customScan.generateBarcode` | `qr_flutter` |
| 图片缓存 | `Image` + 系统缓存；自实现 LRU；或 `@ohos/image-knife` 三方库 | `cached_network_image` |
| 路由 | `Navigation` + `NavPathStack` | `Navigator.pushNamed` |
| 状态管理 | `@State/@Prop/@Link/@Provide/@Consume` + `AppStorage`/`PersistentStorage` + V2 `@ObservedV2/@Trace` | `Riverpod` |
| 国际化 | `$r('app.string.xxx')` + 多 `resources/{base|zh_CN|en_US}/element/string.json` | `flutter_localizations` |
| 主题（深色） | `resources/dark/element/color.json` | `ThemeData.dark` |
| 分享 | `Want` + `action: ohos.want.action.sendData` | `share_plus` |
| 设备信息 | `@kit.BasicServicesKit` → `@ohos.deviceInfo` | `device_info_plus` |
| 包信息 | `@kit.AbilityKit` → `bundleManager` | `package_info_plus` |
| 浏览器跳转 | Want 启动 `ohos.want.action.viewData` | `url_launcher` |

### 4.2 工程结构（建议）

```
entry/
└── src/main/ets/
    ├── entryability/
    │   └── EntryAbility.ets                # 已存在；将增加首屏路由判断
    ├── pages/
    │   └── Index.ets                       # 已存在；将改造为 Navigation 容器
    ├── api/                                【新增】
    │   ├── HttpClient.ets                  # 通用 HTTP（拦截器、Cookie、重试）
    │   ├── ZLibraryClient.ets              # 业务 API
    │   └── ApiTypes.ets                    # ApiResponse / 错误码
    ├── model/                              【新增】
    │   ├── Book.ets
    │   ├── User.ets
    │   └── DomainTestResult.ets
    ├── storage/                            【新增】
    │   ├── PreferencesStore.ets            # 偏好键值（主题/语言/域名/凭证）
    │   ├── AuthStore.ets                   # 凭证封装
    │   ├── FavoritesStore.ets              # 本地收藏索引
    │   └── DownloadHistoryStore.ets        # 下载历史
    ├── viewmodel/                          【新增 V2】
    │   ├── AuthVM.ets
    │   ├── BooksVM.ets
    │   ├── DomainVM.ets
    │   ├── SpeedTestVM.ets
    │   ├── DownloadVM.ets
    │   └── SettingsVM.ets
    ├── pages/                              【新增多页】
    │   ├── SplashPage.ets
    │   ├── LoginPage.ets
    │   ├── MainPage.ets                    # Tabs 容器
    │   ├── HomePage.ets
    │   ├── SearchPage.ets
    │   ├── BookDetailPage.ets
    │   ├── SimilarBooksPage.ets
    │   ├── FavoritesPage.ets
    │   ├── DownloadsPage.ets
    │   ├── ReaderPage.ets
    │   ├── SettingsPage.ets
    │   └── HistoryPage.ets
    ├── components/                         【新增】
    │   ├── BookCard.ets
    │   ├── BookListTile.ets
    │   ├── GradientAppBar.ets
    │   ├── DomainSelector.ets
    │   ├── EmptyState.ets
    │   ├── LoadingView.ets
    │   └── Capsule.ets                     # 元数据胶囊
    ├── theme/                              【新增】
    │   ├── AppColors.ets
    │   └── AppTextStyles.ets
    └── utils/                              【新增】
        ├── Logger.ets
        ├── FileUtils.ets
        ├── UrlUtils.ets                    # readerDomain 重写算法
        └── Permissions.ets
└── src/main/resources/
    ├── base/element/
    │   ├── string.json                     # zh-Hans 默认
    │   └── color.json                      # 浅色主题色
    ├── en_US/element/string.json           # 英文翻译
    └── dark/element/color.json             # 深色主题色
```

模块清单 `main_pages.json` 必须列出所有页面（HarmonyOS 要求）。

---

## 5. 模块映射详细对照

### 5.1 启动流程

| Flutter 行为 | 鸿蒙 ArkTS 实现 |
|---|---|
| `main()` → `runApp(ProviderScope)` | `EntryAbility.onWindowStageCreate` → `windowStage.loadContent('pages/SplashPage')` |
| `SplashScreen` 检查网络 + 鉴权后 `pushReplacement` | `SplashPage.aboutToAppear`：`PreferencesStore.init()` → `AuthVM.bootstrap()` → `router.replaceUrl({url: 'pages/LoginPage'})` 或 `'pages/MainPage'` |
| 前台并发预热 `speedTestProvider.runTest()` | `SpeedTestVM.runTest()` 异步触发 |

### 5.2 路由方案

采用**双层路由**：

- **顶层 `router`**（`@kit.ArkUI` 的 `@ohos.router`）用于主流程页面切换：`Splash → Login → Main`、详情页、阅读页等。
- **`MainPage` 内 `Tabs`** 承载 4 个底栏：首页 / 搜索 / 收藏 / 下载。

### 5.3 状态管理

- **全局共享**：`AppStorage.setOrCreate('user', ...)`、`PersistentStorage.persistProp('domain', 'pkuedu.online')`。
- **页面级**：`@State` / `@ObservedV2 + @Trace` 类（V2 装饰器）。
- **跨页传递**：`@StorageProp/@StorageLink` 订阅 AppStorage。

ViewModel 模板：

```ts
@ObservedV2
export class BooksVM {
  @Trace recommended: Book[] = [];
  @Trace popular: Book[] = [];
  @Trace recent: Book[] = [];
  @Trace loading: boolean = false;

  constructor(private api: ZLibraryClient) {}

  async loadHome(): Promise<void> {
    this.loading = true;
    const [r, p, n] = await Promise.allSettled([
      this.api.getUserRecommended(),
      this.api.getMostPopular(),
      this.api.getRecently(),
    ]);
    if (r.status === 'fulfilled') this.recommended = r.value;
    if (p.status === 'fulfilled') this.popular = p.value;
    if (n.status === 'fulfilled') this.recent = n.value;
    this.loading = false;
  }
}
```

---

## 6. 关键子系统设计

### 6.1 HTTP 客户端（`api/HttpClient.ets`）

- 基于 `@ohos.net.http` 的 `http.createHttp()`，单实例 + 串行化请求队列（鸿蒙的 HttpRequest 不能并发复用，需要重新创建或自管理池）。
- 拦截能力：注入 Cookie 头（`remix_userid={uid}; remix_userkey={key}`）；超时（默认连接 10s/读取 30s）；统一 JSON 解析；统一异常映射（网络/超时/HTTP 4xx/5xx/Cloudflare 拦截）。
- Cloudflare 检测：判断响应体含 `"Just a moment..."` 或 `cf-mitigated`，抛出 `CfBlockedError`，UI 触发"换线路"对话框。
- 重试策略：5xx + 网络错误重试 1 次；其他不重试。

```ts
export class HttpClient {
  private domain: string = 'pkuedu.online';
  private cookies: string = '';

  setDomain(d: string): void { this.domain = d; }
  setAuth(uid: string, key: string): void {
    this.cookies = `remix_userid=${uid}; remix_userkey=${key}`;
  }

  async get<T>(path: string, query?: Record<string, string|number|undefined>): Promise<T> {…}
  async postForm<T>(path: string, form: Record<string, string>): Promise<T> {…}
  async download(url: string, savePath: string, onProgress?: (cur:number, total:number)=>void, signal?: AbortLike): Promise<void> {…}
}
```

### 6.2 业务 API（`api/ZLibraryClient.ets`）

实现第 3.2 节列出的全部方法，输入输出与 Flutter 端 `Map<String, dynamic>` **语义一致**，但 TS 端用强类型 `ApiResponse<Book[]>` / `ApiResponse<User>`。

### 6.3 持久化（`storage/PreferencesStore.ets`）

- 使用 `@ohos.data.preferences` 创建两个实例：`settings`（设置/收藏/历史）、`auth`（凭证）。
- 通过 `PersistentStorage.persistProps([...])` 将下列键钉到 AppStorage 实现"读取-自动持久化"：
  - `domain: string`
  - `themeMode: 'system'|'light'|'dark'`
  - `locale: string`（`zh-Hans`/`en-US`/系统）
  - `userId/userKey/email/name`（仅在登录后写入；登出清除）
  - `downloadPath?: string`
  - `favoriteIds: number[]`
  - `downloadHistory: Record<string, DownloadHistoryItem>`

> 注：HarmonyOS 偏好不支持非常大的对象，下载历史若超过 100 项考虑迁移到 `relationalStore`，初期 KV 即可。

### 6.4 下载子系统（`viewmodel/DownloadVM.ets`）

- 优先使用 `request.agent.create({ action: 'DOWNLOAD' })`：
  - 系统级断点续传 + 通知栏进度 + 应用退后台不中断；
  - 必须用 HTTPS + 完整 URL，需要在 module.json5 声明 `ohos.permission.INTERNET`。
- Fallback：`@ohos.request.downloadFile`（旧 API，简单但能力弱）。
- 保存目录：
  - 默认 → 应用沙箱 `context.filesDir + '/Download/HLib'`；
  - 用户可在设置选择"系统下载文件夹"，调用 `picker.DocumentSaveOptions` 让系统选择目标 URI。
- 进度回调更新 `@Trace progress`，UI 实时刷新。
- 完成后将 `bookId → {title, author, cover, ext, filePath, time}` 写入 `downloadHistory`。

### 6.5 在线阅读（`pages/ReaderPage.ets`）

- 使用 ArkUI `Web` 组件加载重写后的 URL（见 3.4 节）。
- 注入 Cookie：在 `Web.onControllerAttached` 中通过 `webview.WebCookieManager.configCookieSync(url, cookieStr)`。
- 关闭硬件加速以外的特性时，注意鸿蒙端 Web 默认开启 JS 与 DomStorage。
- 顶部栏带"刷新 / 复制链接 / 在浏览器打开"。

### 6.6 线路与测速（`viewmodel/SpeedTestVM.ets`）

- 复刻 Flutter 端 `SpeedTestNotifier`：并发 8、超时 8s、对每个域 `GET /eapi/info/languages`，根据 `success:1` 或 2xx 判定可用，记录耗时。
- 排序：可用按耗时升序，失败置底。
- UI 在"切换线路"对话框实时刷新延迟。

### 6.7 主题与暗色模式

- `resources/base/element/color.json` 与 `resources/dark/element/color.json` 定义同名 token：
  - `brand_primary`：浅 `#0E7C7B`；
  - `bg_canvas`：浅 `#F7F9FC` / 深 `#121212`；
  - `surface`：浅 `#FFFFFF` / 深 `#1E1E1E`；
  - `text_primary`、`text_secondary`、`accent_orange`、`success_teal`…
- `EntryAbility.onCreate` 中按用户设置切换：
  - `system` → `ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET`；
  - `light` → `COLOR_MODE_LIGHT`；
  - `dark` → `COLOR_MODE_DARK`。

### 6.8 国际化

- v1 仅做中文/英文（默认中文）。
- `resources/base/element/string.json` 默认中文，`resources/en_US/element/string.json` 英文。
- 支持运行时切换：写入 AppStorage 后调用 `i18n.System.setAppPreferredLanguage(...)` 并 `router.clear()` 重建当前页。

### 6.9 权限清单（`module.json5` 增项）

```jsonc
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.GET_NETWORK_INFO" },
  // 仅当用户选择保存到公共下载目录时按需申请：
  { "name": "ohos.permission.READ_MEDIA",  "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" } },
  { "name": "ohos.permission.WRITE_MEDIA", "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" } }
]
```

> 鸿蒙沙箱目录读写**无需**任何权限；只有用户选择"公共下载文件夹"时才需要媒体权限。MVP 默认沙箱。

---

## 7. UI 复刻清单（页面级）

> 设计语言：保留 olib 的"圆角胶囊 + 主品牌色 Dark Teal"，但栅格、字号、组件高度对齐 HarmonyOS 设计规范。

### 7.1 SplashPage

- 渐变背景（teal）+ 中心脉冲圆 + 旋转弧线 + Logo + `Olib` → 改名 `HLib`/`鸿蒙书馆`。
- 状态文字：检测网络 → 加载中。
- 完成后 `replaceUrl` 至登录或主页。

### 7.2 LoginPage

- 顶部 AppBar 透明，右侧 `DomainSelector(compact)` + 多账号入口。
- 中部白卡：邮箱 / 密码 / 登录按钮 + 切换"使用 Token 登录"折叠区。
- Cloudflare 拦截 → 弹"切换线路"对话框（复用 DomainSelectionDialog）。
- 注：注册流程禁用（与原项目一致）。

### 7.3 MainPage（Tabs）

- 四个底栏：Home / Search / Favorites / Downloads。
- 用 `Tabs` + `TabContent`，`barPosition: BarPosition.End`。

### 7.4 HomePage

- 顶部问候语 + 设置按钮。
- 大搜索胶囊（点击跳搜索页）。
- 推荐网格（`GridRow` + `BookCard`），最多 20 项；下拉刷新。

### 7.5 SearchPage

- 顶部输入框 + 过滤按钮（语言 / 排序 / 格式）。
- 结果区 Grid/List 切换、分页加载（滑到底自动加载）。
- 空态、首次态、无结果态。

### 7.6 BookDetailPage

- 顶部 SliverHeader 等价：`Stack` 实现高斯模糊封面 + 渐变 + 3D 封面（`shadow`）。
- 中部白卡：标题 / 作者 / 元数据胶囊 / 描述 / 相似书籍入口。
- 底部固定按钮：在线阅读 + 下载（下载时显示进度 %）。
- 收藏心形按钮在右上。

### 7.7 SimilarBooksPage / FavoritesPage / DownloadsPage / HistoryPage

- 三种列表通用：信息条（数量 + Grid/List 切换）+ 列表 + 空态。
- DownloadsPage 用 `Tabs` 区分进行中 / 已完成。

### 7.8 ReaderPage

- 顶部 AppBar（标题 + 刷新）。
- 主体 `Web` 组件全屏。
- 加载进度细线（`Progress` 组件 height=2）。

### 7.9 SettingsPage

分组：账户卡（头像/姓名/邮箱/今日剩余下载次数）→ 库（下载历史）→ 下载（目录）→ 网络（线路 + 测速）→ 外观（主题/语言）→ 关于（版本/开源/反馈）→ 退出登录。

---

## 8. 复刻"映射表"——快速对照速查

| Flutter 元素 | 鸿蒙等价 |
|---|---|
| `Scaffold` + `AppBar` + `body` | `Column` + 自定义 `GradientAppBar` 组件 + 内容；或 `Navigation` 内置标题栏 |
| `Scaffold.bottomNavigationBar` | `Tabs` `barPosition: End` + `TabBar` |
| `ListView.builder` | `List` + `ListItem` + `LazyForEach` + `IDataSource` |
| `GridView.builder(maxCrossAxisExtent)` | `Grid` + `GridItem` + 列宽计算（或 `WaterFlow` 瀑布流） |
| `CachedNetworkImage` | `Image($r('app.media.placeholder')).alt(...)` + 自实现 LRU；或三方 `@ohos/imageknife` |
| `LinearProgressIndicator` | `Progress({value, total, type: ProgressType.Linear})` |
| `CircularProgressIndicator` | `LoadingProgress()` |
| `TextField` | `TextInput`/`Search` |
| `Dropdown(items)` | `Select` 或 `Menu` |
| `Chip(selected)` | 自定义 `Row` 胶囊 + 状态切换（鸿蒙无原生 Chip） |
| `Hero` 转场 | `sharedTransition` 修饰符 |
| `BackdropFilter(blur)` | `backgroundBlurStyle(BlurStyle.Thick)` |
| `RefreshIndicator` | `Refresh` 容器 |
| `SnackBar` | `promptAction.showToast` 或自实现 Banner |
| `AwesomeDialog` | `AlertDialog`/`CustomDialog` |
| `Riverpod` family/futureProvider | `@ObservedV2` ViewModel + `@Trace` |
| `Hive box.put/get` | `preferences.put/get` |
| `path_provider` | `context.filesDir` / `context.cacheDir` |

---

## 9. 风险评估与可行性

### 9.1 高风险项

1. **Z-Library 镜像不稳定**：原项目维护 ~57 个域名，鸿蒙端必须照搬完整列表 + 测速 + Cloudflare 检测，否则用户体验崩盘。**应对**：将 `domains.ets` 列表常量化、支持运行时增删，遇 Cloudflare 自动提示换线。
2. **HTTP Cookie 持久化**：鸿蒙 `http.HttpRequest` 不像 Dio 自带 cookie jar，需自行从响应头 `set-cookie` 解析、合并、注入。**应对**：`HttpClient` 内置 cookie 管理；阅读器 WebView 通过 `WebCookieManager` 注入同样的 cookie。
3. **Web 组件能力差异**：HarmonyOS `Web` 基于 ArkWeb（华为自研），与 Chromium 行为有微差，部分 z-library 阅读器脚本可能兼容性差。**应对**：必要时设置自定义 UA 模拟桌面/Mobile Chrome；提供"在浏览器打开"出口。
4. **下载 URL 鉴权**：`/dl/{id}/{hash}` 需要登录 cookie，且服务端有时返回 302。**应对**：使用 `request.agent`，设 `headers.cookie`，允许 `redirect: true`。
5. **大文件 IO 性能**：电子书 PDF 可达数十 MB，`fs.write` 频繁触发回调会阻塞 UI。**应对**：用 `request.agent`（系统侧线程）+ 内存中累计字节数节流上报进度。

### 9.2 中风险项

- **暗黑主题双套色**：需要逐组件 token 化，工作量较大但模式固定。
- **国际化**：v1 双语即可，预留 `resources/{locale}/element/string.json` 扩展点。
- **平板/折叠屏适配**：`Tabs` + `GridRow` + `BreakpointSystem` 一次到位。

### 9.3 低风险项

- 收藏 / 下载历史 / 设置项：纯 KV 存储 + 列表 UI，无技术挑战。
- 启动屏动画：ArkUI `animateTo` + `@Watch` 直接还原。

### 9.4 不可行 / 暂缓

- **AI 智阅锦囊**：依赖原作者私有后端，公开仓库无该后端代码与协议。
- **WeChat QR 登录**：依赖私有 wxauth 服务。
- **Unity Ads**：商店审核风险高 + 设计目标无广告。

### 9.5 总体可行性结论

**可行**。所有 MVP 功能都能在 HarmonyOS Next API 12+ 找到对等实现，无需 Native（C++）扩展。预估工作量：

| 阶段 | 工作量 | 备注 |
|---|---|---|
| P0 基建（HttpClient / Stores / 主题 / 路由骨架） | 1.5 天 | |
| P1 鉴权（Splash → Login → Main） | 1 天 | |
| P2 浏览（Home / Search / Detail / Similar） | 2.5 天 | |
| P3 下载 + 阅读 + 收藏 | 2 天 | |
| P4 设置 + 线路 + 国际化 + 暗黑 | 1.5 天 | |
| P5 优化 + 测试 + 发布配置 | 1 天 | |

合计 **≈ 10 个工作日**（单人，AI 辅助编码）。

---

## 10. 验收标准（Definition of Done）

1. 在中国大陆典型网络环境，可在 30s 内完成"启动 → 测速 → 登录 → 看到推荐书目"。
2. 切换线路、登录、搜索、详情、收藏、下载、阅读、设置 8 大流程全部可走通。
3. 中英两语在所有页面无硬编码字符串泄漏。
4. 暗黑模式下所有页面无穿透白底/视觉断层。
5. 退出应用后再启动，凭证、域名、主题、收藏、下载历史均能恢复。
6. 在折叠屏展开/平板（横屏 ≥ 600dp）布局自动切换为双栏（左列表 + 右详情）。
7. 静态扫描（`hvigor` + `code-linter`）零阻塞错误；首次冷启动 < 1.2s（中端机）。

---

## 11. 后续规划（v2+）

- 收藏 QR 分享 / 扫码导入（鸿蒙 ScanKit）。
- 阅读历史本地全文索引（`relationalStore`）。
- 推荐瀑布流接入"近期阅读"行为权重。
- 扩展更多语言、引入字体选择。
- 后台静默更新书目元数据缓存。

---

> 备注：本设计文档不直接落地代码。具体实施步骤见 `docs/IMPLEMENTATION_PLAN.md`。
