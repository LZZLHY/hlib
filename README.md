# 海阅 HLib

> HarmonyOS 第三方电子图书阅读客户端。  
> 基于 Z-Library 公开镜像 API，专注搜索、收藏、在线阅读、下载与多镜像线路管理。

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-ArkTS-0E7C7B)](#)
[![ArkUI](https://img.shields.io/badge/UI-ArkUI-2EC4B6)](#)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](#许可证)

## 简介

海阅（HLib）是一款面向 HarmonyOS 的第三方电子书客户端。它通过用户选择的 Z-Library 公共镜像接口提供图书检索、详情查看、收藏、在线阅读与下载能力。

本项目本身不存储、不缓存、不分发任何书籍内容，也不与 Z-Library 官方存在关联。用户应自行确认访问、浏览、下载和阅读行为符合所在地区的法律法规。

## 核心功能

- **图书浏览**
  - 首页推荐、热门图书、近期上传。
  - 支持内容语言偏好，优化中文/英文等地区内容展示。

- **高级搜索**
  - 关键词搜索。
  - 支持语言、排序、文件格式、出版年份筛选。
  - 支持分页浏览搜索结果。

- **书籍详情**
  - 展示封面、标题、作者、出版社、年份、语言、页数、格式、大小、简介等信息。
  - 支持相似书籍推荐。
  - 支持收藏、在线阅读、下载。

- **在线阅读**
  - 使用 ArkWeb 加载在线阅读页面。
  - 自动注入登录 Cookie。
  - 支持阅读进度保存与恢复。
  - 支持字体大小切换、全屏阅读、Web 内返回。

- **下载管理**
  - 流式下载电子书文件。
  - 显示下载进度、速度相关状态与历史记录。
  - 支持打开文件、分享文件、打开下载目录。
  - 下载失败时可自动尝试备用镜像。

- **收藏与历史**
  - 本地优先收藏，服务端尽力同步。
  - 下载历史本地持久化。
  - 阅读进度本地保存。

- **多镜像线路**
  - 内置多个 Z-Library 镜像域名。
  - 支持并发测速、线路选择、自定义域名。
  - 支持远程镜像 manifest 同步。
  - 支持 Cloudflare 拦截提示与一键切换线路。

- **隐私与安全**
  - 账号凭证使用 HarmonyOS HUKS AES-256-GCM 加密。
  - 数据主要保存在本地 preferences 中。
  - 不接入第三方统计、广告、推送、崩溃上报或埋点 SDK。

- **响应式界面**
  - 适配手机、折叠屏、平板和大屏设备。
  - 小屏使用底部导航，大屏可自动切换侧边栏导航。
  - 支持浅色、深色、跟随系统主题。
  - 支持简体中文和 English。

## 安装

请前往 GitHub Releases 下载最新构建产物：

- `*.app`：HarmonyOS 应用包。
- `*.hap`：Entry 模块安装包，如 Release 中同时提供。

安装方式取决于你的设备、系统版本、签名与调试权限。普通用户建议优先下载 Release 中的 signed app 包。

## 构建

### 环境要求

- DevEco Studio
- HarmonyOS SDK / ArkTS 工具链
- ohpm / hvigor 构建环境
- 可用的 HarmonyOS 应用签名配置

### 本地构建

```bash
ohpm install
```

然后使用 DevEco Studio 打开项目，执行同步与构建：

- Build HAP(s)
- Build APP(s)

签名配置通常依赖本地文件，例如 `build-profile.signing.local.json5`。该类文件包含证书路径和密码，已被 `.gitignore` 排除，**请勿提交到仓库**。

## 项目结构

```text
hlib/
├── AppScope/                 # 应用级配置
├── docs/                     # 项目文档与隐私政策
├── entry/
│   ├── src/main/ets/
│   │   ├── api/              # Z-Library API、HTTP 客户端、镜像管理
│   │   ├── components/       # 通用 UI 组件
│   │   ├── entryability/     # 主 Ability
│   │   ├── entrybackupability/
│   │   ├── model/            # Book、User、DownloadTask 等模型
│   │   ├── pages/            # 页面级组件
│   │   ├── storage/          # 本地持久化封装
│   │   ├── tabs/             # 首页、搜索、收藏、下载 Tab
│   │   ├── theme/            # 主题 token
│   │   └── utils/            # 路由、日志、加密、国际化、URL 工具等
│   └── src/main/resources/   # 字符串、颜色、图标、profile 配置
└── build-profile.json5       # 工程构建配置
```

## 架构概览

```text
ArkUI Pages / Tabs / Components
        |
        v
ViewModel 层
        |
        +--> ZLibraryClient
        |        |
        |        v
        |   HttpClient
        |        |
        |        v
        |   Z-Library 镜像 /eapi/*
        |
        +--> Store 层
                 |
                 v
        AppStorage / PreferencesStore / HUKS SecretStore
```

### 关键模块

- `EntryAbility`
  - 初始化 preferences、HUKS、错误日志、镜像 manifest、主题、语言、登录态与窗口布局。

- `SplashPage`
  - 处理隐私同意、镜像测速、远程 manifest 刷新、登录态恢复和启动跳转。

- `HttpClient`
  - 统一管理域名、Cookie、代理、语言偏好、User-Agent、重试、Cloudflare 检测和自动换线。

- `ZLibraryClient`
  - 封装 `/eapi/*` 业务接口，包括登录、搜索、详情、相似书籍、收藏、推荐等。

- `DownloadVM`
  - 负责下载链接解析、流式落盘、进度更新、文件校验、历史记录、打开与分享。

- `AuthStore` / `SecretStore`
  - 使用 HUKS AES-GCM 加密保存 `remix_userid`、`remix_userkey` 和密码等敏感凭证。

## 隐私说明

海阅尽量减少数据收集和外部依赖：

- 不内置第三方统计 SDK。
- 不内置广告 SDK。
- 不上传本地收藏、下载历史、阅读进度到开发者服务器。
- 登录凭证仅保存在本机，并通过 HUKS 加密。
- 网络请求直接发往用户选择的镜像站点。

完整隐私政策请查看：

- [docs/privacy.md](docs/privacy.md)

## 免责声明

1. 本项目是第三方客户端，与 Z-Library 官方无关联。
2. 本项目不存储、不分发、不审查任何书籍内容。
3. 所有内容均来自用户选择访问的第三方镜像站点。
4. 用户应自行确认使用行为符合所在地区的法律法规。
5. 镜像站点的可达性、内容合法性和安全性由对应站点负责。
6. 本项目以“现状”提供，不对稳定性、适用性或可用性作任何明示或默示担保。

## 许可证

MIT License

---

© 2026 海阅 HLib
