/*
 * Layout.ets — 响应式布局工具（纯函数）
 *
 * 业务页面调用 Layout.gridCols(bp) / Layout.contentMaxWidth(bp) 等纯函数，
 * 拿到针对当前断点的合适数值。所有断点判定基于 EntryAbility 写入 AppStorage 的
 * `BREAKPOINT` 字符串（'sm'|'md'|'lg'|'xl'）。
 *
 * 断点定义（沿用华为官方）：
 *   sm: <600vp     手机竖屏
 *   md: 600–840    折叠展开 / 横屏手机
 *   lg: 840–1440   平板 / 大折叠
 *   xl: ≥1440      大平板横屏
 */

import { Breakpoint, NavStyle } from '../storage/AppStorageKeys';

export class Layout {
  /** 由屏宽（vp）派生断点字符串。 */
  static breakpointOf(widthVp: number): Breakpoint {
    if (widthVp < 600) return 'sm';
    if (widthVp < 840) return 'md';
    if (widthVp < 1440) return 'lg';
    return 'xl';
  }

  /** Book 宫格列数：sm=3, md=4, lg=5, xl=6。 */
  static gridCols(bp: Breakpoint): number {
    if (bp === 'sm') return 3;
    if (bp === 'md') return 4;
    if (bp === 'lg') return 5;
    return 6;
  }

  /** 内容容器最大宽度（vp）：sm 不限，md+ 限宽避免过宽行长。 */
  static contentMaxWidth(bp: Breakpoint): number {
    if (bp === 'sm') return -1; // 不限制；UI 层判断 <0 不施加
    if (bp === 'md') return 720;
    if (bp === 'lg') return 960;
    return 1080;
  }

  /** Dialog 最大宽度（vp）。 */
  static dialogMaxWidth(bp: Breakpoint): number {
    if (bp === 'sm') return 360;
    if (bp === 'md') return 420;
    if (bp === 'lg') return 480;
    return 520;
  }

  /** 页面左右 padding（vp）。 */
  static pagePadding(bp: Breakpoint): number {
    if (bp === 'sm') return 16;
    if (bp === 'md') return 24;
    if (bp === 'lg') return 32;
    return 40;
  }

  /** Reader 内容最大宽度（vp）：≥lg 时限制行长 720vp。 */
  static readerMaxWidth(bp: Breakpoint): number {
    if (bp === 'sm' || bp === 'md') return -1;
    if (bp === 'lg') return 720;
    return 800;
  }

  /** 内容容器 ConstraintSizeOptions；sm 不限制返回空对象。 */
  static contentConstraint(bp: Breakpoint): ConstraintSizeOptions {
    const w: number = Layout.contentMaxWidth(bp);
    return w > 0 ? { maxWidth: w } : {};
  }

  /** 是否启用 BookDetail 双栏布局（≥md）。 */
  static useDetailTwoColumn(bp: Breakpoint): boolean {
    return bp !== 'sm';
  }

  /** 是否启用 Settings 双列布局（≥lg）。 */
  static useSettingsTwoColumn(bp: Breakpoint): boolean {
    return bp === 'lg' || bp === 'xl';
  }

  /** 搜索结果是否双列展示（≥md）。 */
  static useResultTwoColumn(bp: Breakpoint): boolean {
    return bp !== 'sm';
  }

  /**
   * 决定最终导航样式：
   *   - 用户偏好为 'bottom' / 'side' 时直接遵从（但 sm 强制底栏）
   *   - 'auto'：sm/md → bottom，lg/xl → side
   */
  static resolveNavStyle(bp: Breakpoint, pref: NavStyle): 'bottom' | 'side' {
    if (bp === 'sm') return 'bottom'; // 手机绝不上侧栏
    if (pref === 'side') return 'side';
    if (pref === 'bottom') return 'bottom';
    // auto
    if (bp === 'lg' || bp === 'xl') return 'side';
    return 'bottom';
  }

  /** 当前断点是否允许显示"导航样式切换"设置项（仅 ≥md）。 */
  static showNavStyleSwitch(bp: Breakpoint): boolean {
    return bp !== 'sm';
  }
}
