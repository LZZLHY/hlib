/*
 * FavoritesTab.ets
 *
 * 收藏 Tab：
 *   - 拉取服务端 saved + 合并本地 ID 集合
 *   - 列表展示 HorizontalBookCard
 *   - 长按弹出"取消收藏"确认
 *   - 顶部"收藏书数 / 编辑（保留位）"
 *   - 下拉刷新
 *
 * 状态：AppStorage[FAVORITE_BOOKS] / [FAVORITE_IDS]
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys, Breakpoint } from '../storage/AppStorageKeys';
import { Layout } from '../utils/Layout';
import { Book } from '../model/Book';
import { FavoritesVM } from '../viewmodel/FavoritesVM';
import { HorizontalBookCard } from '../components/BookCard';
import { EmptyState } from '../components/EmptyState';
import { AppRouter, Routes, BookDetailParams } from '../utils/AppRouter';
import { ErrorHelper } from '../utils/ErrorHelper';
import { I18n } from '../utils/I18n';
import { Logger } from '../utils/Logger';
import { promptAction } from '@kit.ArkUI';

const TAG: string = 'FavoritesTab';

@Component
export struct FavoritesTab {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp(AppStorageKeys.BREAKPOINT) bp: Breakpoint = 'sm';
  @StorageProp(AppStorageKeys.FAVORITE_BOOKS) private books: Book[] = [];
  @State private loading: boolean = false;
  @State private refreshing: boolean = false;
  @State private errorMsg: string = '';

  aboutToAppear(): void {
    if (this.books === null || this.books === undefined || this.books.length === 0) {
      this.refresh();
    }
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      await FavoritesVM.refresh();
    } catch (e) {
      this.errorMsg = ErrorHelper.describe(e as Object, 'ctx_load_favorites');
      Logger.w(TAG, `refresh failed: ${(e as Error).message}`);
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private goDetail(b: Book): void {
    const params: BookDetailParams = {
      bookId: String(b.id),
      hashId: b.hash !== undefined ? b.hash : '',
      title: b.title,
      cover: b.cover !== undefined ? b.cover : '',
    };
    AppRouter.push(Routes.BOOK_DETAIL, params);
  }

  private confirmRemove(b: Book): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.favorites_remove_title'),
      message: I18n.format('favorites_remove_msg_fmt', [b.title]),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.common_remove'),
        fontColor: AppColors.error,
        action: (): void => {
          FavoritesVM.remove(b.id)
            .then((): Promise<void> => this.refresh())
            .catch((e: Error): void => {
              const msg: string = ErrorHelper.describe(e as Object, 'ctx_unfavorite');
              Logger.w(TAG, `remove failed: ${e.message}`);
              try {
                promptAction.openToast({ message: msg, duration: 1800 });
              } catch (te) {
                Logger.w(TAG, `toast failed: ${(te as Error).message}`);
              }
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

  @Builder
  private header() {
    Row() {
      Column() {
        Text($r('app.string.favorites_title'))
          .fontSize(AppFontSize.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary);
        Text(I18n.format('favorites_count_fmt', [this.books !== null && this.books !== undefined ? this.books.length : 0]))
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.textTertiary)
          .margin({ top: 2 });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Image($r('app.media.ic_refresh')).width(20).height(20);
      }
      .width(40)
      .height(40)
      .backgroundColor(AppColors.surfaceAlt)
      .enabled(!this.loading)
      .onClick(() => this.refresh());
    }
    .width('100%')
    .padding({ left: Layout.pagePadding(this.bp), right: Layout.pagePadding(this.bp), top: AppSpace.s16, bottom: AppSpace.s8 })
  }

  build() {
    Column() {
      Blank().height(this.statusBarHeight)
      this.header();

      Refresh({ refreshing: $$this.refreshing }) {
        if (this.loading && !this.refreshing && (this.books === null || this.books === undefined || this.books.length === 0)) {
          Column() {
            LoadingProgress().width(36).height(36).color(AppColors.brandPrimary);
            Text($r('app.string.favorites_loading'))
              .fontSize(AppFontSize.bodySm)
              .fontColor(AppColors.textSecondary)
              .margin({ top: 12 });
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center);
        } else if (this.errorMsg.length > 0 && (this.books === null || this.books === undefined || this.books.length === 0)) {
          EmptyState({
            icon: $r('app.media.ic_empty_warning'),
            title: $r('app.string.common_error'),
            message: this.errorMsg,
            actionLabel: $r('app.string.common_retry'),
            onAction: (): void => {
              this.refresh();
            },
          });
        } else if (this.books === null || this.books === undefined || this.books.length === 0) {
          EmptyState({
            icon: $r('app.media.ic_empty_favorites'),
            title: $r('app.string.favorites_empty_title'),
            message: $r('app.string.favorites_empty_msg'),
          });
        } else {
          // ≥md 走双列 Grid，sm 走单列 List；手势保留长按取消收藏
          Grid() {
            ForEach(this.books, (b: Book) => {
              GridItem() {
                HorizontalBookCard({
                  book: b,
                  onTap: (book: Book): void => this.goDetail(book),
                });
              }
              .gesture(
                LongPressGesture({ repeat: false, duration: 600 })
                  .onAction(() => {
                    this.confirmRemove(b);
                  }),
              );
            }, (b: Book, idx: number) => `${b.id}_${idx}`);
          }
          .columnsTemplate(this.bp === 'sm' ? '1fr' : (this.bp === 'xl' ? '1fr 1fr 1fr' : '1fr 1fr'))
          .columnsGap(12)
          .rowsGap(12)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: Layout.pagePadding(this.bp), right: Layout.pagePadding(this.bp), bottom: 100 })
          .edgeEffect(EdgeEffect.None)
          .scrollBar(BarState.Off);
        }
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing(() => {
        this.refresh();
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgCanvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
