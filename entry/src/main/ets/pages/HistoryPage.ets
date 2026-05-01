/*
 * HistoryPage.ets — 下载历史完整版
 *
 * 与 DownloadsTab 已完成 Tab 类似，但单独成页方便从设置页快速访问，
 * 并提供搜索框过滤大量历史记录。
 *
 * 功能：
 *   - 列表 DownloadHistoryItem（按 downloadedAt 倒序，由 DownloadVM 维护）
 *   - 搜索框：标题 / 作者模糊匹配（本地过滤，零网络）
 *   - 单条操作：打开 / 分享 / 删除（确认对话框）
 *   - 空态：暂无下载历史 / 无搜索结果
 */

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys, Breakpoint } from '../storage/AppStorageKeys';
import { Layout } from '../utils/Layout';
import { DownloadHistoryItem } from '../storage/DownloadHistoryStore';
import { DownloadVM } from '../viewmodel/DownloadVM';
import { BookCoverImage } from '../components/BookCoverImage';
import { EmptyState } from '../components/EmptyState';
import { SearchBar } from '../components/SearchBar';
import { ErrorHelper } from '../utils/ErrorHelper';
import { I18n } from '../utils/I18n';
import { AppRouter } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'HistoryPage';

@Component
export struct HistoryPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp(AppStorageKeys.BREAKPOINT) bp: Breakpoint = 'sm';
  @StorageProp(AppStorageKeys.DOWNLOAD_HISTORY) private history: DownloadHistoryItem[] = [];
  @State private query: string = '';

  aboutToAppear(): void {
    DownloadVM.refreshHistory().catch((e: Error): void => {
      Logger.w(TAG, `refreshHistory failed: ${e.message}`);
    });
  }

  /** 当前应展示的项（按搜索词过滤）。 */
  private filtered(): DownloadHistoryItem[] {
    const list: DownloadHistoryItem[] = this.history !== null && this.history !== undefined
      ? this.history
      : [];
    const q: string = this.query.trim().toLowerCase();
    if (q.length === 0) {
      return list;
    }
    return list.filter((item: DownloadHistoryItem): boolean => {
      const title: string = item.title.toLowerCase();
      const author: string = item.author !== undefined ? item.author.toLowerCase() : '';
      return title.indexOf(q) >= 0 || author.indexOf(q) >= 0;
    });
  }

  private onOpen(item: DownloadHistoryItem): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    DownloadVM.openFile(item, ctx).catch((e: Error): void => {
      Logger.w(TAG, `openFile failed: ${e.message}`);
      HistoryPage.toast(ErrorHelper.describe(e as Object, 'ctx_open_file'));
    });
  }

  private onShare(item: DownloadHistoryItem): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    DownloadVM.shareFile(item, ctx).catch((e: Error): void => {
      Logger.w(TAG, `shareFile failed: ${e.message}`);
      HistoryPage.toast(ErrorHelper.describe(e as Object, 'ctx_share_file'));
    });
  }

  private onDelete(item: DownloadHistoryItem): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.downloads_delete_title'),
      message: $r('app.string.downloads_delete_desc'),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.common_delete'),
        fontColor: AppColors.error,
        action: (): void => {
          DownloadVM.removeHistory(item.bookId).catch((e: Error): void => {
            Logger.w(TAG, `removeHistory failed: ${e.message}`);
            HistoryPage.toast(ErrorHelper.describe(e as Object, 'ctx_remove_history'));
          });
        },
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        fontColor: AppColors.textSecondary,
        action: (): void => {},
      },
    });
  }

  private static toast(msg: string): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 1800 };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, `toast failed: ${(e as Error).message}`);
    }
  }

  // ── Builders ──

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

        Column() {
          Text($r('app.string.history_title'))
            .fontSize(AppFontSize.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary);
          if (this.history !== null && this.history !== undefined && this.history.length > 0) {
            Text(`${this.history.length} ${I18n.ts('history_count_unit')}`)
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary)
              .margin({ top: 2 });
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })

      // 搜索框：仅在有数据时展示
      if (this.history !== null && this.history !== undefined && this.history.length > 0) {
        Column() {
          SearchBar({
            text: $query,
            placeholder: $r('app.string.history_search_hint'),
            onSubmit: (_q: string): void => {
              // SearchBar.text 已通过双向绑定写入 this.query；onSubmit 不需要额外动作
            },
          });
        }
        .padding({ left: AppSpace.s16, right: AppSpace.s16, bottom: AppSpace.s8 });
      }
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    });
  }

  @Builder
  private historyItem(item: DownloadHistoryItem) {
    Row({ space: 12 }) {
      BookCoverImage({
        url: item.cover !== undefined ? item.cover : '',
        title: item.title,
        width_: 56,
        height_: 80,
        radius: 6,
      });

      Column({ space: 6 }) {
        Text(item.title)
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');

        if (item.author !== undefined && item.author.length > 0) {
          Text(item.author)
            .fontSize(AppFontSize.caption)
            .fontColor(AppColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }

        Row({ space: 6 }) {
          if (item.extension !== undefined && item.extension.length > 0) {
            Text(item.extension.toUpperCase())
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.brandPrimary)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(AppColors.brandPrimaryLight)
              .borderRadius(4);
          }
          if (item.filesize !== undefined && item.filesize > 0) {
            Text(HistoryPage.formatSize(item.filesize))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary);
          }
          Text(HistoryPage.formatDate(item.downloadedAt))
            .fontSize(AppFontSize.caption)
            .fontColor(AppColors.textTertiary);
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Column({ space: 4 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_open_file')).width(14).height(14);
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.brandPrimaryLight)
        .onClick(() => this.onOpen(item));

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_share')).width(14).height(14);
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.surfaceAlt)
        .onClick(() => this.onShare(item));

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_cancel')).width(14).height(14);
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.surfaceAlt)
        .onClick(() => this.onDelete(item));
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => this.onOpen(item));
  }

  @Builder
  private body() {
    if (this.history === null || this.history === undefined || this.history.length === 0) {
      EmptyState({
        icon: $r('app.media.ic_empty_books'),
        title: $r('app.string.history_empty_title'),
        message: $r('app.string.history_empty_msg'),
      });
    } else if (this.filtered().length === 0) {
      EmptyState({
        icon: $r('app.media.ic_empty_no_results'),
        title: $r('app.string.history_no_results'),
        message: $r('app.string.search_no_results_msg'),
      });
    } else {
      List({ space: 10 }) {
        ForEach(this.filtered(), (item: DownloadHistoryItem) => {
          ListItem() {
            this.historyItem(item);
          }
        }, (item: DownloadHistoryItem): string => item.bookId);

        ListItem().height(40);
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: AppSpace.s16, right: AppSpace.s16, top: AppSpace.s8 })
      .scrollBar(BarState.Off);
    }
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar();
        this.body();
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  // ── 静态工具 ──

  private static formatSize(bytes: number): string {
    if (bytes <= 0) return '—';
    const KB: number = 1024;
    const MB: number = 1024 * 1024;
    const GB: number = 1024 * 1024 * 1024;
    if (bytes >= GB) return `${(bytes / GB).toFixed(2)} GB`;
    if (bytes >= MB) return `${(bytes / MB).toFixed(1)} MB`;
    if (bytes >= KB) return `${(bytes / KB).toFixed(0)} KB`;
    return `${bytes} B`;
  }

  private static formatDate(iso: string): string {
    if (iso.length === 0) return '';
    return iso.slice(0, 10);
  }
}
