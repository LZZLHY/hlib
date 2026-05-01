/*
 * PrivacyConsentDialog.ets
 *
 * 首次启动 / 政策版本变更后的隐私政策同意弹窗（合规阻塞性必备）。
 *
 * 依据：
 *   - GB/T 35273-2020《信息安全技术 个人信息安全规范》——同意机制
 *   - 华为应用市场审核指南 7.x——隐私政策可便捷查看 + 显式同意
 *   - 个人信息保护法（PIPL）——明示同意 + 撤回同意权利
 *
 * 行为：
 *   - autoCancel = false（不可点击外部关闭）
 *   - 仅"同意"或"不同意"两路出口，"不同意" → onDecline → 调用方应 terminateSelf 退出 App
 *   - 提供"查看完整政策"按钮跳转 PrivacyPage（不会关闭弹窗）
 *
 * 使用：
 *   const ctrl = new CustomDialogController({
 *     builder: PrivacyConsentDialog({
 *       onAgree: () => { ... 写入 PRIVACY_AGREED_VERSION 后启动 bootstrap ... },
 *       onDecline: () => { ... terminateSelf ... },
 *     }),
 *     autoCancel: false,
 *     alignment: DialogAlignment.Center,
 *     customStyle: true,
 *   });
 *   ctrl.open();
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';

@CustomDialog
export struct PrivacyConsentDialog {
  controller?: CustomDialogController;
  onAgree: () => void = (): void => {};
  onDecline: () => void = (): void => {};
  /** 点击"查看完整政策"时回调；调用方应在此关闭弹窗 + 跳转 PrivacyPage。 */
  onViewFull: () => void = (): void => {};

  build() {
    Column({ space: AppSpace.s16 }) {
      // 标题
      Text($r('app.string.privacy_consent_title'))
        .fontSize(AppFontSize.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start);

      // 生效日期
      Text($r('app.string.privacy_effective_date'))
        .fontSize(AppFontSize.caption)
        .fontColor(AppColors.textTertiary)
        .alignSelf(ItemAlign.Start);

      // 摘要正文（限高 + 滚动，避免在小屏被按钮挤掉）
      Scroll() {
        Text($r('app.string.privacy_consent_intro'))
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textSecondary)
          .lineHeight(22)
          .width('100%');
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Auto);

      // 「查看完整政策」次级按钮
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text($r('app.string.privacy_consent_view_full'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.brandPrimary);
      }
      .width('100%')
      .height(40)
      .backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.pill)
      .border({ width: 1, color: AppColors.brandPrimary })
      .onClick(() => {
        // 关闭弹窗后由调用方推 PrivacyPage（避免弹窗遮罩盖住完整政策页内容）；
        // 用户从 PrivacyPage 返回时，调用方需重新拉起本弹窗。
        if (this.controller !== undefined) {
          this.controller.close();
        }
        this.onViewFull();
      });

      // 同意 / 不同意 双按钮
      Row({ space: AppSpace.s12 }) {
        Button($r('app.string.privacy_consent_decline'))
          .layoutWeight(1)
          .height(48)
          .backgroundColor(AppColors.surfaceAlt)
          .fontColor(AppColors.textPrimary)
          .fontSize(AppFontSize.body)
          .borderRadius(AppRadius.pill)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onDecline();
          });

        Button($r('app.string.privacy_consent_agree'))
          .layoutWeight(1)
          .height(48)
          .backgroundColor(AppColors.brandPrimary)
          .fontColor(AppColors.textOnPrimary)
          .fontSize(AppFontSize.body)
          .fontWeight(FontWeight.Bold)
          .borderRadius(AppRadius.pill)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onAgree();
          });
      }
      .width('100%');
    }
    .padding(AppSpace.s24)
    .width('92%')
    .constraintSize({ maxWidth: 520 })
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.lg)
    .alignItems(HorizontalAlign.Start);
  }
}
