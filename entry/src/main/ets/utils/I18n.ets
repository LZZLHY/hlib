/*
 * I18n.ets
 * 简易国际化工具：
 *   - 默认全部走 ArkUI Resource（$r('app.string.xxx')），由系统自动按 locale 选取。
 *   - 提供 t(key) 快捷方法返回 Resource，组件直接传给 Text 即可。
 *   - 提供 ts(key) 同步取出实际字符串（少数场景需要拼接，例如 promptAction.showToast）。
 *     依赖 EntryAbility 在 onCreate 时调用 I18n.bindContext(this.context) 注入 ApplicationContext。
 *   - 提供 isZh() 判断当前是否中文（用于含中文/英文条件分支的极少数 UI 文案）。
 *
 * 用法：
 *   Text(I18n.t('login_welcome'))
 *   promptAction.showToast({ message: I18n.ts('common_loading') })
 */

import { i18n } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';

export class I18n {
  /** EntryAbility 注入；用于无参 ts(key) / format(key) 取字符串。 */
  private static appContext: common.Context | null = null;

  /** 由 EntryAbility.onCreate 调用，注入 ApplicationContext 供后续静态方法用。 */
  static bindContext(ctx: common.Context): void {
    I18n.appContext = ctx;
  }

  /** 返回 Resource 引用（推荐用法） */
  static t(key: string): Resource {
    return $r(`app.string.${key}`);
  }

  /**
   * 同步取出实际字符串。
   * 优先用 bindContext 注入的全局 context；缺失时返回 fallback 或 key。
   */
  static ts(key: string, fallback?: string): string {
    const ctx: common.Context | null = I18n.appContext;
    if (ctx === null) {
      return fallback !== undefined ? fallback : key;
    }
    try {
      const value: string = ctx.resourceManager.getStringByNameSync(key);
      return value.length > 0 ? value : (fallback !== undefined ? fallback : key);
    } catch {
      return fallback !== undefined ? fallback : key;
    }
  }

  /**
   * 取格式化字符串：自动用全局 context 解析模板，按顺序填充 args。
   * 支持 %s / %d 占位符（与 string.json 中 fmt 后缀的资源一致）。
   * 缺失 context 时回退到 fallback；若 fallback 仍空则返回 key。
   */
  static format(key: string, args: Array<string | number>, fallback?: string): string {
    const tmpl: string = I18n.ts(key, fallback);
    return I18n.applyArgs(tmpl, args);
  }

  /** 把 %s/%d/%f 占位符按顺序替换；多余占位符保持原样，多余 args 忽略。 */
  private static applyArgs(template: string, args: Array<string | number>): string {
    if (args.length === 0) {
      return template;
    }
    let i: number = 0;
    return template.replace(/%[sdf]/g, (match: string): string => {
      if (i >= args.length) {
        return match;
      }
      const v: string | number = args[i];
      i = i + 1;
      return String(v);
    });
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
