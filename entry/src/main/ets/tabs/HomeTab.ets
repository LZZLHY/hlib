/*
 * HomeTab.ets
 *
 * 首页内容（嵌入 MainPage 的第一个 Tab）。
 *
 * 结构：
 *   - 顶部 Greeting + 用户名
 *   - 搜索入口（点击切到 Search Tab）
 *   - 推荐横刷
 *   - 热门横刷
 *   - 近期横刷
 *
 * 数据：HomeVM.refresh() 并发拉取，AppStorage 订阅。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { Book } from '../model/Book';
import { User } from '../model/User';
import { HomeVM, LoadMoreResult } from '../viewmodel/HomeVM';
import { VerticalBookCard } from '../components/BookCard';
import { EmptyState } from '../components/EmptyState';
import { AppRouter, Routes, BookDetailParams } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'HomeTab';

@Component
export struct HomeTab {
  /** 由父级 MainPage 传入：点击搜索框切到 Search Tab。 */
  onSearchTap: () => void = (): void => {};
  /** 由父级 MainPage 传入：点击右上齿轮跳设置页。 */
  onSettingsTap: () => void = (): void => {};

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp(AppStorageKeys.USER) private user: User | null = null;
  @StorageLink(AppStorageKeys.HOME_RECOMMENDED) private recommended: Book[] = [];
  @StorageLink(AppStorageKeys.HOME_POPULAR) private popular: Book[] = [];
  @StorageLink(AppStorageKeys.HOME_RECENT) private recent: Book[] = [];
  @StorageLink(AppStorageKeys.HOME_LOADING) private loading: boolean = false;
  @State private refreshing: boolean = false;
  @State private homeSection: number = 1;
  @State private segmentWidth: number = 0;
  @State private topBarHeight: number = 0;
  @State private popularPage: number = 1;
  @State private recentPage: number = 1;
  @State private popularHasMore: boolean = true;
  @State private recentHasMore: boolean = true;
  @State private loadingMore: boolean = false;

  aboutToAppear(): void {
    if (this.recommended.length === 0 && this.popular.length === 0 && this.recent.length === 0) {
      this.refresh();
    }
  }

  private async refresh(): Promise<void> {
    this.popularPage = 1;
    this.recentPage = 1;
    this.popularHasMore = true;
    this.recentHasMore = true;
    try {
      await HomeVM.refresh();
    } catch (err) {
      const e: Error = err as Error;
      Logger.w(TAG, `refresh failed: ${e.message}`);
    } finally {
      this.refreshing = false;
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loadingMore) return;
    if (this.homeSection === 0) return;
    if (this.homeSection === 1 && !this.popularHasMore) return;
    if (this.homeSection === 2 && !this.recentHasMore) return;

    this.loadingMore = true;
    try {
      const nextPage: number = this.homeSection === 1 ? this.popularPage + 1 : this.recentPage + 1;
      const result: LoadMoreResult = await HomeVM.loadMoreSection(this.homeSection, nextPage);
      if (this.homeSection === 1) {
        const merged: Book[] = [...this.popular, ...result.books];
        this.popular = merged;
        this.popularPage = nextPage;
        this.popularHasMore = result.hasMore;
      } else {
        const merged: Book[] = [...this.recent, ...result.books];
        this.recent = merged;
        this.recentPage = nextPage;
        this.recentHasMore = result.hasMore;
      }
    } catch (err) {
      const e: Error = err as Error;
      Logger.w(TAG, `loadMore failed: ${e.message}`);
    } finally {
      this.loadingMore = false;
    }
  }

  private greetingKey(): string {
    const h: number = new Date().getHours();
    if (h < 6) return 'home_greeting_night';
    if (h < 11) return 'home_greeting_morning';
    if (h < 13) return 'home_greeting_noon';
    if (h < 18) return 'home_greeting_afternoon';
    if (h < 22) return 'home_greeting_evening';
    return 'home_greeting_night';
  }

  private greetingResource(): Resource {
    return $r(`app.string.${this.greetingKey()}`);
  }

  private userName(): string {
    if (this.user !== null && this.user.name.length > 0) {
      return this.user.name;
    }
    return '书友';
  }

  private goDetail(book: Book): void {
    const params: BookDetailParams = {
      bookId: String(book.id),
      hashId: book.hash !== undefined ? book.hash : '',
      title: book.title,
      cover: book.cover !== undefined ? book.cover : '',
    };
    AppRouter.push(Routes.BOOK_DETAIL, params);
  }

  // ── Builders ──

  @Builder
  private greetingHeader() {
    Row() {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          Text(this.greetingResource())
            .fontSize(AppFontSize.titleLg)
            .fontColor(AppColors.textSecondary);
          Text(',')
            .fontSize(AppFontSize.titleLg)
            .fontColor(AppColors.textSecondary);
        }
        .alignSelf(ItemAlign.Start);

        Text(this.userName())
          .fontSize(AppFontSize.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .alignSelf(ItemAlign.Start);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Image($r('app.media.ic_settings')).width(20).height(20);
      }
      .width(40)
      .height(40)
      .backgroundColor(AppColors.surfaceAlt)
      .onClick(() => this.onSettingsTap());
    }
    .width('100%');
  }

  @Builder
  private searchEntry() {
    Row({ space: 8 }) {
      Image($r('app.media.ic_tab_search')).width(18).height(18).objectFit(ImageFit.Contain);
      Text($r('app.string.home_search_hint'))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textTertiary)
        .layoutWeight(1);
    }
    .width('100%')
    .height(48)
    .padding({ left: AppSpace.s16, right: AppSpace.s16 })
    .backgroundColor('#E6F5F5F5')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.9,
    })
    .borderRadius(AppRadius.pill)
    .shadow({ radius: 8, color: AppColors.shadowCard, offsetX: 0, offsetY: 2 })
    .onClick(() => this.onSearchTap());
  }


  @Builder
  private segmentTabs() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Sliding capsule indicator
      Row()
        .width(this.segmentWidth > 0 ? this.segmentWidth / 3 : 0)
        .height('100%')
        .borderRadius(16)
        .backgroundColor(AppColors.brandPrimary)
        .translate({ x: this.homeSection * this.segmentWidth / 3 })
        .animation({ duration: 250, curve: Curve.EaseInOut })

      // Labels
      Row() {
        Text($r('app.string.home_recommended'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .height('100%')
          .fontSize(AppFontSize.bodySm)
          .fontColor(this.homeSection === 0 ? AppColors.textOnPrimary : AppColors.textSecondary)
          .fontWeight(this.homeSection === 0 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.homeSection = 0; })

        Text($r('app.string.order_popular'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .height('100%')
          .fontSize(AppFontSize.bodySm)
          .fontColor(this.homeSection === 1 ? AppColors.textOnPrimary : AppColors.textSecondary)
          .fontWeight(this.homeSection === 1 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.homeSection = 1; })

        Text($r('app.string.order_date'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .height('100%')
          .fontSize(AppFontSize.bodySm)
          .fontColor(this.homeSection === 2 ? AppColors.textOnPrimary : AppColors.textSecondary)
          .fontWeight(this.homeSection === 2 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.homeSection = 2; })
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.segmentWidth = newArea.width as number;
      })
    }
    .width('100%')
    .height(36)
    .borderRadius(18)
    .backgroundColor(AppColors.surfaceAlt)
    .padding(2)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Scrollable content (behind top bar)
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column({ space: 16 }) {
            Blank().height(this.topBarHeight + 8);

            if (this.homeSection === 0) {
              BookGridView({
                books: this.recommended,
                loading: this.loading,
                hasMore: false,
                loadingMore: false,
                onBookTap: (b: Book): void => this.goDetail(b),
                onLoadMore: (): void => {},
              });
            } else if (this.homeSection === 1) {
              BookGridView({
                books: this.popular,
                loading: this.loading,
                hasMore: this.popularHasMore,
                loadingMore: this.loadingMore && this.homeSection === 1,
                onBookTap: (b: Book): void => this.goDetail(b),
                onLoadMore: (): void => { this.loadMore(); },
              });
            } else {
              BookGridView({
                books: this.recent,
                loading: this.loading,
                hasMore: this.recentHasMore,
                loadingMore: this.loadingMore && this.homeSection === 2,
                onBookTap: (b: Book): void => this.goDetail(b),
                onLoadMore: (): void => { this.loadMore(); },
              });
            }

            // 全空
            if (!this.loading
              && this.recommended.length === 0
              && this.popular.length === 0
              && this.recent.length === 0) {
              EmptyState({
                icon: $r('app.media.ic_empty_books'),
                title: $r('app.string.home_load_failed'),
                message: $r('app.string.common_retry'),
                actionLabel: $r('app.string.common_retry'),
                onAction: (): void => {
                  this.refresh();
                },
              });
            }

            Blank().height(100);
          }
          .width('100%');
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .width('100%')
        .onScrollEdge((side: Edge) => {
          if (side === Edge.Bottom) {
            this.loadMore();
          }
        });
      }
      .width('100%')
      .height('100%')
      .onRefreshing(() => {
        this.refresh();
      });

      // Fixed blur top bar
      Column({ space: 12 }) {
        Blank().height(this.statusBarHeight)
        this.greetingHeader();
        this.searchEntry();
        this.segmentTabs();
      }
      .width('100%')
      .padding({ left: 28, right: 28, bottom: 12 })
      .backgroundBlurStyle(BlurStyle.Thin, {
        colorMode: ThemeColorMode.SYSTEM,
        adaptiveColor: AdaptiveColor.DEFAULT,
      })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.topBarHeight = newArea.height as number;
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgCanvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}

@Component
struct BookGridView {
  @Prop books: Book[] = [];
  @Prop loading: boolean = false;
  @Prop hasMore: boolean = false;
  @Prop loadingMore: boolean = false;
  onBookTap: (book: Book) => void = (_: Book): void => {};
  onLoadMore: () => void = (): void => {};

  build() {
    Column() {
      if (this.books.length === 0) {
        Row() {
          if (this.loading) {
            LoadingProgress().width(24).height(24).color(AppColors.brandPrimary);
          } else {
            Text($r('app.string.home_no_books'))
              .fontSize(AppFontSize.bodySm)
              .fontColor(AppColors.textTertiary);
          }
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center);
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.books, (book: Book) => {
            Column() {
              VerticalBookCard({ book: book, onTap: (b: Book): void => this.onBookTap(b) });
            }
            .width('33.3%')
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: 16 })
          }, (book: Book, idx: number) => `${book.id}_${idx}`);
        }
        .width('100%')
        .padding({ left: AppSpace.s16, right: AppSpace.s16 });

        if (this.loadingMore) {
          Row({ space: 8 }) {
            LoadingProgress().width(20).height(20).color(AppColors.brandPrimary);
            Text($r('app.string.home_loading_more'))
              .fontSize(AppFontSize.bodySm)
              .fontColor(AppColors.textTertiary);
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center);
        } else if (this.hasMore) {
          Row() {
            Text($r('app.string.home_load_more'))
              .fontSize(AppFontSize.body)
              .fontColor(AppColors.brandPrimary);
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.onLoadMore());
        } else if (this.books.length > 0) {
          Row() {
            Text($r('app.string.home_no_more'))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary);
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center);
        }
      }
    }
    .width('100%');
  }
}
