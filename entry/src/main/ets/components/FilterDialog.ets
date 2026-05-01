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
  /** 0 表示不筛选，否则 1800..当前年 范围内的整数。 */
  yearFrom: number;
  yearTo: number;
}

@CustomDialog
export struct FilterDialog {
  controller?: CustomDialogController;
  initial: FilterValues = { language: 'all', order: 'default', extension: 'all', yearFrom: 0, yearTo: 0 };
  onApply: (values: FilterValues) => void = (_: FilterValues): void => {};

  @State private language: string = 'all';
  @State private order: string = 'default';
  @State private extension: string = 'all';
  @State private yearFromStr: string = '';
  @State private yearToStr: string = '';
  @State private yearError: boolean = false;

  aboutToAppear(): void {
    this.language = this.initial.language;
    this.order = this.initial.order;
    this.extension = this.initial.extension;
    this.yearFromStr = this.initial.yearFrom > 0 ? String(this.initial.yearFrom) : '';
    this.yearToStr = this.initial.yearTo > 0 ? String(this.initial.yearTo) : '';
  }

  /** 解析年份字符串；非正整数、<=0 返回 0；否则限制在 [1000, 2999]。 */
  private parseYear(s: string): number {
    const t: string = s.trim();
    if (t.length === 0) return 0;
    const n: number = parseInt(t, 10);
    if (!Number.isFinite(n) || n <= 0) return 0;
    if (n < 1000) return 1000;
    if (n > 2999) return 2999;
    return n;
  }

  private apply(): void {
    const from: number = this.parseYear(this.yearFromStr);
    const to: number = this.parseYear(this.yearToStr);
    // 仅当两端都填才要求顺序；只填一端仍然放行
    if (from > 0 && to > 0 && from > to) {
      this.yearError = true;
      return;
    }
    this.yearError = false;
    const v: FilterValues = {
      language: this.language,
      order: this.order,
      extension: this.extension,
      yearFrom: from,
      yearTo: to,
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
    this.yearFromStr = '';
    this.yearToStr = '';
    this.yearError = false;
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

  @Builder
  private yearSection() {
    Column({ space: 8 }) {
      Text($r('app.string.search_filter_year'))
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textSecondary)
        .alignSelf(ItemAlign.Start);

      Row({ space: 8 }) {
        TextInput({ placeholder: $r('app.string.search_year_hint_from'), text: this.yearFromStr })
          .type(InputType.Number)
          .height(40)
          .layoutWeight(1)
          .borderRadius(AppRadius.sm)
          .backgroundColor(AppColors.surfaceAlt)
          .fontSize(AppFontSize.bodySm)
          .borderWidth(this.yearError ? 1 : 0)
          .borderColor(AppColors.error)
          .onChange((v: string): void => {
            this.yearFromStr = v;
            if (this.yearError) this.yearError = false;
          });

        Text('—')
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textTertiary);

        TextInput({ placeholder: $r('app.string.search_year_hint_to'), text: this.yearToStr })
          .type(InputType.Number)
          .height(40)
          .layoutWeight(1)
          .borderRadius(AppRadius.sm)
          .backgroundColor(AppColors.surfaceAlt)
          .fontSize(AppFontSize.bodySm)
          .borderWidth(this.yearError ? 1 : 0)
          .borderColor(AppColors.error)
          .onChange((v: string): void => {
            this.yearToStr = v;
            if (this.yearError) this.yearError = false;
          });
      }
      .width('100%');

      if (this.yearError) {
        Text($r('app.string.search_year_invalid'))
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.error)
          .alignSelf(ItemAlign.Start);
      }
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
          this.yearSection();
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
    .constraintSize({ maxWidth: 520 })
    .backgroundColor('#E6FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thick, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    })
    .borderRadius(AppRadius.lg);
  }
}
