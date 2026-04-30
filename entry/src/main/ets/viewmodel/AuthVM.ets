/*
 * AuthVM.ets
 *
 * 鉴权门面：将登录/Token/退登/恢复 4 个动作集中起来，
 * - 调 ZLibraryClient 完成网络请求；
 * - 写入 AuthStore 持久化；
 * - 报出当前用户到 AppStorage[USER]，UI 通过 @StorageProp 订阅。
 *
 * 不做 UI 状态（loading/error）—— 这些由调用页面用 @State 自行管理。
 */

import { User } from '../model/User';
import { ZLibraryClient } from '../api/ZLibraryClient';
import { HttpClient } from '../api/HttpClient';
import { AuthStore, SavedAccount } from '../storage/AuthStore';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { PreferencesStore } from '../storage/PreferencesStore';
import { Logger } from '../utils/Logger';

const TAG: string = 'AuthVM';

export class AuthVM {
  /** 邮箱 + 密码登录。 */
  static async login(email: string, password: string): Promise<User> {
    const user: User = await ZLibraryClient.instance.login(email, password);
    const account: SavedAccount = {
      userId: user.id,
      userKey: user.remixUserkey,
      email: user.email,
      name: user.name,
      password: password,
    };
    await AuthStore.saveCredentials(account);
    AppStorage.setOrCreate<User>(AppStorageKeys.USER, user);
    await AuthVM.applyAccountLanguageIfUnset(user);
    Logger.i(TAG, `login ok user=${user.id}`);
    return user;
  }

  /** Token 登录（remix_userid + remix_userkey）。 */
  static async loginWithToken(userId: string, userKey: string): Promise<User> {
    const user: User = await ZLibraryClient.instance.loginWithToken(userId, userKey);
    const account: SavedAccount = {
      userId: userId,
      userKey: userKey,
      email: user.email,
      name: user.name,
    };
    await AuthStore.saveCredentials(account);
    AppStorage.setOrCreate<User>(AppStorageKeys.USER, user);
    await AuthVM.applyAccountLanguageIfUnset(user);
    Logger.i(TAG, `token login ok user=${user.id}`);
    return user;
  }

  /**
   * 当用户尚未显式设置 CONTENT_LANG 偏好时，把账号 profile 的 language 同步给 HttpClient，
   * 让首次登录的首页热门 / 近期就匹配账号语言（与 zlib 官方 app 一致）。
   * 不写入 PreferencesStore，保留用户随时切换的能力——一旦用户在设置里手动切换，那次写盘后此 helper 不再覆盖。
   */
  private static async applyAccountLanguageIfUnset(user: User): Promise<void> {
    const lang: string | undefined = user.language;
    if (lang === undefined || lang.length === 0) {
      return;
    }
    const explicit: string = await PreferencesStore.getString('settings', AppStorageKeys.CONTENT_LANG, '');
    if (explicit.length > 0) {
      // 用户已显式选择，尊重其偏好
      return;
    }
    HttpClient.instance.setSiteLanguage(lang);
    Logger.i(TAG, `auto-applied account language: ${lang}`);
  }

  /** 仅注入凭证，不发请求；用于"切换账号"快路径。 */
  static async switchToAccount(account: SavedAccount): Promise<User> {
    return await AuthVM.loginWithToken(account.userId, account.userKey);
  }

  /** 退登：清空 cookie / AuthStore / AppStorage[USER] / 站点语言偏好（切账号防残留）。 */
  static async logout(): Promise<void> {
    ZLibraryClient.instance.logout();
    await AuthStore.clearCredentials();
    AppStorage.setOrCreate<User | null>(AppStorageKeys.USER, null);
    // 重置 HttpClient.siteLanguage 到当前显式偏好（无则空），避免上一账号 profile 语言污染下次登录
    const explicit: string = await PreferencesStore.getString('settings', AppStorageKeys.CONTENT_LANG, '');
    HttpClient.instance.setSiteLanguage(explicit);
    Logger.i(TAG, 'logout');
  }

  /**
   * 启动时调用：若本地有 cookie，且服务端依然认账，把 USER 写回 AppStorage；
   * 否则返回 null，由调用方决定是否跳转 LoginPage。
   * 失败不抛异常。
   */
  static async restoreFromStorage(): Promise<User | null> {
    const cred: SavedAccount | null = await AuthStore.getCredentials();
    if (cred === null) {
      return null;
    }
    try {
      const user: User = await ZLibraryClient.instance.loginWithToken(cred.userId, cred.userKey);
      AppStorage.setOrCreate<User>(AppStorageKeys.USER, user);
      await AuthVM.applyAccountLanguageIfUnset(user);
      Logger.i(TAG, `restored user=${user.id}`);
      return user;
    } catch (err) {
      const e: Error = err as Error;
      Logger.w(TAG, `restore failed: ${e.message}`);
      return null;
    }
  }

  /** AppStorage 同步快照。 */
  static currentUser(): User | null {
    const u: User | null | undefined = AppStorage.get<User | null>(AppStorageKeys.USER);
    return u !== undefined && u !== null ? u : null;
  }

  /** 仅本地是否存在凭证（不验证服务端）。 */
  static async hasSavedAccount(): Promise<boolean> {
    const cred: SavedAccount | null = await AuthStore.getCredentials();
    return cred !== null;
  }

  /** 账号列表 */
  static async listAccounts(): Promise<SavedAccount[]> {
    return await AuthStore.listAccounts();
  }
}
