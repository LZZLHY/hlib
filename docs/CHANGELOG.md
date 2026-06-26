# 海阅 HLib · 开发更新日志（CHANGELOG）

本文件是「开发详版」更新日志，逐 versionCode 记录每次有意义的改动；面向用户的精简发布说明放在 GitHub Release 正文。

## 用法（怎么用 / 怎么维护）

1. **versionCode 是唯一比对依据**，与 [`AppScope/app.json5`](../AppScope/app.json5) 的 `versionCode` 同数轴、单调递增（每个有意义的提交 +1）。`versionName` 是给人看的语义版本（如 `1.0.1`），可多个 versionCode 共用。
2. **每次发版必须三处同步**（缺一会导致「检查更新」误判）：
   - [`AppScope/app.json5`](../AppScope/app.json5) → `versionCode` / `versionName`
   - [`docs/update.json`](update.json) → `versionCode` / `versionName` / `releaseUrl` / `notes`
   - 本文件 → 在对应版本段**表格顶部新增一行**
3. **App 端如何消费**：`viewmodel/UpdateChecker.ets` 启动时静默拉取 `docs/update.json`（直连 raw → 代理镜像 → GitHub Pages 兜底），与本地 `versionCode` 比对：
   - 远程 > 本地 → 标记有新版（首页齿轮 / 设置「检查更新」显示红点），点开弹窗可跳转 Release 页；
   - 自动检查 **24h 节流**，失败不写时间戳（下次启动重试）；手动「设置 → 关于 → 检查更新」忽略节流强制检查。
4. **新增一行的写法**：`| versionCode | YYYY-MM-DD | [类型] 一句话主旨 + 关键细节 | 文件链接 · \`commit\` | 作者 |`。

## 注意事项

- **表格按 versionCode 倒序**（最新在最上）；不要回填/改写历史行，历史只追加。
- **类型标签**统一用：`[新增] / [修复] / [优化] / [重构] / [文档] / [安全] / [构建]`，置于描述开头。
- **「涉及文件 / commit」列**给改动文件的相对链接（本文件在 `docs/`，仓库根文件用 `../` 前缀），可附 commit 短哈希。
- **描述需自包含**：写清「为什么改 / 改了什么 / 影响范围」，便于日后回溯（参考既有行的颗粒度）。
- `update.json` 的 `notes` 是给用户看的简短说明；详细技术过程写在本文件。
- 发布产物为**未签名 HAP**，`releaseUrl` 指向 Releases 页，用户需侧载安装（见 README）。

---

## 1.0.1 （2026-06-26，重构 + 安全加固 + 检查更新）

| versionCode | 时间 | 描述 | 涉及文件 / commit | 作者 |
|---|---|---|---|---|
| 1000007 | 2026-06-26 | [修复] **平板侧栏模式不再叠加底部悬浮栏**：`MainPage` 析出 `useSideNav()` 与共用 `@Builder tabPanels()`；侧栏 / 自动（≥lg 触发侧栏）模式下 `HdsTabs` 改 `.barOverlap(false).barHeight(0)` 隐藏底栏，仅底栏模式保留沉浸光感 `barFloatingStyle`，消除 SideBar 与悬浮底栏同时出现的问题。[新增] **下载页按目录类型切换头部操作**：公共目录（沙箱外）显示「打开下载文件夹」；沙箱内显示「导出文件」——经 `PublicDownloadDir`（校验 syscap + 申请 `READ_WRITE_DOWNLOAD_DIRECTORY` 权限）把已完成文件 `copyFileSync` 到公共下载目录的应用专属子目录（平板可用）。 | [MainPage.ets](../entry/src/main/ets/pages/MainPage.ets) · [DownloadsTab.ets](../entry/src/main/ets/tabs/DownloadsTab.ets) · [PublicDownloadDir.ets](../entry/src/main/ets/utils/PublicDownloadDir.ets) | LZZLHY |
| 1000006 | 2026-06-26 | [修复/重构] **下载目录改为「沙箱 / 公共下载目录」二选一**：移除「缓存目录」选项；公共目录用 `Environment.getUserDownloadDir()`（`@kit.CoreFileKit`）解析公共 Download 路径，并写入其下**以包名命名的应用专属子目录** `Download/<bundleName>/`（系统据此归属到本应用、用户在文件管理可见）。权限用 user_grant 的 `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`（切换时 `requestPermissionsFromUser` 弹窗授权），未授权 / 不支持回退沙箱。**注**：未采用 `FILE_ACCESS_MANAGER` + FileAccess 框架——该权限为系统级，仅授予系统文件管理类应用，第三方应用无法获批。新增 `PublicDownloadDir`，删除 `PublicDirAccess`；`DownloadPaths` / `DownloadsTab` 同步适配。 | [PublicDownloadDir.ets](../entry/src/main/ets/utils/PublicDownloadDir.ets) · [DownloadPaths.ets](../entry/src/main/ets/viewmodel/download/DownloadPaths.ets) · [SettingsPage.ets](../entry/src/main/ets/pages/SettingsPage.ets) · [module.json5](../entry/src/main/module.json5) | LZZLHY |
| 1000005 | 2026-06-26 | [新增] **启动静默自动检查更新 + 红点 + 24h 节流**：`UpdateChecker.autoCheck` 在 SplashPage 引导阶段触发——先把上次缓存的「有新版」状态回灌 AppStorage（即时红点、无需联网），距上次检查不足 24h 直接返回，否则联网刷新并写回缓存；首页右上齿轮与「设置 → 关于 → 检查更新」通过 `@StorageProp(UPDATE_AVAILABLE)` 显示红点。[文档] 完善 CHANGELOG 用法与注意事项。 | [UpdateChecker.ets](../entry/src/main/ets/viewmodel/UpdateChecker.ets) · [SplashPage.ets](../entry/src/main/ets/pages/SplashPage.ets) · [HomeTab.ets](../entry/src/main/ets/tabs/HomeTab.ets) · [SettingsPage.ets](../entry/src/main/ets/pages/SettingsPage.ets) | LZZLHY |
| 1000004 | 2026-06-26 | [新增] **检查更新功能**：仓库维护 `docs/update.json`（versionCode/versionName/releaseUrl/notes），App 经「直连 raw + 代理镜像 + GitHub Pages 兜底」多候选拉取并按 versionCode 比对，有新版弹窗 + 打开 Release 页；接入「设置 → 关于 → 检查更新」。[文档] 引入本 CHANGELOG（AMCL 格式）。[文档] README 移除「多设备 / 无广告」徽章；安装说明改为「仅提供未签名 HAP，需侧载（自签名 / hdc）」。 | [UpdateChecker.ets](../entry/src/main/ets/viewmodel/UpdateChecker.ets) · [update.json](update.json) · [CHANGELOG.md](CHANGELOG.md) · [README.md](../README.md) | LZZLHY |
| 1000003 | 2026-06-26 | [文档] **README 重构**：居中 Logo（docs/logo.svg，从 app 图标派生，raw 链接渲染）+ 多组徽章（HarmonyOS/ArkTS/ArkUI/License/Version/Stars 等）+ 语言切换；新增英文版 `README.en.md`；同步「项目结构 / 架构」反映本次拆分模块。 | [README.md](../README.md) · [README.en.md](../README.en.md) · [logo.svg](logo.svg) · `500a5a3` | LZZLHY |
| 1000002 | 2026-06-26 | [安全] **清除公开仓库泄漏 + 历史重写**：`build-profile.json5` 的 signingConfigs 置空（移除证书路径与密码，本地签名改 skip-worktree）；删除逆向转储 `tmp/olib-rev/`；用 `git filter-branch` 重写全部历史并 force-push，备份 bundle 留存。[安全] 新增 `Redact` 日志脱敏（URL / Cookie / Header），ReaderPage / DownloadVM / HttpClient 接入，防 remix_userkey 经 hilog 泄漏。`.deveco/opencode.json` 的 API key 改环境变量占位。 | [build-profile.json5](../build-profile.json5) · [Redact.ets](../entry/src/main/ets/utils/Redact.ets) · `d18aa7a` | LZZLHY |
| 1000001 | 2026-06-26 | [重构] **拆分上帝类**：`DownloadVM` 析出 `download/`（FileTypes / FileValidator / DownloadPaths / DownloadUrlResolver / DownloadRepository），只留流式引擎 + 镜像重试；`HttpClient` 析出 `CookieJar` / `CloudflareDetector`，并以 `DomainFailover` 接口注入解耦 AppStorage（`AppStorageDomainFailover` 适配器）。[优化] 新增 `Format` 工具消除 formatSize/formatDate 重复；`AppRouter.pushBookDetail` 收敛 5 处重复构造；移除误导性的假 pause/resume；删除死文件 Index.ets。[新增] 纯函数单测（QrLoginParser / Layout / Format / Redact）。 | [DownloadVM.ets](../entry/src/main/ets/viewmodel/DownloadVM.ets) · [HttpClient.ets](../entry/src/main/ets/api/HttpClient.ets) · [DomainFailover.ets](../entry/src/main/ets/api/DomainFailover.ets) · `d18aa7a` | LZZLHY |
