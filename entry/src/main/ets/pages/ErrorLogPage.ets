/*
 * ErrorLogPage.ets
 *
 * P7 诊断：展示 ErrorReportStore 中持久化的错误记录。
 *   - 顶栏：返回 + "错误日志" + "清空"按钮
 *   - 列表：时间 + tag + message（可展开 stack）
 *   - 空态：友好提示
 */

import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { ErrorReportStore, ErrorReport } from '../storage/ErrorReportStore';
import { EmptyState } from '../components/EmptyState';
import { AppRouter } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'ErrorLogPage';

@Component
export struct ErrorLogPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State private reports: ErrorReport[] = [];
  @State private expanded: Set<number> = new Set<number>();

  aboutToAppear(): void {
    this.reports = ErrorReportStore.getAll();
  }

  private toggle(idx: number): void {
    const next: Set<number> = new Set<number>(this.expanded);
    if (next.has(idx)) {
      next.delete(idx);
    } else {
      next.add(idx);
    }
    this.expanded = next;
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.settings_error_log_clear'),
      message: '',
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.common_ok'),
        fontColor: '#E53935',
        action: (): void => {
          ErrorReportStore.clear()
            .then((): void => {
              this.reports = [];
              this.expanded = new Set<number>();
              ErrorLogPage.toast($r('app.string.settings_error_log_cleared'));
            })
            .catch((e: Error): void => {
              Logger.w(TAG, `clear failed: ${e.message}`);
              ErrorLogPage.toast(`清除失败：${e.message}`);
            });
        },
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        fontColor: '#666666',
        action: (): void => {},
      },
    });
  }

  private static toast(msg: ResourceStr): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 1500 };
      promptAction.openToast(opts);
    } catch {
      // ignore
    }
  }

  @Builder
  private topBar() {
    Column() {
      Blank().height(this.statusBarHeight)
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_back')).width(20).height(20);
        }
        .width(40)
        .height(40)
        .backgroundColor(AppColors.surfaceAlt)
        .onClick(() => AppRouter.pop());

        Text($r('app.string.settings_error_log'))
          .fontSize(AppFontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
          .margin({ left: 12 });

        if (this.reports.length > 0) {
          Button($r('app.string.settings_error_log_clear'))
            .height(36)
            .padding({ left: 12, right: 12 })
            .backgroundColor(AppColors.surfaceAlt)
            .fontColor(AppColors.error)
            .fontSize(AppFontSize.bodySm)
            .borderRadius(18)
            .onClick(() => this.confirmClear());
        }
      }
      .width('100%')
      .padding(AppSpace.s16)
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    });
  }

  @Builder
  private reportItem(idx: number, item: ErrorReport) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(ErrorLogPage.formatTime(item.ts))
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.textTertiary);
        Text(item.tag)
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.brandPrimary)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(AppColors.brandPrimaryLight)
          .borderRadius(4);
        Blank();
      }
      .width('100%');

      Text(item.message)
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textPrimary)
        .maxLines(this.expanded.has(idx) ? 99 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');

      if (this.expanded.has(idx) && item.stack !== undefined && item.stack.length > 0) {
        Text(item.stack)
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.textSecondary)
          .width('100%')
          .padding(8)
          .backgroundColor(AppColors.bgCanvas)
          .borderRadius(4);
      }
    }
    .width('100%')
    .padding(AppSpace.s12)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => this.toggle(idx));
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar();

        if (this.reports.length === 0) {
          EmptyState({
            icon: $r('app.media.ic_empty_log'),
            title: $r('app.string.settings_error_log_empty'),
            message: '',
          });
        } else {
          List({ space: 10 }) {
            ForEach(this.reports, (item: ErrorReport, idx: number) => {
              ListItem() {
                this.reportItem(idx, item);
              }
            }, (item: ErrorReport, idx: number) => `${item.ts}_${idx}`);

            ListItem().height(40);
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: AppSpace.s16, right: AppSpace.s16 })
          .scrollBar(BarState.Off);
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  private static formatTime(iso: string): string {
    if (iso.length === 0) return '';
    try {
      const d: Date = new Date(iso);
      const m: number = d.getMonth() + 1;
      const day: number = d.getDate();
      const hh: string = d.getHours().toString().padStart(2, '0');
      const mm: string = d.getMinutes().toString().padStart(2, '0');
      const ss: string = d.getSeconds().toString().padStart(2, '0');
      return `${m}/${day} ${hh}:${mm}:${ss}`;
    } catch {
      return iso;
    }
  }
}
