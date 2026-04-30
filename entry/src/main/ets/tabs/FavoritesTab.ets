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
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Book } from '../model/Book';
import { FavoritesVM } from '../viewmodel/FavoritesVM';
import { HorizontalBookCard } from '../components/BookCard';
import { EmptyState } from '../components/EmptyState';
import { AppRouter, Routes, BookDetailParams } from '../utils/AppRouter';
import { ErrorHelper } from '../utils/ErrorHelper';
import { Logger } from '../utils/Logger';
import { promptAction } from '@kit.ArkUI';

const TAG: string = 'FavoritesTab';

@Component
export struct FavoritesTab {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
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
      this.errorMsg = ErrorHelper.describe(e as Object, '加载收藏');
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
      title: '取消收藏？',
      message: `将从收藏中移除《${b.title}》。`,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '移除',
        fontColor: '#E53935',
        action: (): void => {
          FavoritesVM.remove(b.id)
            .then((): Promise<void> => this.refresh())
            .catch((e: Error): void => {
              const msg: string = ErrorHelper.describe(e as Object, '取消收藏');
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
        value: '取消',
        fontColor: '#666666',
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
        Text(`${this.books !== null && this.books !== undefined ? this.books.length : 0} 本`)
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
    .padding({ left: AppSpace.s24, right: AppSpace.s24, top: AppSpace.s16, bottom: AppSpace.s8 })
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
          List({ space: 12 }) {
            ForEach(this.books, (b: Book) => {
              ListItem() {
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

            ListItem().height(100);
          }
          .width('100%')
          .padding({ left: AppSpace.s24, right: AppSpace.s24 })
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
