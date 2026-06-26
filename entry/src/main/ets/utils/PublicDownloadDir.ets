/*
 * PublicDownloadDir.ets — 公共「下载」目录访问（应用专属，归类到公共 Download 下）
 *
 * 依据华为官方文档（保存用户文件 / 授权持久化，内容整理改写）与真机验证，按设备能力分两条路：
 *
 *   1) 平板 / 2in1（syscap FolderObtain）：
 *      `Environment.getUserDownloadDir()` 直接静默拿到 `<Download>/<bundleName>` 原始路径，
 *      用 `fileIo` 按路径写，需 user_grant 权限 `READ_WRITE_DOWNLOAD_DIRECTORY`。
 *
 *   2) 手机（FolderObtain 不支持）：用 `DocumentViewPicker` 的 **DOWNLOAD 模式**——
 *      该模式自动落到 `下载/<应用名>/`、**跳过文件选择界面直接返回目录 URI**（无弹窗），
 *      且返回的 URI 已具备持久化权限。流程：
 *        · 首次：`save({pickerMode: DOWNLOAD})` 取目录 URI → `fileShare.persistPermission` 记账 →
 *          缓存 URI 与其路径（AppStorage 持久化）；
 *        · 后续 / 重启：`fileShare.activatePermission` 激活该 URI 即可继续按
 *          `<目录>/<文件名>` 原始路径读写（无需再次拉起 picker），应用内打开 / 分享也随之可用。
 *      持久化能力依赖 syscap `AppFileService.FolderAuthorization` + 权限 `FILE_ACCESS_PERSIST`。
 */

import { Environment, picker, fileUri, fileIo, fileShare } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions, wantConstant, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Logger } from './Logger';

const TAG: string = 'PublicDownloadDir';
const PERM: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';
const RW: number = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;

export class PublicDownloadDir {
  /** 平板 / 2in1 静默路线是否可用（syscap）。 */
  static isTabletSilent(): boolean {
    return canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain');
  }

  /** 手机端（非平板静默）须经 DocumentViewPicker DOWNLOAD 模式获取公共目录。 */
  static needsPicker(): boolean {
    return !PublicDownloadDir.isTabletSilent();
  }

  /** fileShare 持久化授权能力是否可用（syscap）。 */
  static isPersistSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
  }

  /** 本设备是否“有办法”保存到公共下载目录（两路都算，恒 true）。 */
  static isSupported(): boolean {
    return true;
  }

  /** 路径是否存在且可访问（同步）。 */
  static isWritable(path: string): boolean {
    if (path === undefined || path === null || path.length === 0) {
      return false;
    }
    try {
      return fileIo.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  /**
   * 同步返回“当前已确立”的公共下载目录路径；未确立返回空串。不弹 UI。
   *   平板：实时由 Environment 解析；手机：返回缓存的 picker 目录路径。
   */
  static resolveDir(): string {
    if (!PublicDownloadDir.isTabletSilent()) {
      return AppStorage.get<string>(AppStorageKeys.PUBLIC_DOWNLOAD_DIR) ?? '';
    }
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

  /**
   * 确保拿到一个可写的公共下载目录的**原始路径**，返回该目录路径；失败 / 取消返回空串。
   * 调用方据此用 `<目录>/<文件名>` 落盘。须在 UI 交互时机调用（下载入口 / 导出）。
   *   平板：申请权限 → Environment 路径。
   *   手机：复用已持久化并激活的目录；否则 DOWNLOAD 模式静默取目录并持久化。
   */
  static async ensurePublicDirPath(ctx: common.UIAbilityContext): Promise<string> {
    if (PublicDownloadDir.isTabletSilent()) {
      const granted: boolean = await PublicDownloadDir.requestDownloadPerm(ctx);
      return granted ? PublicDownloadDir.resolveDir() : '';
    }
    return await PublicDownloadDir.ensurePhoneDirPath(ctx);
  }

  /** 平板：申请下载目录读写权限（已授权不再弹窗）。 */
  private static async requestDownloadPerm(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      const atm: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const res = await atm.requestPermissionsFromUser(ctx, [PERM]);
      const results: number[] = res.authResults;
      return results.length > 0 && results[0] === 0;
    } catch (e) {
      Logger.w(TAG, `requestDownloadPerm failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 手机：复用持久化目录或经 DOWNLOAD 模式获取并持久化，返回目录原始路径。 */
  private static async ensurePhoneDirPath(ctx: common.UIAbilityContext): Promise<string> {
    // 复用已持久化的目录 URI（激活后即可按路径读写）
    const stored: string = AppStorage.get<string>(AppStorageKeys.PUBLIC_DOWNLOAD_URI) ?? '';
    if (stored.length > 0 && await PublicDownloadDir.activate(stored)) {
      const p: string = PublicDownloadDir.uriToPath(stored);
      if (p.length > 0) {
        AppStorage.setOrCreate<string>(AppStorageKeys.PUBLIC_DOWNLOAD_DIR, p);
        return p;
      }
    }
    // 首次：DOWNLOAD 模式取目录 URI（无弹窗）
    const dirUri: string = await PublicDownloadDir.pickDownloadDirUri(ctx);
    if (dirUri.length === 0) {
      return '';
    }
    await PublicDownloadDir.persist(dirUri); // best-effort：DOWNLOAD URI 本已可持久，记账以便重启后激活
    const dirPath: string = PublicDownloadDir.uriToPath(dirUri);
    if (dirPath.length === 0) {
      return '';
    }
    AppStorage.setOrCreate<string>(AppStorageKeys.PUBLIC_DOWNLOAD_URI, dirUri);
    AppStorage.setOrCreate<string>(AppStorageKeys.PUBLIC_DOWNLOAD_DIR, dirPath);
    return dirPath;
  }

  /** DOWNLOAD 模式：返回 `下载/<应用名>` 目录 URI（无弹窗）；失败 / 取消返回空串。 */
  private static async pickDownloadDirUri(ctx: common.UIAbilityContext): Promise<string> {
    try {
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const vp: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const uris: Array<string> = await vp.save(opts);
      return uris !== undefined && uris !== null && uris.length > 0 ? uris[0] : '';
    } catch (e) {
      Logger.w(TAG, `pickDownloadDirUri failed: ${(e as Error).message}`);
      return '';
    }
  }

  private static uriToPath(uri: string): string {
    try {
      return new fileUri.FileUri(uri).path;
    } catch (e) {
      Logger.w(TAG, `uriToPath failed: ${(e as Error).message}`);
      return '';
    }
  }

  private static async persist(uri: string): Promise<void> {
    if (!PublicDownloadDir.isPersistSupported()) {
      return;
    }
    try {
      const policy: fileShare.PolicyInfo = { uri: uri, operationMode: RW };
      await fileShare.persistPermission([policy]);
    } catch (e) {
      Logger.w(TAG, `persistPermission failed: ${(e as Error).message}`);
    }
  }

  private static async activate(uri: string): Promise<boolean> {
    if (!PublicDownloadDir.isPersistSupported()) {
      return false;
    }
    try {
      const policy: fileShare.PolicyInfo = { uri: uri, operationMode: RW };
      await fileShare.activatePermission([policy]);
      return true;
    } catch (e) {
      Logger.w(TAG, `activatePermission failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 启动时激活已持久化的公共目录授权（best-effort）。手机需要，平板跳过。 */
  static async activatePersisted(): Promise<void> {
    if (PublicDownloadDir.isTabletSilent()) {
      return;
    }
    const stored: string = AppStorage.get<string>(AppStorageKeys.PUBLIC_DOWNLOAD_URI) ?? '';
    if (stored.length > 0) {
      await PublicDownloadDir.activate(stored);
    }
  }

  /** 跳转系统文件管理器，打开公共下载目录（优先深链，失败回退 startAbility）。 */
  static openFolder(ctx: common.UIAbilityContext): void {
    let uriParam: string = '';
    if (!PublicDownloadDir.isTabletSilent()) {
      uriParam = AppStorage.get<string>(AppStorageKeys.PUBLIC_DOWNLOAD_URI) ?? '';
    }
    if (uriParam.length === 0) {
      const dir: string = PublicDownloadDir.resolveDir();
      uriParam = dir.length > 0 ? fileUri.getUriFromPath(dir) : '';
    }
    const options: OpenLinkOptions = { parameters: { 'fileUri': uriParam } };
    ctx.openLink('filemanager://openDirectory', options).catch((e: BusinessError): void => {
      Logger.w(TAG, `openLink failed: code=${e.code} msg=${e.message}; fallback startAbility`);
      PublicDownloadDir.openFolderFallback(ctx);
    });
  }

  private static openFolderFallback(ctx: common.UIAbilityContext): void {
    const dir: string = PublicDownloadDir.resolveDir();
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
