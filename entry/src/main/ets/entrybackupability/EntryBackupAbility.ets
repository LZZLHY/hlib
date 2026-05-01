/*
 * EntryBackupAbility.ets
 *
 * HarmonyOS BackupExtensionAbility 入口。
 * 本应用仅做沙箱全量备份 / 恢复（由系统在 backup_config.json 中声明 allowToBackupRestore），
 * 这里不做额外处理——系统会自动打包 context.filesDir / databaseDir。
 * 仅负责在关键时刻打一条业务 hilog 作为回溯。
 */

import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { Logger } from '../utils/Logger';

const TAG: string = 'EntryBackupAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    Logger.i(TAG, 'onBackup start');
    try {
      // 预留：如需清理临时文件可在此处理
      await Promise.resolve();
    } catch (e) {
      Logger.w(TAG, `onBackup failed: ${(e as Error).message}`);
    }
    Logger.i(TAG, 'onBackup ok');
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    Logger.i(TAG, `onRestore start from version=${JSON.stringify(bundleVersion)}`);
    try {
      await Promise.resolve();
    } catch (e) {
      Logger.w(TAG, `onRestore failed: ${(e as Error).message}`);
    }
    Logger.i(TAG, 'onRestore ok');
  }
}