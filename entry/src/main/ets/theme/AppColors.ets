/*
 * AppColors.ets
 * 主题色 token 的 TS 端薄包装。
 * 所有色值在 resources/base|dark/element/color.json 中定义；
 * 这里只暴露 Resource 引用，方便组件统一引用且可被 IDE 跳转。
 *
 * 用法： Text(...).fontColor(AppColors.textPrimary)
 */

export class AppColors {
  // ─── 品牌色 ───
  static readonly brandPrimary: Resource      = $r('app.color.brand_primary');
  static readonly brandPrimaryLight: Resource = $r('app.color.brand_primary_light');
  static readonly brandPrimaryDark: Resource  = $r('app.color.brand_primary_dark');

  // ─── 背景 / 表面 ───
  static readonly bgCanvas: Resource   = $r('app.color.bg_canvas');
  static readonly surface: Resource    = $r('app.color.surface');
  static readonly surfaceAlt: Resource = $r('app.color.surface_alt');

  // ─── 文本 ───
  static readonly textPrimary: Resource    = $r('app.color.text_primary');
  static readonly textSecondary: Resource  = $r('app.color.text_secondary');
  static readonly textTertiary: Resource   = $r('app.color.text_tertiary');
  static readonly textOnPrimary: Resource  = $r('app.color.text_on_primary');

  // ─── 辅助 / 状态 ───
  static readonly accentOrange: Resource = $r('app.color.accent_orange');
  static readonly successTeal: Resource  = $r('app.color.success_teal');
  static readonly warning: Resource      = $r('app.color.warning');
  static readonly error: Resource        = $r('app.color.error');

  // ─── 进度色（依完成度阶梯切换） ───
  static readonly progressGreen: Resource  = $r('app.color.progress_green');
  static readonly progressYellow: Resource = $r('app.color.progress_yellow');
  static readonly progressOrange: Resource = $r('app.color.progress_orange');

  // ─── 杂项 ───
  static readonly divider: Resource    = $r('app.color.divider');
  static readonly shadowCard: Resource = $r('app.color.shadow_card');
  static readonly scrim: Resource      = $r('app.color.scrim');
}
