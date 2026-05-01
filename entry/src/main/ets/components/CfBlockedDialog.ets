/*
 * CfBlockedDialog.ets
 * Cloudflare 拦截统一提示。一键打开线路选择。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';

@CustomDialog
export struct CfBlockedDialog {
  controller?: CustomDialogController;
  onSwitchLine: () => void = (): void => {};

  build() {
    Column({ space: 16 }) {
      Image($r('app.media.startIcon'))
        .width(48)
        .height(48)
        .opacity(0.4);

      Text($r('app.string.login_cf_blocked_title'))
        .fontSize(AppFontSize.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary);

      Text($r('app.string.login_cf_blocked_desc'))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textSecondary)
        .textAlign(TextAlign.Center);

      Row({ space: 12 }) {
        Button($r('app.string.common_close'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(AppColors.surfaceAlt)
          .fontColor(AppColors.textPrimary)
          .borderRadius(AppRadius.pill)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
          });

        Button($r('app.string.settings_switch_line'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(AppColors.brandPrimary)
          .fontColor(AppColors.textOnPrimary)
          .borderRadius(AppRadius.pill)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onSwitchLine();
          });
      }
      .width('100%');
    }
    .padding(AppSpace.s24)
    .width('85%')
    .constraintSize({ maxWidth: 420 })
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.lg)
    .alignItems(HorizontalAlign.Center);
  }
}
