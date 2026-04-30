/*
 * I18n.ets
 * 简易国际化工具：
 *   - 默认全部走 ArkUI Resource（$r('app.string.xxx')），由系统自动按 locale 选取。
 *   - 提供 t(key) 快捷方法返回 Resource，组件直接传给 Text 即可。
 *   - 提供 ts(key) 同步取出实际字符串（少数场景需要拼接，例如 promptAction.showToast）。
 *   - 提供 isZh() 判断当前是否中文（用于含中文/英文条件分支的极少数 UI 文案）。
 *
 * 用法：
 *   Text(I18n.t('login_welcome'))
 *   promptAction.showToast({ message: I18n.ts('common_loading') })
 */

import { i18n } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';

export class I18n {
  /** 返回 Resource 引用（推荐用法） */
  static t(key: string): Resource {
    return $r(`app.string.${key}`);
  }

  /**
   * 同步取出实际字符串。需要 UIAbilityContext / ApplicationContext。
   * 若资源不存在，返回 fallback 或 key 本身。
   */
  static ts(context: common.Context, key: string, fallback?: string): string {
    try {
      const mgr = context.resourceManager;
      // 用 sync API；HarmonyOS 自 API 12 起支持
      const value = mgr.getStringByNameSync(key);
      return value ?? fallback ?? key;
    } catch {
      return fallback ?? key;
    }
  }

  /** 当前应用首选语言（与系统 locale 同步） */
  static currentLocale(): string {
    try {
      return i18n.System.getSystemLanguage();
    } catch {
      return 'zh-Hans';
    }
  }

  /** 是否中文环境 */
  static isZh(): boolean {
    const loc = I18n.currentLocale().toLowerCase();
    return loc.startsWith('zh');
  }
}
