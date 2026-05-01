/*
 * DownloadsTab.ets
 *
 * 下载 Tab：
 *   - 上半 Tabs：进行中 / 已完成
 *   - 进行中：DownloadTask[] 渲染（进度条 + 暂停/恢复/取消）
 *   - 已完成：DownloadHistoryItem[] 渲染（打开 / 删除）
 *
 * 状态：AppStorage[DOWNLOAD_TASKS] / [DOWNLOAD_HISTORY]
 */

import { common, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys, Breakpoint } from '../storage/AppStorageKeys';
import { Layout } from '../utils/Layout';
import { DownloadTask, DownloadStatus } from '../model/DownloadTask';
import { DownloadHistoryItem } from '../storage/DownloadHistoryStore';
import { DownloadVM } from '../viewmodel/DownloadVM';
import { BookCoverImage } from '../components/BookCoverImage';
import { EmptyState } from '../components/EmptyState';
import { ErrorHelper } from '../utils/ErrorHelper';
import { I18n } from '../utils/I18n';
import { Logger } from '../utils/Logger';

const TAG: string = 'DownloadsTab';

@Component
export struct DownloadsTab {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp(AppStorageKeys.BREAKPOINT) bp: Breakpoint = 'sm';
  @StorageProp(AppStorageKeys.DOWNLOAD_TASKS) private active: DownloadTask[] = [];
  @StorageProp(AppStorageKeys.DOWNLOAD_HISTORY) private history: DownloadHistoryItem[] = [];

  @State private currentIndex: number = 0;
  private tabsController: TabsController = new TabsController();

  aboutToAppear(): void {
    DownloadVM.refreshHistory().catch((e: Error) => {
      Logger.w(TAG, `refreshHistory failed: ${e.message}`);
    });
  }

  private async onPause(t: DownloadTask): Promise<void> {
    await DownloadVM.pause(t.bookId);
  }

  private async onResume(t: DownloadTask): Promise<void> {
    await DownloadVM.resume(t.bookId);
  }

  private onCancel(t: DownloadTask): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.downloads_cancel_title'),
      message: I18n.format('downloads_cancel_msg_fmt', [t.title]),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.downloads_cancel_confirm'),
        fontColor: AppColors.error,
        action: (): void => {
          DownloadVM.cancel(t.bookId).catch((e: Error): void => {
            Logger.w(TAG, `cancel failed: ${e.message}`);
            DownloadsTab.toast(ErrorHelper.describe(e as Object, 'ctx_cancel_dl'));
          });
        },
      },
      secondaryButton: {
        value: $r('app.string.downloads_cancel_keep'),
        fontColor: AppColors.textSecondary,
        action: (): void => {},
      },
    });
  }

  private onOpen(item: DownloadHistoryItem): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    DownloadVM.openFile(item, ctx).catch((e: Error): void => {
      Logger.w(TAG, `openFile failed: ${e.message}`);
      DownloadsTab.toast(ErrorHelper.describe(e as Object, 'ctx_open_file'));
    });
  }

  private onShare(item: DownloadHistoryItem): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    DownloadVM.shareFile(item, ctx).catch((e: Error): void => {
      Logger.w(TAG, `shareFile failed: ${e.message}`);
      DownloadsTab.toast(ErrorHelper.describe(e as Object, 'ctx_share_file'));
    });
  }

  /** 跳转系统文件管理器，打开下载输出目录。 */
  private onOpenDownloadFolder(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (ctx === undefined || ctx === null) {
      DownloadsTab.toast(I18n.ts('downloads_open_folder_failed'));
      return;
    }
    // DOWNLOAD_PATH 可能是 'cache' / 'default' / 公共夹 URI / ''
    const cfg: string | undefined = AppStorage.get<string>(AppStorageKeys.DOWNLOAD_PATH);
    let folder: string;
    if (cfg === 'cache') {
      folder = `${ctx.cacheDir}/Downloads`;
    } else if (cfg !== undefined && cfg.length > 0 && cfg !== 'default') {
      folder = cfg;
    } else {
      folder = `${ctx.filesDir}/Downloads`;
    }
    const uri: string = folder.startsWith('file://') ? folder : fileUri.getUriFromPath(folder);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: uri,
      type: 'resource/directory',
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
    };
    ctx.startAbility(want).catch((e: BusinessError): void => {
      Logger.w(TAG, `openFolder failed: code=${e.code} msg=${e.message}`);
      DownloadsTab.toast(I18n.ts('downloads_open_folder_failed'));
    });
  }

  private onRemoveHistory(item: DownloadHistoryItem): void {
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
            DownloadsTab.toast(ErrorHelper.describe(e as Object, 'ctx_remove_history'));
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

  private static toast(msg: string, duration: number = 1800): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: duration };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, `toast failed: ${(e as Error).message}`);
    }
  }

  // ── Builders ──

  @Builder
  private header() {
    Row() {
      Text($r('app.string.downloads_title'))
        .fontSize(AppFontSize.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1);

      Button() {
        Row({ space: 4 }) {
          Image($r('app.media.ic_open_file')).width(14).height(14);
          Text($r('app.string.settings_open_download_folder'))
            .fontSize(AppFontSize.bodySm)
            .fontColor(AppColors.brandPrimary);
        }
      }
      .height(32)
      .padding({ left: 12, right: 12 })
      .backgroundColor(AppColors.brandPrimaryLight)
      .borderRadius(AppRadius.pill)
      .onClick(() => this.onOpenDownloadFolder());
    }
    .width('100%')
    .padding({ left: Layout.pagePadding(this.bp), right: Layout.pagePadding(this.bp), top: AppSpace.s16, bottom: AppSpace.s8 });
  }

  @Builder
  private tabBar(label: ResourceStr, index: number) {
    Column() {
      Text(label)
        .fontSize(AppFontSize.body)
        .fontColor(this.currentIndex === index ? AppColors.brandPrimary : AppColors.textSecondary)
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Regular);
      Divider()
        .strokeWidth(this.currentIndex === index ? 3 : 0)
        .color(AppColors.brandPrimary)
        .width(40)
        .margin({ top: 6 });
    }
    .padding({ left: 8, right: 8, top: 12, bottom: 8 })
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  private taskItem(t: DownloadTask) {
    Row({ space: 12 }) {
      BookCoverImage({
        url: t.cover !== undefined ? t.cover : '',
        title: t.title,
        width_: 56,
        height_: 80,
        radius: 6,
      });

      Column({ space: 6 }) {
        Text(t.title)
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');

        Row({ space: 6 }) {
          Text(DownloadsTab.statusLabel(t.status))
            .fontSize(AppFontSize.caption)
            .fontColor(DownloadsTab.statusColor(t.status));
          if (t.totalBytes > 0) {
            Text(`${t.progress}%`)
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary);
            Text(`${DownloadsTab.formatSize(t.receivedBytes)} / ${DownloadsTab.formatSize(t.totalBytes)}`)
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          } else if (t.receivedBytes > 0) {
            Text(DownloadsTab.formatSize(t.receivedBytes))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary);
          }
        }
        .width('100%');

        if (t.totalBytes > 0) {
          Progress({ value: t.progress, total: 100, type: ProgressType.Linear })
            .color(DownloadsTab.statusColor(t.status))
            .height(4)
            .width('100%');
        } else {
          Progress({ value: 0, total: 100, type: ProgressType.Linear })
            .color(DownloadsTab.statusColor(t.status))
            .height(4)
            .width('100%')
            .style({ enableSmoothEffect: true });
        }

        if (t.errorMessage !== undefined && t.errorMessage.length > 0) {
          Text(t.errorMessage)
            .fontSize(AppFontSize.caption)
            .fontColor(AppColors.error)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Column({ space: 6 }) {
        if (t.status === 'downloading') {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_pause')).width(16).height(16);
          }
          .width(32)
          .height(32)
          .backgroundColor(AppColors.surfaceAlt)
          .onClick(() => this.onPause(t));
        } else if (t.status === 'paused') {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_resume')).width(14).height(14);
          }
          .width(32)
          .height(32)
          .backgroundColor(AppColors.surfaceAlt)
          .onClick(() => this.onResume(t));
        }

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_cancel')).width(14).height(14);
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.surfaceAlt)
        .onClick(() => this.onCancel(t));
      }
      .alignItems(HorizontalAlign.End);
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
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
            Text(DownloadsTab.formatSize(item.filesize))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary);
          }
          Text(DownloadsTab.formatDate(item.downloadedAt))
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
        .onClick(() => this.onRemoveHistory(item));
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md)
    .onClick(() => this.onOpen(item));
  }

  @Builder
  private ongoingPane() {
    if (this.active === null || this.active === undefined || this.active.length === 0) {
      EmptyState({
        icon: $r('app.media.ic_empty_downloads'),
        title: $r('app.string.downloads_no_ongoing'),
        message: $r('app.string.downloads_no_ongoing_msg'),
      });
    } else {
      List({ space: 12 }) {
        ForEach(this.active, (t: DownloadTask) => {
          ListItem() {
            this.taskItem(t);
          }
        }, (t: DownloadTask) => t.bookId);

        ListItem().height(100);
      }
      .width('100%')
      .height('100%')
      .padding({ left: Layout.pagePadding(this.bp), right: Layout.pagePadding(this.bp), top: AppSpace.s8 })
      .edgeEffect(EdgeEffect.None)
      .scrollBar(BarState.Off);
    }
  }

  @Builder
  private completedPane() {
    if (this.history === null || this.history === undefined || this.history.length === 0) {
      EmptyState({
        icon: $r('app.media.ic_empty_books'),
        title: $r('app.string.downloads_no_completed'),
        message: $r('app.string.downloads_no_completed_msg'),
      });
    } else {
      List({ space: 12 }) {
        ForEach(this.history, (item: DownloadHistoryItem) => {
          ListItem() {
            this.historyItem(item);
          }
        }, (item: DownloadHistoryItem) => item.bookId);

        ListItem().height(100);
      }
      .width('100%')
      .height('100%')
      .padding({ left: Layout.pagePadding(this.bp), right: Layout.pagePadding(this.bp), top: AppSpace.s8 })
      .edgeEffect(EdgeEffect.None)
      .scrollBar(BarState.Off);
    }
  }

  build() {
    Column() {
      Blank().height(this.statusBarHeight)
      this.header();

      Tabs({ index: this.currentIndex, controller: this.tabsController }) {
        TabContent() {
          this.ongoingPane();
        }
        .tabBar(this.tabBar($r('app.string.downloads_tab_ongoing'), 0));

        TabContent() {
          this.completedPane();
        }
        .tabBar(this.tabBar($r('app.string.downloads_tab_completed'), 1));
      }
      .barMode(BarMode.Fixed)
      .barHeight(48)
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => {
        this.currentIndex = index;
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgCanvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  // ─── 静态工具 ──────────────────────────────────────

  private static statusLabel(s: DownloadStatus): string {
    if (s === 'pending') return I18n.ts('downloads_status_pending');
    if (s === 'downloading') return I18n.ts('downloads_status_downloading');
    if (s === 'paused') return I18n.ts('downloads_status_paused');
    if (s === 'completed') return I18n.ts('downloads_status_completed');
    if (s === 'failed') return I18n.ts('downloads_status_failed');
    return I18n.ts('downloads_status_canceled');
  }

  private static statusColor(s: DownloadStatus): Resource {
    if (s === 'failed' || s === 'canceled') return AppColors.error;
    if (s === 'paused') return AppColors.warning;
    if (s === 'completed') return AppColors.successTeal;
    return AppColors.brandPrimary;
  }

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
    // 取 YYYY-MM-DD
    return iso.slice(0, 10);
  }
}
