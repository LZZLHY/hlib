/*
 * AppTextStyles.ets
 * 字号 / 圆角 / 间距 token 的薄包装。所有原始值定义在 resources/base/element/float.json。
 */

export class AppFontSize {
  static readonly caption: Resource  = $r('app.float.fs_caption');   // 11
  static readonly overline: Resource = $r('app.float.fs_overline');  // 10
  static readonly bodySm: Resource   = $r('app.float.fs_body_sm');   // 12
  static readonly body: Resource     = $r('app.float.fs_body');      // 14
  static readonly bodyLg: Resource   = $r('app.float.fs_body_lg');   // 16
  static readonly titleSm: Resource  = $r('app.float.fs_title_sm');  // 15
  static readonly title: Resource    = $r('app.float.fs_title');     // 18
  static readonly titleLg: Resource  = $r('app.float.fs_title_lg');  // 20
  static readonly headline: Resource = $r('app.float.fs_headline');  // 24
  static readonly display: Resource  = $r('app.float.fs_display');   // 28
}

export class AppRadius {
  static readonly sm: Resource   = $r('app.float.radius_sm');   // 8
  static readonly md: Resource   = $r('app.float.radius_md');   // 12
  static readonly lg: Resource   = $r('app.float.radius_lg');   // 16
  static readonly xl: Resource   = $r('app.float.radius_xl');   // 20
  static readonly pill: Resource = $r('app.float.radius_pill'); // 30
}

export class AppSpace {
  static readonly s2: Resource  = $r('app.float.space_2');
  static readonly s4: Resource  = $r('app.float.space_4');
  static readonly s6: Resource  = $r('app.float.space_6');
  static readonly s8: Resource  = $r('app.float.space_8');
  static readonly s12: Resource = $r('app.float.space_12');
  static readonly s16: Resource = $r('app.float.space_16');
  static readonly s20: Resource = $r('app.float.space_20');
  static readonly s24: Resource = $r('app.float.space_24');
  static readonly s32: Resource = $r('app.float.space_32');
}
