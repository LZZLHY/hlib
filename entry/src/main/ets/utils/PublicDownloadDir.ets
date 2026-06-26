/*
 * PublicDownloadDir.ets — 公共「下载」目录访问（应用专属，归类到公共 Download 下）
 *
 * 设备能力分两条路（内容依据华为官方文档整理改写，并经真机验证）：
 *
 *   1) 平板 / 2in1（syscap FolderObtain 支持）：
 *      `Environment.getUserDownloadDir()` 直接静默拿到公共 Download 的沙箱映射路径，
 *      用 `fileIo` 按**原始路径**写 `<Download>/<bundleName>/`，需 user_grant 权限
 *      `READ_WRITE_DOWNLOAD_DIRECTORY`。下载可静默落公共目录。
 *
 *   2) 手机（FolderObtain 不支持，getUserDownloadDir 报 801）：
 *      实测**无法**按原始路径写公共目录（fileIo.openSync 报 "Operation not permitted"），
 *      `fileShare.persistPermission` 也报 "Operation not permitted" —— 即第三方应用拿不到
 *      公共 Download 的持久原始路径写权限。唯一可行路线是 `DocumentViewPicker`：
 *      用户在保存弹窗里确认一次（DOWNLOAD 模式默认落到 `下载/<应用名>/`），save() 返回**文件 URI**，
 *      必须**立即**通过该 URI 写入（openSync(uri)）。一次 save() 可传入多个文件名 → 单弹窗批量授权。
 *      因此手机端下载先落沙箱（可靠），再由「下载」页「导出文件」用 picker 推送到公共目录。
 */

import { Environment, picker, fileUri, fileIo } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions, wantConstant, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Logger } from './Logger';

const TAG: string = 'PublicDownloadDir';
const PERM: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';

export class PublicDownloadDir {
  /** 平板 / 2in1 静默路线是否可用（syscap）。仅此情形可按原始路径静默写公共目录。 */
  static isTabletSilent(): boolean {
    return canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain');
  }

  /** 手机端（非平板静默）写公共目录必须经 DocumentViewPicker 交互。 */
  static needsPicker(): boolean {
    return !PublicDownloadDir.isTabletSilent();
  }

  /** 本设备是否“有办法”保存到公共下载目录（两路都算，恒 true）。保留以兼容旧调用点语义。 */
  static isSupported(): boolean {
    return true;
  }

  /** 目录/文件是否存在且可访问（同步）。 */
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
   * 平板：解析 `<Download>/<bundleName>` 原始路径（静默）。手机返回空串。
   * 纯同步、不弹 UI，可在后台下载管线安全调用。
   */
  static resolveDir(): string {
    if (!PublicDownloadDir.isTabletSilent()) {
      return '';
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
   * 平板：申请下载目录读写权限（弹窗）并返回可写目录路径；失败返回空串。
   * 手机不适用（返回空串，应改用 saveFilesViaPicker）。
   */
  static async ensureDir(ctx: common.UIAbilityContext): Promise<string> {
    if (!PublicDownloadDir.isTabletSilent()) {
      return '';
    }
    try {
      const atm: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const res = await atm.requestPermissionsFromUser(ctx, [PERM]);
      const results: number[] = res.authResults;
      if (results.length > 0 && results[0] === 0) {
        return PublicDownloadDir.resolveDir();
      }
    } catch (e) {
      Logger.w(TAG, `ensureDir failed: ${(e as Error).message}`);
    }
    return '';
  }

  /**
   * 手机：经 DocumentViewPicker（DOWNLOAD 模式）让用户确认一次，把给定文件名批量保存到
   * `下载/<应用名>/`，返回与 names 顺序对应的文件 URI 数组（须立即写入）；取消 / 失败返回空数组。
   */
  static async saveFilesViaPicker(ctx: common.UIAbilityContext, names: string[]): Promise<string[]> {
    if (names === undefined || names === null || names.length === 0) {
      return [];
    }
    try {
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD; // 默认落到 下载/<应用名>/
      opts.newFileNames = names;
      const vp: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const res: Array<string> = await vp.save(opts);
      return res !== undefined && res !== null ? res : [];
    } catch (e) {
      Logger.w(TAG, `saveFilesViaPicker failed: ${(e as Error).message}`);
      return [];
    }
  }

  /** 把沙箱文件内容拷贝到 picker 授权的目标 URI（fd 级拷贝）。失败抛异常。 */
  static copyPathToUri(srcPath: string, destUri: string): void {
    const rf: fileIo.File = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
    try {
      const wf: fileIo.File = fileIo.openSync(destUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.copyFileSync(rf.fd, wf.fd);
      } finally {
        fileIo.closeSync(wf);
      }
    } finally {
      fileIo.closeSync(rf);
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
