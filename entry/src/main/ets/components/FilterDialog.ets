/*
 * FilterDialog.ets
 *
 * 搜索筛选弹窗：单选式语言/排序/格式三组 chip。
 * 与 SearchOptions 的映射：
 *   languageKey === 'all' -> languages: undefined
 *   orderKey === 'default' -> order: undefined
 *   extensionKey === 'all' -> extensions: undefined
 *
 * onApply 携带 3 个 key（'all'/'default' 表示未选）。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { LANGUAGE_FILTERS, ORDER_FILTERS, EXTENSION_FILTERS, FilterItem } from '../api/SearchFilters';

@Component
struct FilterChip {
  label: ResourceStr = '';
  @Prop selected: boolean = false;
  onTap: () => void = (): void => {};

  build() {
    Button(this.label)
      .height(34)
      .padding({ left: 14, right: 14 })
      .fontSize(AppFontSize.bodySm)
      .fontColor(this.selected ? AppColors.textOnPrimary : AppColors.textPrimary)
      .backgroundColor(this.selected ? AppColors.brandPrimary : AppColors.surfaceAlt)
      .borderRadius(AppRadius.pill)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => this.onTap());
  }
}

export interface FilterValues {
  language: string;
  order: string;
  extension: string;
}

@CustomDialog
export struct FilterDialog {
  controller?: CustomDialogController;
  initial: FilterValues = { language: 'all', order: 'default', extension: 'all' };
  onApply: (values: FilterValues) => void = (_: FilterValues): void => {};

  @State private language: string = 'all';
  @State private order: string = 'default';
  @State private extension: string = 'all';

  aboutToAppear(): void {
    this.language = this.initial.language;
    this.order = this.initial.order;
    this.extension = this.initial.extension;
  }

  private apply(): void {
    const v: FilterValues = {
      language: this.language,
      order: this.order,
      extension: this.extension,
    };
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onApply(v);
  }

  private reset(): void {
    this.language = 'all';
    this.order = 'default';
    this.extension = 'all';
  }

  // ── Builder ──

  @Builder
  private langSection() {
    Column({ space: 8 }) {
      Text($r('app.string.search_filter_language'))
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textSecondary)
        .alignSelf(ItemAlign.Start);
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        ForEach(LANGUAGE_FILTERS, (item: FilterItem) => {
          FilterChip({
            label: item.label,
            selected: this.language === item.key,
            onTap: (): void => { this.language = item.key; },
          });
        }, (item: FilterItem) => `lang_${item.key}`);
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private orderSection() {
    Column({ space: 8 }) {
      Text($r('app.string.search_filter_order'))
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textSecondary)
        .alignSelf(ItemAlign.Start);
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        ForEach(ORDER_FILTERS, (item: FilterItem) => {
          FilterChip({
            label: item.label,
            selected: this.order === item.key,
            onTap: (): void => { this.order = item.key; },
          });
        }, (item: FilterItem) => `ord_${item.key}`);
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private extSection() {
    Column({ space: 8 }) {
      Text($r('app.string.search_filter_format'))
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textSecondary)
        .alignSelf(ItemAlign.Start);
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        ForEach(EXTENSION_FILTERS, (item: FilterItem) => {
          FilterChip({
            label: item.label,
            selected: this.extension === item.key,
            onTap: (): void => { this.extension = item.key; },
          });
        }, (item: FilterItem) => `ext_${item.key}`);
      }
      .width('100%');
    }
    .width('100%');
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text($r('app.string.search_filter'))
          .fontSize(AppFontSize.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1);

        Text($r('app.string.search_clear'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.brandPrimary)
          .onClick(() => this.reset());
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 });

      Scroll() {
        Column({ space: 16 }) {
          this.langSection();
          this.orderSection();
          this.extSection();
        }
        .padding({ left: 20, right: 20, top: 8, bottom: 16 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);

      // 底部应用按钮
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
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

        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(AppColors.brandPrimary)
          .fontColor(AppColors.textOnPrimary)
          .borderRadius(AppRadius.pill)
          .onClick(() => this.apply());
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 16 });
    }
    .width('92%')
    .height('72%')
    .backgroundColor('#E6FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thick, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    })
    .borderRadius(AppRadius.lg);
  }
}
