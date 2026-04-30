/*
 * SearchBar.ets
 * 搜索输入框 + 清空按钮 + Submit 回调。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';

@Component
export struct SearchBar {
  @Link text: string;
  placeholder: ResourceStr = $r('app.string.search_hint');
  onSubmit: (q: string) => void = (_: string): void => {};

  build() {
    Row({ space: 8 }) {
      Image($r('app.media.ic_tab_search')).width(16).height(16).objectFit(ImageFit.Contain);

      TextInput({ placeholder: this.placeholder, text: this.text })
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .placeholderColor(AppColors.textTertiary)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .padding(0)
        .layoutWeight(1)
        .height(40)
        .onChange((v: string) => {
          this.text = v;
        })
        .onSubmit(() => {
          this.onSubmit(this.text.trim());
        });

      if (this.text.length > 0) {
        Button() {
          Image($r('app.media.ic_close')).width(14).height(14);
        }
        .width(28)
        .height(28)
        .backgroundColor(AppColors.surfaceAlt)
        .borderRadius(14)
        .onClick(() => {
          this.text = '';
        });
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: AppSpace.s12, right: AppSpace.s8 })
    .backgroundColor(AppColors.surfaceAlt)
    .borderRadius(AppRadius.pill);
  }
}
