/*
 * PrivacyPage.ets
 *
 * 隐私政策与用户协议。所有正文走 string.json，按 locale 自动选择中英。
 * 商店审核基本必备项：声明数据收集范围 / 权限用途 / 免责声明。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys, Breakpoint } from '../storage/AppStorageKeys';
import { Layout } from '../utils/Layout';
import { AppRouter } from '../utils/AppRouter';

@Component
export struct PrivacyPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp(AppStorageKeys.BREAKPOINT) bp: Breakpoint = 'sm';

  /**
   * 页面卸载时写时间戳给 SplashPage 等待方使用：
   * 它们通过 @StorageProp + @Watch(PRIVACY_PAGE_CLOSED_AT) 检测此变化以恢复 UI（如重新拉起同意弹窗）。
   */
  aboutToDisappear(): void {
    AppStorage.setOrCreate<number>(AppStorageKeys.PRIVACY_PAGE_CLOSED_AT, Date.now());
  }

  @Builder
  private topBar() {
    Column() {
      Blank().height(this.statusBarHeight)
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_back')).width(22).height(22);
        }
        .width(40)
        .height(40)
        .backgroundColor(AppColors.surfaceAlt)
        .onClick(() => AppRouter.pop());

        Text($r('app.string.privacy_title'))
          .fontSize(AppFontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    });
  }

  @Builder
  private section(titleKey: string, bodyKey: string) {
    Column({ space: 8 }) {
      Text($r(`app.string.${titleKey}`))
        .fontSize(AppFontSize.bodyLg)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start);
      Text($r(`app.string.${bodyKey}`))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textSecondary)
        .lineHeight(22);
    }
    .width('100%')
    .padding(AppSpace.s16)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar();

        Scroll() {
          Column({ space: 12 }) {
            // 生效日期 —— 国标要求显著位置
            Text($r('app.string.privacy_effective_date'))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary)
              .alignSelf(ItemAlign.Start);

            // 国标 GB/T 35273-2020 附录 D 11 节结构（概述 + 9 大模块 + 联系）
            this.section('privacy_section_overview', 'privacy_overview_body');
            this.section('privacy_section_controller', 'privacy_controller_body');
            this.section('privacy_section_data', 'privacy_data_body');
            this.section('privacy_section_permissions', 'privacy_permissions_body');
            this.section('privacy_section_share', 'privacy_share_body');
            this.section('privacy_section_security', 'privacy_security_body');
            this.section('privacy_section_rights', 'privacy_rights_body');
            this.section('privacy_section_minors', 'privacy_minors_body');
            this.section('privacy_section_disclaimer', 'privacy_disclaimer_body');
            this.section('privacy_section_changes', 'privacy_changes_body');
            this.section('privacy_section_contact', 'privacy_contact_body');

            Blank().height(40);
          }
          .width('100%')
          .padding({ left: Layout.pagePadding(this.bp), right: Layout.pagePadding(this.bp), top: AppSpace.s16 });
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
