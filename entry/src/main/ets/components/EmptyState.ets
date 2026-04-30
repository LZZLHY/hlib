/*
 * EmptyState.ets
 * 空状态 / 错误占位通用组件。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppSpace } from '../theme/AppTextStyles';

@Component
export struct EmptyState {
  @Prop icon: Resource = $r('app.media.ic_empty_books');
  @Prop title: ResourceStr = '';
  @Prop message: ResourceStr = '';
  actionLabel?: ResourceStr;
  onAction: () => void = (): void => {};

  build() {
    Column({ space: 12 }) {
      Image(this.icon)
        .width(56)
        .height(56)
        .objectFit(ImageFit.Contain);

      Text(this.title)
        .fontSize(AppFontSize.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
        .textAlign(TextAlign.Center);

      Text(this.message)
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textSecondary)
        .textAlign(TextAlign.Center);

      if (this.actionLabel !== undefined) {
        Button(this.actionLabel)
          .height(40)
          .padding({ left: 24, right: 24 })
          .backgroundColor(AppColors.brandPrimaryLight)
          .fontColor(AppColors.brandPrimary)
          .fontSize(AppFontSize.bodySm)
          .borderRadius(20)
          .margin({ top: 8 })
          .onClick(() => this.onAction());
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding(AppSpace.s32)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center);
  }
}
