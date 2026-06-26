/*
 * PublicDownloadDir.ets — 公共下载目录访问（应用专属，归类到公共 Download 下）
 *
 * 机制（HarmonyOS 文件访问框架，内容依据华为官方文档整理改写）：
 *   - `Environment.getUserDownloadDir()` 返回应用可访问的「公共 Download 目录」沙箱映射路径；
 *     在手机 / 平板上，写入的文件会归类到公共下载目录下以**包名**命名的应用专属子目录里
 *     （用户在「文件管理 / 下载」中可见），卸载应用随之清理。
 *   - 需声明并经用户弹窗授予 user_grant 权限 `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`。
 *   - 能力依赖 syscap `SystemCapability.FileManagement.File.Environment.FolderObtain`。
 */

import { Environment } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Logger } from './Logger';

const TAG: string = 'PublicDownloadDir';
const PERM: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';

export class PublicDownloadDir {
  /** 设备是否支持获取公共下载目录。 */
  static isSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain');
  }

  /**
   * 申请下载目录读写权限（user_grant，弹窗）。已授权时不再弹窗直接返回 true。
   * 返回是否已获授权。永不抛异常。
   */
  static async requestPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    if (!PublicDownloadDir.isSupported()) {
      return false;
    }
    try {
      const atm: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Array<Permissions> = [PERM];
      const res = await atm.requestPermissionsFromUser(ctx, perms);
      const results: number[] = res.authResults;
      return results.length > 0 && results[0] === 0; // 0 = PERMISSION_GRANTED
    } catch (e) {
      Logger.w(TAG, `requestPermission failed: ${(e as Error).message}`);
      return false;
    }
  }

  /**
   * 解析公共下载目录下「以包名命名的应用专属子目录」可写路径，即 `<公共Download>/<bundleName>`。
   * 系统据此把该子目录归属到本应用，用户在文件管理中可见。
   * 失败（不支持 / 未授权 / 取不到路径）返回空串，调用方应回退沙箱。
   */
  static resolveDir(): string {
    if (!PublicDownloadDir.isSupported()) {
      return '';
    }
    try {
      const base: string = Environment.getUserDownloadDir();
      if (base === undefined || base === null || base.length === 0) {
        return '';
      }
      const bundle: string = AppStorage.get<string>(AppStorageKeys.BUNDLE_NAME) ?? '';
      return bundle.length > 0 ? `${base}/${bundle}` : base;
    } catch (e) {
      Logger.w(TAG, `getUserDownloadDir failed: ${(e as Error).message}`);
      return '';
    }
  }
}
