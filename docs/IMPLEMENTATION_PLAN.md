# HLib · 复刻实施计划（Step-by-Step）

> 配合 `TECHNICAL_DESIGN.md` 阅读。本文档把"做什么"拆解为可被一次提交完成的最小步骤。
> 阶段编号 P0..P5；每个 Step 标注"验收点"，做完即可勾选。

---

## P0 · 基础设施

### Step 0.1 修订 app 元数据
- 修改 `AppScope/app.json5`：`bundleName` → `com.hlib.app`（保留），`label` 引用资源 `$string:app_name`，`vendor` 改为本人/团队。
- 在 `AppScope/resources/base/element/string.json` 写入 `app_name = "HLib · 鸿蒙书馆"`。
- **验收**：`hvigor build` 通过；启动后桌面图标显示新名字。

### Step 0.2 引入依赖
- `entry/oh-package.json5` 增加：
  - 无需第三方网络/存储库（全用系统 Kit）。
  - 可选：`@ohos/imageknife`（封面图片缓存，若不引则用 `Image` + 自实现 LRU）。
- **验收**：`ohpm install` 成功，`oh-package-lock.json5` 更新。

### Step 0.3 主题 token
- 新增 `entry/src/main/resources/base/element/color.json` 与 `entry/src/main/resources/dark/element/color.json`，定义品牌色 token（`brand_primary`、`bg_canvas`、`surface`、`text_primary`、`text_secondary`、`accent_orange`、`success_teal`、`error`、`shadow_card`）。
- 新增 `entry/src/main/ets/theme/AppColors.ets` 与 `theme/AppTextStyles.ets` 暴露常量便于 IDE 跳转。
- **验收**：在 `Index.ets` 临时使用 `$r('app.color.brand_primary')` 渲染色块，明暗模式下颜色不同。

### Step 0.4 i18n 资源
- `entry/src/main/resources/base/element/string.json`（中文）+ `entry/src/main/resources/en_US/element/string.json`（英文）：先填入 30~50 个 key（参考 olib `lib/l10n/translations/zh.dart` & `en.dart`）。
- 工具类 `utils/I18n.ets` 提供 `t(key)` 包装（实际只是 `$r('app.string.xxx')`，但便于动态字符串 fallback）。
- **验收**：切换系统语言，`Index.ets` 标题随之变化。

### Step 0.5 持久化基座
- `storage/PreferencesStore.ets`：单例，封装 `data_preferences.getPreferences(context, 'settings')` 与 `'auth'`，提供 `getString/putString/getStringArray/putObject` 等。
- `EntryAbility.onCreate` 早期调用 `PreferencesStore.init(this.context)`。
- `PersistentStorage.persistProps([...])` 将 `domain`/`themeMode`/`locale` 钉到 AppStorage。
- **验收**：随便写 `PreferencesStore.putString('test', 'hello')`、重启读出来。

### Step 0.6 HTTP 客户端骨架
- `api/HttpClient.ets`：单例；`setDomain` / `setAuth` / `get<T>(path, query?)` / `postForm<T>` / `download(url, dest, onProgress, signal)`。
- 实现 cookie 解析与自动注入（响应 `set-cookie` 入内存 + 写入 `auth` 偏好）。
- 实现 Cloudflare 检测（响应体含 `Just a moment` 或状态码 403 + `cf-mitigated`）→ 抛 `CfBlockedError`。
- **验收**：调用 `httpClient.get('/eapi/info/languages')` 返回包含 `success:1`。

### Step 0.7 业务 API 封装
- `api/ZLibraryClient.ets`：将第 3.2 节 14 个方法逐个实现；优先实现 `search / getBookInfo / getMostPopular / getUserRecommended / getRecently / login / getProfile`，其余在用到时补全。
- `model/Book.ets`、`model/User.ets`：定义接口 + `fromJson` 工厂。
- **验收**：写一个临时按钮在 `Index.ets` 里点一下，输出 `hilog` 显示 5 本推荐书目标题。

### Step 0.8 路由骨架
- 修改 `entry/src/main/resources/base/profile/main_pages.json` 列出全部页面：`SplashPage`、`LoginPage`、`MainPage`、`SearchPage`、`BookDetailPage`、`SimilarBooksPage`、`ReaderPage`、`SettingsPage`、`HistoryPage`。
- `EntryAbility.onWindowStageCreate` 改为加载 `pages/SplashPage`。
- 创建空壳页面文件（每个 `@Entry @Component struct XxxPage { build() { Text('TODO') } }`）。
- **验收**：手机上能用 `router.pushUrl({ url: 'pages/LoginPage' })` 跳转。

---

## P1 · 鉴权流程

### Step 1.1 SplashPage 动画与启动序列
- 渐变背景 + 中心 Logo + 脉冲外圈 + 旋转弧线（`Canvas` + `animateTo`）。
- `aboutToAppear` 中：`PreferencesStore.init` → `AuthVM.bootstrap` → `SpeedTestVM.runTest()`（不阻塞）。
- 完成后 `replaceUrl` 至 `LoginPage` 或 `MainPage`。
- **验收**：冷启动 1.5s 内看到动画，2~3s 内完成跳转。

### Step 1.2 AuthVM
- `viewmodel/AuthVM.ets`：`@Trace user`、`@Trace loading`、`@Trace error`。
- 方法：`bootstrap()`、`login(email, pwd)`、`loginWithToken(uid, key)`、`refresh()`、`logout()`、`switchAccount(...)`、`removeAccount(uid)`。
- 凭证读写走 `storage/AuthStore.ets`。多账号列表用 JSON 数组保存。
- **验收**：单元测试或手动调用 `login` 成功后 `AppStorage.get('user')` 不为 null。

### Step 1.3 LoginPage UI
- AppBar 透明 + 右侧 `DomainSelector(compact=true)` + 多账号入口图标。
- 中部白卡：邮箱、密码、登录按钮、Token 折叠区（`Stepper` 或 `Show/Hide`）。
- 错误处理：`CfBlockedError` → 弹换线路对话框；其他 → 红色 Banner 显示文案。
- **验收**：用真实 z-library 账号登录成功并跳到主页。

### Step 1.4 DomainSelector + Dialog
- `components/DomainSelector.ets`：胶囊样式 + Line N 标签。
- 对话框列表展示测速结果（`SpeedTestVM.results` 由 `@Consume` 订阅）：可用绿色 / 慢黄色 / 失败红色。
- 底部"重新测速""自定义线路"按钮。
- **验收**：从登录页和设置页都能弹出，点击切换后立即生效。

### Step 1.5 SpeedTestVM
- `viewmodel/SpeedTestVM.ets`：复刻 Flutter 端 `_maxConcurrent=8` 的有界并发；超时 8s。
- 排序逻辑：可用按延迟升序 + 失败置底。
- 可被多次手动触发（重新测速）。
- **验收**：50+ 域名能在 15s 内完成测速。

---

## P2 · 浏览模块

### Step 2.1 MainPage Tabs 容器
- `Tabs` + `TabContent`，4 个底栏：`Home/Search/Favorites/Downloads`。
- 每个 TabContent 直接嵌入对应组件（`HomeTab`、`SearchTab`、`FavoritesTab`、`DownloadsTab`），保持状态。
- **验收**：底栏切换流畅，滚动位置不丢失。

### Step 2.2 BookCard 组件
- `components/BookCard.ets`：3:2 高宽比，封面 `Image` + 占位图（渐变 + 书本 icon）+ 元数据胶囊。
- 按下缩放动效（`scale: 0.96` 200ms）。
- **验收**：在 Home/Search/Favorites/Similar 四处复用，样式一致。

### Step 2.3 BookListTile 组件
- 简洁列表项：左侧 40x40 图标占位 + 标题 + 作者 + 格式徽章 + 大小 + 年份。
- **验收**：搜索页切换列表视图正常。

### Step 2.4 HomeTab 内容
- 顶部问候语 + 设置入口（跳 `SettingsPage`）。
- 大搜索胶囊（点击切换到搜索 Tab 并聚焦）。
- 推荐网格：`GridRow` 自适应 2~4 列；调用 `BooksVM.loadHome()`。
- 下拉刷新（`Refresh` 容器）。
- **验收**：首次加载在 3s 内显示 ≥10 本书。

### Step 2.5 SearchTab + 筛选
- `Search` 输入框 + 提交触发查询；`tune` 按钮切换筛选面板（语言 `Select`、排序 `Select`、格式胶囊 `Row`）。
- 分页：`onScrollEnd` 检测距离底部 < 200vp 时加载下一页。
- 状态：未搜索 / 加载中 / 无结果 / 列表 / 末尾加载中。
- **验收**：连翻 3 页无重复，列表/网格切换不丢分页。

### Step 2.6 BookDetailPage
- 顶部 `Stack`：高斯模糊背景封面 + 渐变 + 中心 3D 书封（`shadow` 多层）+ 收藏图标。
- 中部白卡：标题、作者、`Capsule` 列表（格式/大小/年份/出版社/页数/语言）、描述（折叠）。
- 相似书入口卡片。
- 底部固定：在线阅读 + 下载（依赖 `book.readOnlineAvailable`）。
- **验收**：所有字段无硬编码"暂无"，详情滚动流畅。

### Step 2.7 SimilarBooksPage
- 顶部书名上下文条 + 数量 + 视图切换。
- 调 `client.Similar(bookId, hash)`。
- **验收**：从详情页进入正常显示 6~12 本相似书。

---

## P3 · 收藏 / 下载 / 阅读

### Step 3.1 FavoritesTab
- 调 `client.getUserSaved(100)` + 本地索引合并。
- 长按进入多选模式：批量取消收藏。
- 空态：图标 + "去搜索几本喜欢的书吧"。
- **验收**：详情页点心形 → Tab 立即出现该书。

### Step 3.2 DownloadVM
- `viewmodel/DownloadVM.ets`：管理任务列表（pending/downloading/completed/error）。
- 用 `request.agent.create({ action: 'DOWNLOAD' })`，监听 `progress`、`completed`、`failed` 回调。
- 完成后写入 `downloadHistory`。
- 启动时从 `downloadHistory` 重建已完成任务列表（校验文件是否存在）。
- **验收**：100MB 测试文件下载完成，可被打开；中途取消能删除半成品。

### Step 3.3 BookDetailPage 接入下载
- 检测 `downloadHistory` 中是否已有同 ID → 弹"打开 / 重新下载"对话框。
- 进度按钮显示 `XX%`；完成显示"打开文件"。
- **验收**：流程顺畅，不会重复创建任务。

### Step 3.4 DownloadsTab
- 两 Tab：进行中 / 已完成。
- 列表项支持取消（进行中）/ 打开 / 详情 / 分享 / 删除（已完成）。
- 顶部按钮"打开下载文件夹"通过 Want 跳系统文件管理（若失败提示路径）。
- **验收**：删除后从历史和文件系统都清掉。

### Step 3.5 ReaderPage
- 顶部 AppBar（标题截断 + 刷新）。
- `Web` 组件加载重写后的 URL（按 3.4 节算法）。
- 在 `onControllerAttached` 中通过 `WebCookieManager.configCookieSync(url, cookies)` 注入登录态。
- 进度条用 `onProgressChange` 驱动，加载完成隐藏。
- **验收**：能加载阅读器并保持登录态翻页。

---

## P4 · 设置与体验完善

### Step 4.1 SettingsPage
- 用户卡（头像首字母 + 姓名 + 邮箱 + 今日剩余下载次数）。
- 库 → 下载历史（跳 HistoryPage）。
- 下载 → 下载目录（默认沙箱 / 选择系统下载文件夹）。
- 网络 → 当前线路 + 切换 + 测速。
- 外观 → 主题（系统/浅/深 三选一）+ 语言（中/英 + 跟随系统）。
- 关于 → 版本 + 开源声明 + 反馈邮箱。
- 退出登录（清 auth 偏好 + 跳登录页）。
- **验收**：每项设置改完即时生效；重启后保留。

### Step 4.2 HistoryPage
- 列出 `downloadHistory` 全部条目（按时间倒序）+ 文件存在性校验。
- 项点击 → 打开文件；右滑 → 删除。
- **验收**：与 DownloadsTab 已完成列表一致，但展现时间维度。

### Step 4.3 暗黑模式联动
- 检查每个页面，确保色值都用 `$r('app.color.xxx')`，无硬编码 `0xFFxxxxxx`（除非品牌色）。
- 在 SettingsPage 切换主题时调 `app.context.getApplicationContext().setColorMode(...)`。
- **验收**：手动切换 + 跟随系统 三种模式均正常。

### Step 4.4 双语校对
- 用 `node` 脚本扫描所有 `Text(...)` 字面量，确认全部走 `$r('app.string.xxx')`。
- 缺失的 key 一并补齐到中英资源文件。
- **验收**：英文模式下所有页面无中文残留（除版权说明等明确双语区）。

### Step 4.5 平板/折叠屏适配
- `BreakpointSystem`：`sm/md/lg` 三档。
- HomeTab 在 `lg` 时改为 4 列网格；BookDetailPage 在 `lg` 时启用左右分栏（左侧封面 + 右侧文本）。
- **验收**：DevEco 模拟器 2in1 + 折叠屏展开两种形态布局合理。

---

## P5 · 测试 / 优化 / 发布

### Step 5.1 性能优化
- BookCard 启用 `LazyForEach` 与 `cachedCount` 调优。
- Image 加载启用磁盘缓存（`@ohos/imageknife` 或自实现 `cacheKey`）。
- HTTP 复用 `HttpRequest` 实例池（最多 4 个）。
- **验收**：搜索结果连续滚动 200 项，FPS ≥ 55。

### Step 5.2 错误处理矩阵
- 网络不可达 / 4xx / 5xx / Cloudflare / 鉴权失效 / 下载失败 / 文件被删 七种情境，全部弹友好提示并提供恢复路径（重试/换线路/重新登录）。
- **验收**：手动断网/切错域名/删本地文件，UI 不崩。

### Step 5.3 单元 / UI 测试
- `entry/src/test`：HttpClient 的 cookie 解析与 Cloudflare 检测。
- `entry/src/ohosTest`：登录页输入校验、SearchPage 列表渲染。
- **验收**：`hvigor test` 通过率 100%。

### Step 5.4 静态扫描
- `code-linter.json5` 启用全部默认规则；修复全部告警。
- `obfuscation-rules.txt` 保留必要的反射与 JSON 解析符号。
- **验收**：构建零阻塞警告。

### Step 5.5 签名与发布
- 在 `build-profile.json5` 配置 `signingConfigs`（开发者后台拿到 cert/p12/profile）。
- Release 构建 `.app` 包；用 DevEco 直接安装到真机。
- **验收**：真机能正常使用全功能；冷启动 < 1.2s（中端机）。

---

## 总进度看板

```
P0 ░░░░░░░░░░  基建：8 步
P1 ░░░░░░░░░░  鉴权：5 步
P2 ░░░░░░░░░░  浏览：7 步
P3 ░░░░░░░░░░  下载/阅读：5 步
P4 ░░░░░░░░░░  设置/体验：5 步
P5 ░░░░░░░░░░  发布：5 步
```

每完成一个 Step 即可在 PR 中勾选；建议每个 Phase 单独一个 PR，便于回滚。

---

## 立即可启动的下一步

> 待用户确认本设计后，我将按 **P0.1 → P0.8** 顺序开始落地代码（约 10~12 个连续提交）。
> 任何阶段都可以停下来评审 / 调整方向。

- [ ] 用户确认 → 开始 P0
- [ ] 是否需要我先生成 50+ 镜像域名常量文件？（建议是）
- [ ] 是否引入 `@ohos/imageknife` 还是自实现轻量缓存？（建议自实现，零依赖）
- [ ] App 中文名定为 **"鸿蒙书馆"** 还是 **"HLib"**？默认双语。
