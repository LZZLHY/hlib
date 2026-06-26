<div align="center">

<img src="https://raw.githubusercontent.com/LZZLHY/hlib/master/docs/logo.svg" width="120" alt="海阅 HLib" />

# 海阅 HLib

**HarmonyOS 第三方电子图书阅读客户端**

基于 Z-Library 公开镜像 · 搜索 · 收藏 · 在线阅读 · 下载 · 多镜像线路管理

<br/>

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-6.1.0%20(API%2024)-0E7C7B?style=flat-square&logo=harmonyos&logoColor=white)](#)
[![ArkTS](https://img.shields.io/badge/Language-ArkTS-2EC4B6?style=flat-square)](#)
[![ArkUI](https://img.shields.io/badge/UI-ArkUI-26A69A?style=flat-square)](#)

[![License](https://img.shields.io/badge/License-MIT-3F7DE0?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.1-FF9F1C?style=flat-square)](https://github.com/LZZLHY/hlib/releases)
[![Stars](https://img.shields.io/github/stars/LZZLHY/hlib?style=flat-square&color=FFBF69)](https://github.com/LZZLHY/hlib/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/LZZLHY/hlib?style=flat-square&color=2EC4B6)](https://github.com/LZZLHY/hlib/commits)

**简体中文** · [English](README.en.md)

</div>

---

## 简介

海阅（HLib）是一款面向 HarmonyOS 的第三方电子书客户端。它通过用户选择的 Z-Library 公共镜像接口提供图书检索、详情查看、收藏、在线阅读与下载能力。

本项目本身不存储、不缓存、不分发任何书籍内容，也不与 Z-Library 官方存在关联。用户应自行确认访问、浏览、下载和阅读行为符合所在地区的法律法规。

## 核心功能

- **图书浏览**：首页推荐 / 热门 / 近期上传，支持内容语言偏好。
- **高级搜索**：关键词 + 语言 / 排序 / 格式 / 出版年份筛选，分页浏览。
- **书籍详情**：封面、作者、出版信息、简介、相似书籍推荐，收藏 / 在线阅读 / 下载。
- **在线阅读**：ArkWeb 加载阅读页，自动注入登录 Cookie，进度记忆、字体切换、全屏。
- **下载管理**：流式下载、进度与速度展示、历史记录，打开 / 分享 / 失败自动换镜像。
- **收藏与历史**：本地优先收藏，服务端尽力同步；下载历史与阅读进度本地持久化。
- **多镜像线路**：内置多镜像 + 并发测速 + 自定义域名 + 远程 manifest 同步 + Cloudflare 拦截一键换线。
- **隐私与安全**：HUKS AES‑256‑GCM 加密凭证，数据本地优先，不接入第三方统计 / 广告 / 推送 / 崩溃上报。
- **响应式界面**：适配手机 / 折叠屏 / 平板 / 大屏，小屏底部导航、大屏侧边栏；浅色 / 深色 / 跟随系统；中英双语。

## 安装

> ⚠️ 本项目 **仅提供未签名的 HAP 包**（`entry-default-unsigned.hap`），**不提供应用市场签名包**，需自行 **侧载（sideload）安装**。

前往 [GitHub Releases](https://github.com/LZZLHY/hlib/releases) 下载最新的 `*-unsigned.hap`，任选一种方式安装：

- **方式一 · 自签名安装（推荐）**：用 DevEco Studio 打开本项目，在 *Project Structure > Signing Configs* 配置你自己的调试签名后 Build & Run 安装到设备。
- **方式二 · hdc 侧载**：设备开启「开发者模式 + USB 调试」，执行 `hdc install path\to\entry-default-unsigned.hap`（设备需允许安装调试 / 未签名应用）。

由于未做应用市场签名，系统的「直接点击安装」通常会被拦截，请使用上述侧载方式。

## 构建

### 环境要求

- DevEco Studio，或 HarmonyOS Command Line Tools
- HarmonyOS SDK / ArkTS 工具链（API 24 / 6.1.0）
- ohpm / hvigor 构建环境
- 可用的 HarmonyOS 应用签名配置

### 命令行构建

```bash
ohpm install

# 指向本机 SDK（command-line-tools 内）
set DEVECO_SDK_HOME=D:\Huawei\command-line-tools\sdk   # Windows
hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```

> **签名说明**：仓库中提交的 `build-profile.json5` 的 `signingConfigs` 为空数组，**不含任何证书路径与密码**。
> 本地构建请在 DevEco Studio 的 *File > Project Structure > Signing Configs* 配置签名；
> 为避免本地签名信息被提交，可对该文件执行 `git update-index --skip-worktree build-profile.json5`。

## 项目结构

```text
hlib/
├── AppScope/                     # 应用级配置
├── docs/                         # 项目文档、隐私政策、Logo
└── entry/src/main/
    ├── cpp/                      # NAPI 脚手架（当前未参与业务）
    ├── ets/
    │   ├── api/                  # 网络层
    │   │   ├── HttpClient        #   传输底座：重试 / 漂移 / Cookie / 语言
    │   │   ├── ZLibraryClient    #   /eapi/* 业务接口
    │   │   ├── CookieJar         #   Cookie 容器 + set-cookie 解析（自 HttpClient 拆出）
    │   │   ├── CloudflareDetector#   CF 拦截识别（自 HttpClient 拆出）
    │   │   ├── DomainFailover    #   域名漂移接口 + AppStorageDomainFailover 适配器
    │   │   ├── ApiTypes / Domains / DomainManifest / SearchFilters
    │   ├── components/           # 通用 UI 组件与对话框
    │   ├── entryability/         # EntryAbility 主入口
    │   ├── entrybackupability/   # 备份扩展
    │   ├── model/                # Book / User / DownloadTask / DomainTestResult
    │   ├── pages/                # 页面级路由组件（RootPage 承载 Navigation）
    │   ├── storage/              # PreferencesStore / AuthStore / Favorites / History / ...
    │   ├── tabs/                 # 首页 / 搜索 / 收藏 / 下载 Tab
    │   ├── theme/                # AppColors / AppTextStyles
    │   ├── utils/                # Logger / SecretStore / I18n / Layout / AppRouter
    │   │                         #   Redact(日志脱敏) / Format(格式化) / UrlUtils / DohResolver / ...
    │   └── viewmodel/            # AuthVM / HomeVM / SearchVM / BookDetailVM / FavoritesVM / SpeedTestVM / DownloadVM
    │       └── download/         # DownloadVM 拆分：
    │                             #   FileTypes / FileValidator / DownloadPaths
    │                             #   DownloadUrlResolver / DownloadRepository
    └── resources/                # 字符串、颜色、float、图标、profile
```

## 架构概览

```text
ArkUI Pages / Tabs / Components
        |
        v
ViewModel 层（AuthVM / HomeVM / DownloadVM ...）
        |
        +--> ZLibraryClient ──> HttpClient ──> Z-Library 镜像 /eapi/*
        |                          |
        |                          +── CookieJar / CloudflareDetector / RetryPolicy
        |                          +── DomainFailover（注入，解耦 AppStorage）
        |
        +--> Store 层 ──> AppStorage / PreferencesStore / HUKS SecretStore
```

### 关键模块

- **EntryAbility**：初始化 preferences、HUKS、错误日志、镜像 manifest、主题、语言、登录态、窗口布局，并注入 `AppStorageDomainFailover`。
- **HttpClient**：统一域名 / Cookie / 代理 / 语言 / UA / 重试 / Cloudflare 检测；自动换线逻辑通过 `DomainFailover` 接口注入，传输层不再直接依赖 AppStorage。
- **ZLibraryClient**：封装 `/eapi/*`（登录、搜索、详情、相似、收藏、推荐等）。
- **DownloadVM + download/**：下载链接解析、流式落盘、进度、魔术字节校验、镜像漂移、打开 / 分享；职责拆分为 `DownloadUrlResolver` / `FileValidator` / `DownloadPaths` / `FileTypes` / `DownloadRepository`。
- **AuthStore / SecretStore**：用 HUKS AES‑GCM 加密保存 `remix_userid` / `remix_userkey` 及密码等敏感凭证。
- **Redact**：URL / Cookie / Header 日志脱敏，防止凭证经 hilog 泄漏。

## 隐私说明

海阅尽量减少数据收集与外部依赖：不内置第三方统计 / 广告 SDK；不上传本地收藏、下载历史、阅读进度；登录凭证仅保存在本机并经 HUKS 加密；网络请求直接发往用户选择的镜像站点。完整隐私政策见 [docs/privacy.md](docs/privacy.md)。

## 免责声明

1. 本项目是第三方客户端，与 Z-Library 官方无关联。
2. 本项目不存储、不分发、不审查任何书籍内容。
3. 所有内容均来自用户选择访问的第三方镜像站点。
4. 用户应自行确认使用行为符合所在地区的法律法规。
5. 镜像站点的可达性、内容合法性与安全性由对应站点负责。
6. 本项目以“现状”提供，不对稳定性、适用性或可用性作任何明示或默示担保。

## 许可证

[MIT License](LICENSE)

---

<div align="center">
© 2026 海阅 HLib · Made for HarmonyOS
</div>
