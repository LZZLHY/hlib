# olib v1.0.4 反编译产出（hlib 协议层补强参考）

> 来源：`o-lib1.0.4.apk` → `lib/arm64-v8a/libapp.so`（Dart AOT，7.19 MB）
> 工具：PowerShell `Expand-Archive` + 自写 strings 提取脚本（基于 `Encoding.ASCII.GetString` + `[regex]`）
> 时间：P8 阶段，hlib 已基本对齐 olib 公开 endpoint 的前提下做"暗料确认"

---

## 1. 提取到的 endpoint 字符串

| Endpoint | 出现 | hlib 已实现 |
|---|---|---|
| `/eapi/info/languages`             | ✅ | ✅ 探针/ping |
| `/eapi/user/login`                 | ✅ | ✅ |
| `/eapi/user/profile`               | ✅ | ✅ |
| `/eapi/book/`（前缀，含详情）       | ✅ | ✅ `/eapi/book/{id}/{hash}` |
| `/eapi/book/search`                | ✅ | ✅ |
| `/eapi/user/book/`（前缀）         | ✅ | ✅ |
| `/eapi/user/book/saved`            | ✅ | ✅ |
| `/eapi/user/book/downloaded`       | ✅ | ✅ |
| `/eapi/user/book/recommended`      | ✅ | ✅ |
| `/save`（拼接到上面前缀）           | ✅ 单独 | ✅ `/eapi/user/book/save` |
| `/unsave`（拼接）                   | ✅ 单独 | ✅ `/eapi/user/book/unsave` |
| `/eapi/book/most-popular`          | ❌ 整串未命中 | ⚠️ hlib 已实现，olib 可能被 dead-code 消除 |
| `/eapi/book/recently`              | ❌ 整串未命中 | ⚠️ 同上 |
| `/eapi/book/{id}/{hash}/similar`   | ❌ 整串未命中 | ⚠️ 同上 |

> 后三个是 hlib 走得多于 olib 的（olib 的 `books_provider.dart` 调用了但 release 包未编出字符串，可能是 Riverpod lazy 或 tree-shake 导致 const 拆碎）。**这些 endpoint 仍按 Z-Library 公开规范保留**。

## 2. 关键反爬秘方（olib 的"私有"部分）

只有一条：**伪装 User-Agent 为浏览器**。

```
Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36
```

hlib `@/entry/src/main/ets/api/HttpClient.ets:32-34` 已对齐。

桌面端 olib 还在用：
```
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36
```

（hlib 是移动端，无需此版本）

## 3. 没有的东西（确认 olib 也不需要）

逐一搜索，均 0 命中：
- `cloudflare` / `captcha` / `singlelogin` / `challenge token`
- `x-zlib*` / `/m/api*` / `x-requested-with`
- 自定义加密签名 / API token 刷新机制

**结论**：olib 的 zlibrary_api.dart 没有特殊反爬手段，UA 伪装就是全部秘密。

## 4. 字段命名 / 协议形态对齐确认

| 字段 / 形态 | olib strings | hlib 实现 |
|---|---|---|
| `remix_userid` cookie  | ✅ | ✅ |
| `remix_userkey` cookie | ✅ | ✅ |
| `&remix_userid=` (cookie 串拼接) | ✅ | ✅ |
| `pagination.total_pages` | ✅ | ✅ |
| `filesizeString` | ✅ | ✅ |
| `readOnlineUrl` | ✅ | ✅ |
| `Accept-Language` 标头 | ✅ | ✅ |
| `application/json` content-type | ✅ | ✅ |

完全对齐。

## 5. 注册流程

- olib 的 `_api.sendCode` / `_api.verifyCode` 方法名（在 auth_provider.dart）**完全未在 release strings 中出现** —— 与 olib 主线 `// Registration disabled - API不支持` 注释一致
- hlib 同样未实现（一致）

## 6. olib 内部组件信息（顺手扒到的）

- 项目原名：`zlibrary_mobile`（dev 路径 `C:/Users/Administrator/StudioProjects/zlibrary_mobile`），后改名 olib_mobile
- olib 自家后端的字段（与本逆向无关）：`backendAuthProvider`、`themeModeProvider`、`recommendedBooksProvider`、`savedBooksProvider`、`UpdateService` 等
- AI 服务：`localAI`、`prescriber_screen` 字符串存在
- 滑动操作组件：使用 `flutter_slidable`
- 图标：使用 `cached_network_image`

## 7. hlib 行动落地

- ✅ HttpClient UA 已替换为 olib 同款浏览器伪装
- ✅ 所有公开 endpoint 已对齐
- ✅ 字段命名一致
- ⚠️ 已实现但 olib release 中字符串缺失的：`most-popular` / `recently` / `similar` 保留，按公开规范走

## 8. 不再继续深挖的理由

完整反编译需要 `blutter`（Flutter Dart AOT 反编译器，需要本机 build Dart SDK，1~2 小时环境），产出也只能拿到方法签名 + 字符串常量，**方法体（业务逻辑）拿不到**——而仅靠 strings 已穷尽 olib 的暗料。

---

## 9. hlib 在 olib 之上的协议层加固（基于本次逆向结论再走一步）

> 逆向证明 olib 反爬就一行 UA。hlib 在已抄齐 UA 的前提下，主动加固 4 项以提升稳定性与安全性。**所有 4 项 olib 都没有**，hlib 在协议层超过 olib。

### A. 多域名探测 + 自动漂移

- 运行时 `HttpClient.request<T>` 累计连续失败计数（`consecutiveFails`）
- 失败 ≥ `FALLBACK_FAIL_THRESHOLD`（=3）时，从 `AppStorage[SPEED_RESULTS]` 选下一个 alive 且未尝试过的域名
- 切换后原 url 中的旧 domain 替换为新 domain 自动重试
- 实现：`@/entry/src/main/ets/api/HttpClient.ets` 的 `request<T>` + `pickFallbackDomain()`

### B. 429 / 5xx 指数退避重试

- 重试规则：
  - **重试**：`NetworkError` / `HttpStatusError 5xx` / `HttpStatusError 429`
  - **不重试**：`UnauthorizedError` / `CfBlockedError` / `4xx` 其他状态码（避免无效重试拖时间）
- 退避：`800ms × 2^attempt`（首次 800ms、再 1.6s、再 3.2s）
- 上限 `RETRY_LIMIT`（=3），含首次共 4 次尝试
- 实现：同上 `request<T>` 循环 + `sleep` 工具

### C. UA 多候选随机轮换

- `UA_POOL` 包含 5 条不同 Android 版本的浏览器 UA（10 / 11 / 12 / 13 / 14）
- 每次 `attemptOnce` 调 `pickUA()` 随机选一条
- 即使某条 UA 被服务端识别封禁，其它 4 条仍可用
- `ping` 探针固定使用首条 UA，保持探测一致性
- 实现：`HttpClient.ets:38-51`

### D. HUKS 凭证 AES-256-GCM 加密

> 这是 hlib 最关键的安全加固。olib 的本地 cookie 是明文存储；hlib 改成 HUKS 加密。

- **Key 在 TEE / SE 内**：用 `huks.generateKeyItem` 生成 master key，`keyAlias = 'hlib_credential_master_v1'`，**应用永远拿不到原始字节**
- **加密**：`HUKS GCM` 模式，三段式 `initSession` + `finishSession`，每次新 nonce
- **存盘格式**：`sec1:<base64(12B nonce || N cipher || 16B authTag)>`
- **向后兼容**：`SecretStore.decrypt` 对非 `sec1:` 前缀输入原样返回，旧明文条目自动平滑迁移
- **保护的字段**：`remix_userid` / `remix_userkey` / `password`（`email` / `name` 是 PII 但非凭证，原文存）
- **降级策略**：HUKS 不可用时 `usable = false`，加解密 no-op 直通明文（兼容性优先）
- 实现：
  - `@/entry/src/main/ets/utils/SecretStore.ets`（HUKS 封装，213 行）
  - `@/entry/src/main/ets/storage/AuthStore.ets`（saveCredentials / getCredentials / upsertAccount / listAccounts / removeAccount 全部加解密）
  - `@/entry/src/main/ets/entryability/EntryAbility.ets:22-23`（启动时 `await SecretStore.init()`）

#### 威胁模型对比

| 攻击场景 | olib | hlib（D 加固后） |
|---|---|---|
| 设备截屏看到 prefs 文件 | 看到明文 cookie | 只看到 `sec1:Y2lwaGVy...`，无法直接登 |
| root 设备 dump 应用沙箱 | 拿到明文 cookie 即可登 | 拿到 cipher + keyAlias 句柄，**无法离线解密**——必须在该设备上重新调 HUKS API |
| 冷备份扫描器扫凭证 | 命中 `remix_userid=xxxxx` | 命中 `sec1:...` 字符串无法识别为凭证 |
| 跨设备克隆数据库 | 直接可登 | HUKS key 绑定本设备，cipher 在其它设备上解不开 |

### 编译验证

```
BUILD SUCCESSFUL
ERROR: 0
WARN: 3（仅 ScanKit syscap 设计性提示，运行时已 canIUse 守卫）
```

新增代码 0 警告 0 错误。

---

## 10. 兜底方案：T2 代理 + T3 DoH + T4 Onion + 镜像在线同步

### 10.1 为什么"直连 Z-Library"在国内能跑

**关键事实**：hlib 与 olib **都不连 Z-Library 主域**（`z-library.sk` 等已被 GFW 主动 DNS 污染 + IP 黑洞），而是连**镜像域名池**（pkuedu.online / 9libmirror.tech / anthology.lol 等 50+ 二级域）。

工作链路：
```
DNS 解析 pkuedu.online    ← 国内未污染该小众域名
→ Cloudflare CDN IP        ← 国内大部分 IP 路由可达
→ HTTPS + 浏览器 UA         ← olib 同款 UA pool
→ CDN 反代到真实后端
```

**Z-Library 项目策略**：每月新增 5~10 个镜像域，"数量战胜审查更新速度"——封 1 个上 5 个。这就是 olib / hlib 都能跑的全部秘密。

### 10.2 镜像列表在线同步（DomainManifest）

> Z-Library 后端**没有暴露** `/eapi/info/domains` 类型的 endpoint（一旦暴露=方便封禁）。olib 也是硬编码。hlib 加"自定义远程 manifest"扩展，由用户/项目方自维护。

实现：
- `@/entry/src/main/ets/api/DomainManifest.ets`
- 默认禁用，用户在设置中显式开启 + 配置 manifest URL 才生效
- Manifest JSON 格式：
  ```json
  {
    "version": "2026-04-30",
    "domains": ["pkuedu.online", "9libmirror.tech", "..."]
  }
  ```
- 严格清洗：去 schema、小写、去尾斜杠、白名单 regex（仅小写字母/数字/`.`/`-`），防注入
- 拉到的域名与内置 `DOMAINS` **合并去重**，不替换
- 失败回退内置列表，不阻塞启动

推荐 manifest 托管位置：
| 选项 | 优势 |
|---|---|
| GitHub Raw `https://raw.githubusercontent.com/<owner>/<repo>/main/domains.json` | 免费 / 可版本控制 / 国内 ip 可达性中等 |
| jsdelivr CDN `https://cdn.jsdelivr.net/gh/<owner>/<repo>@main/domains.json` | 国内 ip 可达性较好（有节点） |
| Cloudflare Pages `https://<name>.pages.dev/domains.json` | 全球 CDN / 部分时段国内可达 |

### 10.3 T2：HTTP 代理转发

> 务实兜底——比 Tor 实用得多。用户**自己**提供代理 URL，hlib 仅"支持代理"而不内嵌任何境外通信组件。**合规风险用户自担**，应用本身合规。

实现：
- `HttpClient.setProxy(host, port)` / `clearProxy()`
- `attemptOnce` 与 `ping` 内部统一注入 `reqOpts.usingProxy`
- AppStorageKeys：`PROXY_ENABLED` / `PROXY_HOST` / `PROXY_PORT`
- EntryAbility.onCreate 启动时读取偏好并应用
- SettingsPage 设置 UI：开关 + Host + Port 输入

适用场景：
- 自建 VPS（用户在境外的 SS / V2Ray / Trojan 等代理）
- 本地 Clash / Sing-box 端口（如 `127.0.0.1:7890`）
- 朋友共享的代理

### 10.4 T3：DoH 解析（仅诊断用途）

> ⚠️ **HarmonyOS NetworkKit `http` 模块不暴露 SNI 控制字段**——传统的「DoH 解析后 IP 直连 + Host header」方案在 HTTPS 下不可行（TLS 握手时 SNI=IP 导致证书校验失败）。要做真正 SNI bypass 必须自实现 socket+TLS 客户端，工作量数百行高风险代码，ROI 极低。

折中方案：DoH 仅作**网络诊断**用途，不参与请求路由。

实现：
- `@/entry/src/main/ets/utils/DohResolver.ets`
- `resolveA(hostname)`：通过 Cloudflare DoH 端点（`cloudflare-dns.com/dns-query` 主，`1.1.1.1/dns-query` fallback）查 A 记录
- `diagnoseAsync(hostname)`：HttpClient 自动 fallback 触发时**异步**调，写入 Logger 用于事后排查
  - DNS 解析成功但请求失败 → 提示 IP 层封锁 / Cloudflare 节点不可达
  - DNS 解析失败 → 提示 DNS 污染或域名失效

### 10.5 T4：Onion URL 兑底（不内嵌 Tor）

> Tor 在国内的硬伤：公开 Tor 入口节点 100% 被 GFW 封；Bridges 体验差；HarmonyOS 没原生 SDK；分发内嵌 Tor 应用合规风险高。**hlib 的解法**：不内嵌 Tor，仅展示 .onion URL 让用户自己用 Tor Browser 打开。

实现：
- `DomainSelectorDialog` 底部增加"复制 Tor 地址"按钮
- 内置 Z-Library 官方 .onion 地址（多年不变）：
  ```
  http://loginzlib2vrak5zzpcocc3ouizykn6k5qecgj2tzlnab5wcbqhembyd.onion
  ```
- 点击 → `pasteboard` 写剪贴板 + Toast 提示用 Tor Browser 打开
- 零工程成本、零合规风险、零 .hap 体积增长

### 10.6 加固完整对比

| 加固层级 | olib | hlib |
|---|---|---|
| **A**. 多镜像域名漂移 | 启动测速选最快（手动切换） | + 运行时**自动**漂移（连续失败 ≥ 3 立即换域） |
| **B**. 退避重试 | ❌ 无 | 800ms × 2^n，3 次重试，仅对 5xx/429 重试 |
| **C**. UA 多候选 | ❌ 单一 UA | UA pool 5 条随机轮换 |
| **D**. 凭证加密 | ❌ 明文存盘 | HUKS AES-256-GCM（key 在 TEE） |
| **T1**. 镜像静态列表 | 硬编码 58 个 | 硬编码 58 + 远程 manifest 同步 |
| **T2**. HTTP 代理支持 | ❌ 无 | 设置中可填 host:port |
| **T3**. DoH 诊断 | ❌ 无 | 失败时自动 DNS 查询写日志 |
| **T4**. Onion 兑底 | ❌ 无 | 一键复制 .onion |
| **T5**. 请求频率抖动 | ❌ 无 | 每个业务请求注入 25-150ms 随机 jitter，打乱并发节奏防 batch 识别 |

hlib 在协议层 / 网络层 / 安全层 **9 项指标全面超过 olib**。

### 10.7 T5：请求频率随机抖动（防 batch 识别）

**目的**：服务端反爬可能根据"短时间内相同 IP/账号触发的请求间隔规律性"识别机器人。olib 用 `Future.wait([f1, f2, f3])` 同时发首页 3 个 endpoint 请求，毫秒级整齐节奏容易被识别。hlib 加 jitter 打乱节奏。

**实现**：
- `request<T>` 入口处 `await sleep(jitterMs())`，jitterMs ∈ [25, 150]
- 每个请求独立生成抖动值（随机化）
- **不影响**：
  - `ping` 探针（保持测速准确）
  - retry backoff（已有自己的退避节奏，jitter 不叠加）
- **代价**：单请求增加 ≤150ms 延迟，用户感知不明显（人类反应时间通常 200ms+）
- **收益**：3 个并发请求被随机错开 25-150ms，服务端看到的是"散乱"而非"齐步走"

代码位置：`@/entry/src/main/ets/api/HttpClient.ets`（`JITTER_MIN_MS` / `JITTER_MAX_MS` / `jitterMs()` / `request<T>` 入口）。

### 10.8 示例 manifest 模板

放一个 `domains.json` 模板供项目方/用户参考。建议托管到 GitHub raw 或自有 CDN：

```json
{
  "version": "2026-04-30",
  "domains": [
    "pkuedu.online",
    "9libmirror.tech",
    "bookroom.digital",
    "anthology.lol",
    "interflow.ch"
  ]
}
```

更新流程：发现新镜像 → 提交 PR / 推到对应仓库 → 用户下次启动自动同步。
