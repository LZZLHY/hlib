/*
 * PublicDownloadDir.ets — 公共「下载」目录访问（应用专属，归类到公共 Download 下）
 *
 * 设备能力分两条路（内容依据华为官方文档整理改写）：
 *   1) 平板 / 2in1（syscap FolderObtain 支持）：
 *      `Environment.getUserDownloadDir()` 直接静默拿到公共 Download 的沙箱映射路径，
 *      写入 `<Download>/<bundleName>/`，需 user_grant 权限 `READ_WRITE_DOWNLOAD_DIRECTORY`。
 *   2) 手机（FolderObtain 不支持，getUserDownloadDir 报 801）：
 *      用 `DocumentViewPicker`（DOWNLOAD 模式）交互式让用户确认一次 → 拿到 `Download/<应用名>/` 目录 URI，
 *      经 `fileShare.persistPermission` 持久化授权，把目录路径缓存到 AppStorage（持久化），
 *      之后所有下载 / 导出静默复用，启动时 `activatePersisted()` 重新激活权限。
 *
 * 任何失败（不支持 / 未授权 / 用户取消）均返回空串，调用方回退应用沙箱。
 */

import { Environment, picker, fileUri, fileIo, fileShare } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions, wantConstant, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Logger } from './Logger';

const TAG: string = 'PublicDownloadDir';
const PERM: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';
/** 在公共目录里建一个标记文件以探测/确认目录，随后删除。 */
const MARKER: string = '.hlib_keep';
const RW_MODE: number =
  wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION | wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION;

export class PublicDownloadDir {
  /** 平板 / 2in1 静默路线是否可用（syscap）。 */
  static isTabletSilent(): boolean {
    return canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain');
  }

  /**
   * 本设备是否“有办法”保存到公共下载目录。平板走 Environment、手机走 picker，两路都可用，恒为 true。
   * 保留此方法是为兼容旧调用点语义。
   */
  static isSupported(): boolean {
    return true;
  }

  /** 目录是否存在且可访问（同步）。 */
  static isWritable(dir: string): boolean {
    if (dir === undefined || dir === null || dir.length === 0) {
      return false;
    }
    try {
      return fileIo.accessSync(dir);
    } catch (e) {
      return false;
    }
  }

  /**
   * 纯同步读取“当前已确立”的公共下载目录路径；未确立返回空串。
   * 不弹任何 UI，可在后台下载管线中安全调用。
   *   平板：实时由 Environment 解析 `<Download>/<bundleName>`。
   *   手机：返回此前 picker 选定并缓存的路径。
   */
  static resolveDir(): string {
    if (PublicDownloadDir.isTabletSilent()) {
      try {
        const base: string = Environment.getUserDownloadDir();
        if (base !== undefined && base !== null && base.length > 0) {
          const bundle: string = AppStorage.get<string>(AppStorageKeys.BUNDLE_NAME) ?? '';
          return bundle.length > 0 ? `${base}/${bundle}` : base;
        }
      } catch (e) {
        Logger.w(TAG, `getUserDownloadDir failed: ${(e as Error).message}`);
      }
      return '';
    }
    return AppStorage.get<string>(AppStorageKeys.PUBLIC_DOWNLOAD_DIR) ?? '';
  }

  /**
   * 交互式确保拿到一个可写的公共下载目录，返回其绝对路径；失败 / 取消返回空串。
   *   平板：申请 READ_WRITE_DOWNLOAD_DIRECTORY 权限（弹窗）→ Environment 路径。
   *   手机：已有可写缓存则直接复用；否则唤起 DocumentViewPicker 让用户确认一次。
   * 必须在 UI 交互时机调用（设置页切换 / 点击导出），勿在后台下载里调用。
   */
  static async ensureDir(ctx: common.UIAbilityContext): Promise<string> {
    if (PublicDownloadDir.isTabletSilent()) {
      const granted: boolean = await PublicDownloadDir.requestDownloadPerm(ctx);
      if (!granted) {
        return '';
      }
      return PublicDownloadDir.resolveDir();
    }
    // 手机：复用已选定且仍可写的目录
    const cached: string = AppStorage.get<string>(AppStorageKeys.PUBLIC_DOWNLOAD_DIR) ?? '';
    if (cached.length > 0 && PublicDownloadDir.isWritable(cached)) {
      return cached;
    }
    return await PublicDownloadDir.pickViaPicker(ctx);
  }

  /** 平板：申请下载目录读写权限（user_grant 弹窗）。 */
  private static async requestDownloadPerm(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      const atm: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Array<Permissions> = [PERM];
      const res = await atm.requestPermissionsFromUser(ctx, perms);
      const results: number[] = res.authResults;
      return results.length > 0 && results[0] === 0; // 0 = PERMISSION_GRANTED
    } catch (e) {
      Logger.w(TAG, `requestDownloadPerm failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 手机：DocumentViewPicker（DOWNLOAD 模式）选定 Download/<应用名> 目录，持久化并缓存。 */
  private static async pickViaPicker(ctx: common.UIAbilityContext): Promise<string> {
    try {
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD; // 默认落到 Download/<应用名>/
      opts.newFileNames = [MARKER];
      const vp: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const res: Array<string> = await vp.save(opts);
      if (res === undefined || res === null || res.length === 0) {
        return '';
      }
      const uri: string = res[0];
      const filePath: string = new fileUri.FileUri(uri).path;
      const slash: number = filePath.lastIndexOf('/');
      const dir: string = slash >= 0 ? filePath.substring(0, slash) : filePath;

      // 持久化授权（best-effort：失败也不阻断本次会话使用）
      await PublicDownloadDir.tryPersist(uri);

      AppStorage.setOrCreate<string>(AppStorageKeys.PUBLIC_DOWNLOAD_DIR, dir);
      AppStorage.setOrCreate<string>(AppStorageKeys.PUBLIC_DOWNLOAD_URI, uri);

      // 标记文件用完即删（best-effort）
      try {
        if (fileIo.accessSync(filePath)) {
          fileIo.unlinkSync(filePath);
        }
      } catch (e) {
        Logger.w(TAG, `cleanup marker failed: ${(e as Error).message}`);
      }
      return dir;
    } catch (e) {
      Logger.w(TAG, `pickViaPicker failed: ${(e as Error).message}`);
      return '';
    }
  }

  private static async tryPersist(uri: string): Promise<void> {
    try {
      const policy: fileShare.PolicyInfo = { uri: uri, operationMode: RW_MODE };
      await fileShare.persistPermission([policy]);
    } catch (e) {
      Logger.w(TAG, `persistPermission failed: ${(e as Error).message}`);
    }
  }

  /** 启动时重新激活此前持久化的目录授权（best-effort）。手机重启后需要，平板无需。 */
  static async activatePersisted(): Promise<void> {
    if (PublicDownloadDir.isTabletSilent()) {
      return;
    }
    const uri: string = AppStorage.get<string>(AppStorageKeys.PUBLIC_DOWNLOAD_URI) ?? '';
    if (uri.length === 0) {
      return;
    }
    try {
      const policy: fileShare.PolicyInfo = { uri: uri, operationMode: RW_MODE };
      await fileShare.activatePermission([policy]);
    } catch (e) {
      Logger.w(TAG, `activatePersisted failed: ${(e as Error).message}`);
    }
  }

  /** 跳转系统文件管理器，打开公共下载目录（优先深链，失败回退 startAbility）。 */
  static openFolder(ctx: common.UIAbilityContext): void {
    const dir: string = PublicDownloadDir.resolveDir();
    const uri: string = dir.length > 0 ? fileUri.getUriFromPath(dir) : '';
    const link: string = 'filemanager://openDirectory';
    const options: OpenLinkOptions = { parameters: { 'fileUri': uri } };
    ctx.openLink(link, options).catch((e: BusinessError): void => {
      Logger.w(TAG, `openLink failed: code=${e.code} msg=${e.message}; fallback startAbility`);
      PublicDownloadDir.openFolderFallback(ctx, dir);
    });
  }

  private static openFolderFallback(ctx: common.UIAbilityContext, dir: string): void {
    const folder: string = dir.length > 0 ? dir : `${ctx.filesDir}/Downloads`;
    const uri: string = folder.startsWith('file://') ? folder : fileUri.getUriFromPath(folder);
    ctx.startAbility({
      action: 'ohos.want.action.viewData',
      uri: uri,
      type: 'resource/directory',
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
    }).catch((e: BusinessError): void => {
      Logger.w(TAG, `openFolderFallback failed: code=${e.code} msg=${e.message}`);
    });
  }
}
