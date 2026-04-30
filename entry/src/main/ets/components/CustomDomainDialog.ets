/*
 * CustomDomainDialog.ets
 * 自定义镜像域名输入弹窗。校验后回调 onConfirm。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';

@CustomDialog
export struct CustomDomainDialog {
  controller?: CustomDialogController;
  onConfirm: (domain: string) => void = (_: string): void => {};
  @State private input: string = '';
  @State private hasError: boolean = false;

  private commit(): void {
    const raw: string = this.input.trim();
    // 简单校验：包含至少一个点，去掉协议后纯字符
    const cleaned: string = raw.replace(/^https?:\/\//, '').replace(/\/$/, '');
    if (cleaned.length === 0 || cleaned.indexOf('.') < 0 || cleaned.indexOf(' ') >= 0) {
      this.hasError = true;
      return;
    }
    this.hasError = false;
    this.onConfirm(cleaned);
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.domain_custom_dialog_title'))
        .fontSize(AppFontSize.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary);

      Column({ space: 6 }) {
        Text($r('app.string.domain_custom_input_label'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textSecondary)
          .alignSelf(ItemAlign.Start);

        TextInput({ placeholder: $r('app.string.domain_custom_input_hint'), text: this.input })
          .height(48)
          .borderRadius(AppRadius.md)
          .backgroundColor(AppColors.surfaceAlt)
          .fontColor(AppColors.textPrimary)
          .placeholderColor(AppColors.textTertiary)
          .borderWidth(this.hasError ? 1 : 0)
          .borderColor(AppColors.error)
          .onChange((v: string) => {
            this.input = v;
            if (this.hasError) {
              this.hasError = false;
            }
          })
          .onSubmit(() => this.commit());

        if (this.hasError) {
          Text('域名格式不正确')
            .fontSize(AppFontSize.caption)
            .fontColor(AppColors.error)
            .alignSelf(ItemAlign.Start);
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);

      Row({ space: 12 }) {
        Button($r('app.string.domain_cancel'))
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

        Button($r('app.string.domain_save'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(AppColors.brandPrimary)
          .fontColor(AppColors.textOnPrimary)
          .borderRadius(AppRadius.pill)
          .onClick(() => this.commit());
      }
      .width('100%');
    }
    .padding(AppSpace.s24)
    .width('85%')
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.lg);
  }
}
