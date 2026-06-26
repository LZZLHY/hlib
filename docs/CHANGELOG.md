# 海阅 HLib · 开发更新日志（CHANGELOG）

> **维护约定**（与 [`AppScope/app.json5`](../AppScope/app.json5) 同数轴）：
> - **versionCode 单调递增**，每个有意义的提交 +1；它是「检查更新」比对的唯一依据。
> - 每次发版把 **最新 versionCode / versionName** 同步到三处：`app.json5`、本文件、[`docs/update.json`](update.json)。
> - 表格按 **versionCode 倒序**（最新在最上）。
> - 描述以类型标签开头：`[新增] / [修复] / [优化] / [重构] / [文档] / [安全] / [构建]`。
> - 「涉及文件 / commit」列给出改动文件的相对链接，必要时附 commit 短哈希。
>
> App 内「设置 → 关于 → 检查更新」拉取 `docs/update.json`，与本地 versionCode 比对，有新版即提示并打开 Release 页。

---

## 1.0.1 （2026-06-26，重构 + 安全加固 + 检查更新）

| versionCode | 时间 | 描述 | 涉及文件 / commit | 作者 |
|---|---|---|---|---|
| 1000004 | 2026-06-26 | [新增] **检查更新功能**：仓库维护 `docs/update.json`（versionCode/versionName/releaseUrl/notes），App 经「直连 raw + 代理镜像 + GitHub Pages 兜底」多候选拉取并按 versionCode 比对，有新版弹窗 + 打开 Release 页；接入「设置 → 关于 → 检查更新」。[文档] 引入本 CHANGELOG（AMCL 格式）。[文档] README 移除「多设备 / 无广告」徽章；安装说明改为「仅提供未签名 HAP，需侧载（自签名 / hdc）」。app.json5 versionCode 1000000→1000004、versionName 1.0.0→1.0.1。 | [UpdateChecker.ets](../entry/src/main/ets/viewmodel/UpdateChecker.ets) · [update.json](update.json) · [CHANGELOG.md](CHANGELOG.md) · [SettingsPage.ets](../entry/src/main/ets/pages/SettingsPage.ets) · [README.md](../README.md) · [README.en.md](../README.en.md) · [app.json5](../AppScope/app.json5) | LZZLHY |
| 1000003 | 2026-06-26 | [文档] **README 重构**：居中 Logo（docs/logo.svg，从 app 图标派生，raw 链接渲染）+ 多组徽章（HarmonyOS/ArkTS/ArkUI/License/Version/Stars 等）+ 语言切换；新增英文版 `README.en.md`；同步「项目结构 / 架构」反映本次拆分模块。 | [README.md](../README.md) · [README.en.md](../README.en.md) · [logo.svg](logo.svg) · `500a5a3` | LZZLHY |
| 1000002 | 2026-06-26 | [安全] **清除公开仓库泄漏 + 历史重写**：`build-profile.json5` 的 signingConfigs 置空（移除证书路径与密码，本地签名改 skip-worktree）；删除逆向转储 `tmp/olib-rev/`；用 `git filter-branch` 重写全部历史并 force-push，备份 bundle 留存。[安全] 新增 `Redact` 日志脱敏（URL / Cookie / Header），ReaderPage / DownloadVM / HttpClient 接入，防 remix_userkey 经 hilog 泄漏。`.deveco/opencode.json` 的 API key 改环境变量占位。 | [build-profile.json5](../build-profile.json5) · [Redact.ets](../entry/src/main/ets/utils/Redact.ets) · `d18aa7a` | LZZLHY |
| 1000001 | 2026-06-26 | [重构] **拆分上帝类**：`DownloadVM` 析出 `download/`（FileTypes / FileValidator / DownloadPaths / DownloadUrlResolver / DownloadRepository），只留流式引擎 + 镜像重试；`HttpClient` 析出 `CookieJar` / `CloudflareDetector`，并以 `DomainFailover` 接口注入解耦 AppStorage（`AppStorageDomainFailover` 适配器）。[优化] 新增 `Format` 工具消除 formatSize/formatDate 重复；`AppRouter.pushBookDetail` 收敛 5 处重复构造；移除误导性的假 pause/resume；删除死文件 Index.ets。[新增] 纯函数单测（QrLoginParser / Layout / Format / Redact）。 | [DownloadVM.ets](../entry/src/main/ets/viewmodel/DownloadVM.ets) · [HttpClient.ets](../entry/src/main/ets/api/HttpClient.ets) · [DomainFailover.ets](../entry/src/main/ets/api/DomainFailover.ets) · `d18aa7a` | LZZLHY |
