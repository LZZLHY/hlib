# 开发笔记：HarmonyOS 第三方应用「下载到公共下载目录」实战

> 适用：HarmonyOS NEXT（compatibleSdkVersion API 23）普通签名的第三方应用，把文件保存到系统「下载」目录下以应用命名的专属文件夹（`下载/<应用名>/`），并在重启后仍可读写、可在应用内重新打开。
>
> 本文记录了「海阅 HLib」实现该能力的完整技术路线、可直接复用的示例代码、官方文档出处，以及我（AI）在此过程中**反复犯过的错误与心得**，供后来者少走弯路。
>
> 文中对华为官方文档内容均为整理改写（content rephrased for licensing compliance）。

---

## 1. 目标与难点

需求很简单：用户点下载，书直接进系统「下载」目录，文件管理里能看到 `下载/<应用名>/书名.epub`。

难点在于 **HarmonyOS 的沙箱隔离**：普通第三方应用默认只能读写自己的沙箱（`ctx.filesDir` / `ctx.cacheDir`），公共目录受系统强管控。而且**手机与平板的能力不一样**，同一套「想当然」的代码在手机上会直接失败。

---

## 2. 设备能力差异（核心认知）

| 能力 | 平板 / 2in1 | 手机 |
|---|---|---|
| `Environment.getUserDownloadDir()` | ✅ 返回公共 Download 的沙箱映射路径，可按**原始路径**静默写 | ❌ 报错 **801**（device doesn't support this api） |
| syscap `...File.Environment.FolderObtain` | ✅ 支持 | ❌ 不支持 |
| 按原始路径 `fileIo.openSync` 写公共 Download | ✅（配合 `READ_WRITE_DOWNLOAD_DIRECTORY` 权限） | ❌ `Operation not permitted` |
| `DocumentViewPicker` DOWNLOAD 模式 | ✅ | ✅（**唯一可行**且静默） |

结论：**必须按设备能力分两条路**，用 `canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain')` 判定。

---

## 3. 三条技术路线对比

| 路线 | 手机可用？ | 结论 |
|---|---|---|
| A. `Environment.getUserDownloadDir()` + 原始路径写 | ❌ | 平板可用；手机 801。仅作平板路线。 |
| B. `FILE_ACCESS_MANAGER` + FileAccess 框架（`@ohos.file.fileAccess`） | ❌ | 该权限是**系统级**，只授予系统文件管理类应用；普通应用**安装即被拒**（"grant request permissions failed"）。死路。 |
| C. `DocumentViewPicker` 的 **DOWNLOAD 模式** + 授权持久化 | ✅ | **最终方案**。手机/平板均可，且 DOWNLOAD 模式**无弹窗**。 |

> 路线 A、B 的失败都是我在真机上一一实测出来的（见第 7 节心得）。

---

## 4. 最终方案：DOWNLOAD 模式 + 授权持久化

### 4.1 DOWNLOAD 模式的三个关键特性（官方）

依据[保存用户文件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/save-user-file)文档（整理改写）：

1. **自动落到 `下载/<包名/应用名>/`**；
2. **跳过文件选择界面、直接返回目录 URI**——也就是说 **DOWNLOAD 模式没有弹窗**，调用即返回；
3. **返回的 URI 已具备持久化权限**，可在该 URI 下创建文件。

官方写法（节选改写）：

```ts
import { fileUri, picker, fileIo } from '@kit.CoreFileKit';

const opts = new picker.DocumentSaveOptions();
opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD; // 设了 DOWNLOAD，其它 options 参数不生效
const vp = new picker.DocumentViewPicker(context);
const uris = await vp.save(opts);          // 无弹窗，返回 [目录 URI]
const dirUri = uris[0];

// 在该目录 URI 下创建并写文件：拼好文件名 → 转成路径 → openSync
const filePath = new fileUri.FileUri(dirUri + '/test.txt').path;
const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
fileIo.writeSync(file.fd, 'Hello World!');
fileIo.closeSync(file.fd);
```

### 4.2 授权持久化（跨重启复用 + 应用内重开）

依据[授权持久化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-persistpermission)文档（整理改写）：

- Picker 拿到的授权默认是**临时**的，应用退到后台 / 设备重启后会清除；
- 需长期访问 → `fileShare.persistPermission()` 持久化；
- **每次启动**需 `fileShare.activatePermission()` 激活后才能用；
- 关键参数 `operationMode` 用 **`fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE`**；
- syscap：`SystemCapability.FileManagement.AppFileService.FolderAuthorization`；
- 权限：`ohos.permission.FILE_ACCESS_PERSIST`；
- API 24+ 还可在 module 的 metadata 配 `ohos.fileshare.supportPreservePersistentPermission`，**卸载重装后保留**授权（本项目 compatibleSdkVersion=23，未启用）。

```ts
import { fileShare } from '@kit.CoreFileKit';

const RW = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;
const policy: fileShare.PolicyInfo = { uri: dirUri, operationMode: RW };

// 首次：持久化
await fileShare.persistPermission([policy]);

// 每次启动：激活（否则已持久化的权限仍不可用）
await fileShare.activatePermission([policy]);
```

### 4.3 权限 / 配置清单（`module.json5`）

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  {
    "name": "ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY", // 平板静默写公共目录
    "reason": "$string:reason_download_dir",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  },
  {
    "name": "ohos.permission.FILE_ACCESS_PERSIST",           // 授权持久化（手机）
    "reason": "$string:reason_file_persist",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  }
]
```

> 实测：`FILE_ACCESS_PERSIST` 可授予普通第三方应用、安装不被拒（与系统级的 `FILE_ACCESS_MANAGER` 截然不同）。

---

## 5. 本项目落地代码（可直接复用）

### 5.1 `PublicDownloadDir`：能力封装

核心思路：对外暴露一个 `ensurePublicDirPath(ctx)`，内部按设备能力走不同分支，返回一个**可写的公共目录原始路径**，调用方一律用 `<目录>/<文件名>` 落盘。

```ts
import { Environment, picker, fileUri, fileIo, fileShare } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

const PERM: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';
const RW: number = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;

export class PublicDownloadDir {
  /** 平板静默路线是否可用 */
  static isTabletSilent(): boolean {
    return canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain');
  }

  /** fileShare 持久化能力是否可用 */
  static isPersistSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
  }

  /** 确保拿到可写的公共目录原始路径；失败/取消返回 '' */
  static async ensurePublicDirPath(ctx: common.UIAbilityContext): Promise<string> {
    if (PublicDownloadDir.isTabletSilent()) {
      // 平板：申请权限 → Environment 路径
      const granted = await PublicDownloadDir.requestDownloadPerm(ctx);
      return granted ? PublicDownloadDir.resolveTabletDir() : '';
    }
    return await PublicDownloadDir.ensurePhoneDirPath(ctx);
  }

  private static resolveTabletDir(): string {
    const base = Environment.getUserDownloadDir();      // 平板可用
    const bundle = AppStorage.get<string>('state_bundleName') ?? '';
    return bundle.length > 0 ? `${base}/${bundle}` : base;
  }

  private static async requestDownloadPerm(ctx: common.UIAbilityContext): Promise<boolean> {
    const atm = abilityAccessCtrl.createAtManager();
    const res = await atm.requestPermissionsFromUser(ctx, [PERM]);
    return res.authResults.length > 0 && res.authResults[0] === 0;
  }

  /** 手机：复用已持久化目录或经 DOWNLOAD 模式获取并持久化 */
  private static async ensurePhoneDirPath(ctx: common.UIAbilityContext): Promise<string> {
    // 1) 复用：已存的目录 URI 激活成功就直接用
    const stored = AppStorage.get<string>('pref_publicDownloadUri') ?? '';
    if (stored.length > 0 && await PublicDownloadDir.activate(stored)) {
      const p = new fileUri.FileUri(stored).path;
      AppStorage.setOrCreate<string>('pref_publicDownloadDir', p);
      return p;
    }
    // 2) 首次：DOWNLOAD 模式（无弹窗）取目录 URI
    let dirUri = '';
    try {
      const opts = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD;   // 不要设 newFileNames，只取目录
      const vp = new picker.DocumentViewPicker(ctx);
      const uris = await vp.save(opts);
      dirUri = (uris && uris.length > 0) ? uris[0] : '';
    } catch (e) {
      return '';
    }
    if (dirUri.length === 0) return '';

    await PublicDownloadDir.persist(dirUri);                  // best-effort
    const dirPath = new fileUri.FileUri(dirUri).path;
    AppStorage.setOrCreate<string>('pref_publicDownloadUri', dirUri);
    AppStorage.setOrCreate<string>('pref_publicDownloadDir', dirPath);
    return dirPath;
  }

  private static async persist(uri: string): Promise<void> {
    if (!PublicDownloadDir.isPersistSupported()) return;
    try {
      await fileShare.persistPermission([{ uri, operationMode: RW }]);
    } catch (e) { /* DOWNLOAD URI 本已可持久，报错可忽略 */ }
  }

  private static async activate(uri: string): Promise<boolean> {
    if (!PublicDownloadDir.isPersistSupported()) return false;
    try {
      await fileShare.activatePermission([{ uri, operationMode: RW }]);
      return true;
    } catch (e) { return false; }
  }

  /** 启动时激活（手机端跨重启复用的关键） */
  static async activatePersisted(): Promise<void> {
    if (PublicDownloadDir.isTabletSilent()) return;
    const stored = AppStorage.get<string>('pref_publicDownloadUri') ?? '';
    if (stored.length > 0) await PublicDownloadDir.activate(stored);
  }
}
```

### 5.2 下载落盘（`DownloadVM`）

要点：**目录解析只在 UI 入口 `start()` 做一次**，把目标路径随「镜像重试」复用，避免每次重试都重新触发授权流程。

```ts
static async start(book: Book, ctx: common.UIAbilityContext): Promise<DownloadTask> {
  let filePathOverride: string | undefined = undefined;
  if (AppStorage.get<string>('pref_downloadPath') === 'public') {
    const dirPath = await PublicDownloadDir.ensurePublicDirPath(ctx);
    if (dirPath.length > 0) {
      filePathOverride = `${dirPath}/${DownloadPaths.buildFilename(book)}`;
    }
    // dirPath 为空（不支持/取消）→ 回退沙箱
  }
  // ...把 filePathOverride 存进重试上下文，startInternal 优先用它，否则用沙箱路径
}

// 落盘（与原沙箱写盘逻辑一致，路径换成 filePathOverride 即可）
const file = fileIo.openSync(
  filePath,
  fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
);
// ... 流式 writeSync ... closeSync
```

### 5.3 启动激活（`EntryAbility.onCreate`）

```ts
// 在读到 bundleName 之后，best-effort 激活，不阻塞启动
PublicDownloadDir.activatePersisted().catch((e: Error) => {
  Logger.w(TAG, `activatePersisted failed: ${e.message}`);
});
```

### 5.4 跳转系统文件管理器到下载目录（深链）

```ts
import { OpenLinkOptions } from '@kit.AbilityKit';

const options: OpenLinkOptions = { parameters: { 'fileUri': dirUriOrUri } };
ctx.openLink('filemanager://openDirectory', options)
  .catch((e) => { /* 回退：startAbility(action: 'ohos.want.action.viewData', uri, type:'resource/directory') */ });
```

---

## 6. 完整调用时序

```
设置页选「公共下载目录」
  └─ ensurePublicDirPath(ctx)
       ├─ 平板：requestPermissionsFromUser(READ_WRITE_DOWNLOAD_DIRECTORY) → Environment 路径
       └─ 手机：DOWNLOAD 模式 save()（无弹窗）→ dirUri
                → persistPermission(dirUri, RW) → 缓存 uri+path

点击下载（public 模式）
  └─ start(): ensurePublicDirPath() →（手机优先复用并 activate 已存 uri）→ dirPath
       └─ filePath = dirPath/<文件名> → openSync(CREATE|RW|TRUNC) → 流式写

App 重启
  └─ EntryAbility.onCreate: activatePersisted() → activatePermission(已存 uri)
       └─ 之后下载 / 应用内打开分享均可按原始路径访问
```

---

## 7. 我犯过的错误与心得 ⭐

这一节是这份文档最值钱的部分。下面每一条都是真实踩过的坑。

### 错误 1：想当然地以为「拿到路径就能写」
最初照搬「`Environment.getUserDownloadDir()` + `fs.mkdir` + `fs.openSync`」的方案，在手机上直接 **801 / Operation not permitted**。
**心得**：HarmonyOS 公共目录访问是**能力分级**的，手机和平板不是一套 API。任何涉及公共目录的代码，第一步先 `canIUse` 判设备能力，别假设。

### 错误 2：被「权限名看起来对」骗了，去申请 `FILE_ACCESS_MANAGER`
看到方案里写 `FILE_ACCESS_MANAGER` + FileAccess 框架，以为能"无需额外权限写 Downloads"。结果**安装直接被拒**——它是系统级权限，只给系统文件管理器。
**心得**：申请权限前先查它的**开放范围/级别**（普通 / system_basic / system_core / ACL）。普通第三方应用拿不到的权限，写了也是白写，甚至装不上。**用真机安装去验证权限是否被接受**，比读文档更快暴露问题。

### 错误 3（最致命）：误解了 picker 授权的「作用域」和「时机」
我第一版的逻辑是：在「设置页」用 picker 拿一次目录、删掉标记文件、把**重建的原始路径**存起来；等到**下载时**再去 `openSync` 那个路径。结果 `Operation not permitted`。
**根因**：picker 授予的访问权限，作用在它返回的那个 **URI / 目录**上，且临时授权**退到后台就失效**。我在「另一次会话」里拿一个自己拼的路径去写，授权早没了。
**心得**：
- picker 拿到 URI 后要**在同一会话内、就着这个 URI/目录**去操作；
- 想跨会话/跨重启复用，**必须走 `persistPermission` + 每次启动 `activatePermission`**，不能靠"把路径字符串存下来"自欺欺人。

### 错误 4：把目录 URI 的父目录算错了
我用 `new fileUri.FileUri(uri).path` 拿到的其实是**应用专属目录**（`下载/<应用名>`），却又对它取了一次 `substring(0, lastSlash)`，把 `<应用名>` 那层弄丢了，文件落到了 `下载/` 根目录。日志里的 `cleanup marker failed: Is a directory` 就是铁证——它本来就是个目录，我当成文件去 unlink。
**心得**：对 picker 返回值，**先打日志确认它到底是文件还是目录**（`statSync().isDirectory()`），别凭感觉拼路径。DOWNLOAD 模式下 `FileUri(uri).path` 给的是**目录**，文件名要自己往后拼。

### 错误 5：`persistPermission` 的 `operationMode` 用错了常量
持久化一直报 `Operation not permitted`，我一度以为是权限没下来、是设备不支持。实际是我把 `operationMode` 填成了 `wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION | ...`（want 的标志位），而 fileShare 要的是 **`fileShare.OperationMode.READ_MODE | WRITE_MODE`**。两套常量数值或语义不一致，接口直接拒绝。
**心得**：跨 Kit 的接口，**参数常量一定要用该接口自己命名空间下的枚举**，别拿"看起来差不多"的另一套标志位顶替。报错信息模糊时（如 Operation not permitted），优先怀疑**入参取值是否合法**，而不是一上来就归因于"系统不支持/没权限"。

### 错误 6：过早下"做不到"的结论
在错误 3、5 还没排查清楚时，我一度判断"普通应用在手机上根本无法静默写公共目录、只能逐文件弹 picker 导出"，还据此改了一版降级方案。其实是**用户坚持"它能自动下进去"**、并贴出可用代码，逼着我回去重读官方文档，才发现 **DOWNLOAD 模式本就是静默的、URI 本就可持久化**。
**心得**：
- 当用户用实践反驳你的"理论不可行"时，**以实测/官方文档为准**，先别急着下"不可能"的定论；
- 失败要**定位到根因**（看 hilog 的具体 errno / message），而不是在表层反复打补丁、或直接放弃换降级方案；
- 官方文档要**读全**——"DOWNLOAD 模式跳过选择界面""返回 URI 已具备持久化权限"这两句关键描述，我前面几版都漏看了。

### 错误 7：删掉刚拿到授权的标记文件
为"清理"我把 picker 预置的空文件 unlink 掉，反而把仅有的、已授权的落点弄没了。
**心得**：picker 在 `autoCreateEmptyFile` 默认 `true` 时会**预置空文件并返回其 URI**，这个文件就是你授权写入的载体，别手贱删它；不需要预置就把 `autoCreateEmptyFile` 设 `false`。

### 一条贯穿始终的方法论
> **每改一处涉及系统能力的代码，就 build → 装真机 → 看 hilog**。这套"编译能过 ≠ 真机能用"的领域（文件/权限/跨进程），靠静态推理会反复翻车，靠真机日志能一次定位。

---

## 8. 验证清单（真机）

- [ ] 手机：设置选「公共下载目录」→ 下载一本书 → `下载/<应用名>/` 出现文件，无报错；
- [ ] 手机：**杀进程重启 App** → 对已下载书点「打开/分享」→ 正常打开（验证 `activatePermission` 生效）；
- [ ] 手机：重启后再下一本 → 仍直接落公共目录、无需重新授权；
- [ ] 平板：选「公共下载目录」→ 授权弹窗 → 下载静默落 `下载/<包名>/`；
- [ ] 「打开下载文件夹」能跳到对应目录。

---

## 9. 官方文档链接

- [保存用户文件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/save-user-file)（含 DOWNLOAD 模式）
- [授权持久化（ArkTS）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-persistpermission)
- [授权持久化（C/C++）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/native-fileshare-guidelines)
- [@ohos.file.fileshare（FileShare）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-fileshare)
- [@ohos.file.picker（选择器）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-picker)
- [@ohos.file.fs（文件管理）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-fs)

---

*归属：本文为「海阅 HLib」开发过程沉淀。华为官方文档内容均已整理改写以符合授权要求。*
