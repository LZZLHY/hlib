/*
 * PublicDirAccess.ets — 公共目录（用户选择的下载文件夹）持久化写入授权
 *
 * 背景（HarmonyOS 文件访问框架）：
 *   - 通过 DocumentViewPicker 让用户选择的目录，返回的是 file:// URI，默认仅临时授权，
 *     应用重启后失效。
 *   - 要「一次授权、长期有效」，需声明 ohos.permission.FILE_ACCESS_PERSIST，
 *     选中后调 fileShare.persistPermission 持久化；之后每次写入前调 fileShare.activatePermission 唤醒。
 *   - 文件夹选择能力仅 PC / 2in1 提供（canIUse FolderAuthorization）；手机 / 平板只能用沙箱目录。
 *   - 媒体类 URI（file://media/...）不支持 persistPermission，此处只处理普通 file:// 目录 URI。
 *
 * 内容依据华为官方文件访问框架文档整理改写（已按授权要求改写）。
 */

import { fileShare } from '@kit.CoreFileKit';
import { Logger } from './Logger';

const TAG: string = 'PublicDirAccess';

export class PublicDirAccess {
  /** 设备是否支持文件夹授权（PC / 2in1）。 */
  static isSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
  }

  /** 是否是需要持久化授权管理的公共目录 URI（file://，非沙箱明文路径）。 */
  static isManagedUri(path: string): boolean {
    return path.startsWith('file://') && path.indexOf('file://media') !== 0;
  }

  /** 持久化某目录 URI 的写入授权。成功返回 true。永不抛异常。 */
  static async persistWrite(uri: string): Promise<boolean> {
    if (!PublicDirAccess.isManagedUri(uri)) {
      return false;
    }
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.WRITE_MODE,
      };
      const policies: Array<fileShare.PolicyInfo> = [policy];
      await fileShare.persistPermission(policies);
      Logger.i(TAG, 'persistPermission ok');
      return true;
    } catch (e) {
      Logger.w(TAG, `persistPermission failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 唤醒已持久化的目录写入授权（写文件前调用）。成功返回 true。永不抛异常。 */
  static async activateWrite(uri: string): Promise<boolean> {
    if (!PublicDirAccess.isManagedUri(uri)) {
      return false;
    }
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.WRITE_MODE,
      };
      const policies: Array<fileShare.PolicyInfo> = [policy];
      await fileShare.activatePermission(policies);
      Logger.i(TAG, 'activatePermission ok');
      return true;
    } catch (e) {
      Logger.w(TAG, `activatePermission failed: ${(e as Error).message}`);
      return false;
    }
  }
}
