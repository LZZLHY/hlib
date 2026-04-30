/*
 * SearchTab.ets
 *
 * 搜索 Tab：搜索栏 + 筛选弹窗 + 结果列表 + 分页。
 * 搜索状态完全本地（@State），不入 AppStorage（搜索流是临时的）。
 */

import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { Book } from '../model/Book';
import { SearchVM } from '../viewmodel/SearchVM';
import { SearchOptions, SearchPage } from '../api/ZLibraryClient';
import { LANGUAGE_FILTERS, ORDER_FILTERS, EXTENSION_FILTERS, FilterItem } from '../api/SearchFilters';
import { CfBlockedError } from '../api/ApiTypes';
import { SearchBar } from '../components/SearchBar';
import { HorizontalBookCard } from '../components/BookCard';
import { EmptyState } from '../components/EmptyState';
import { FilterDialog, FilterValues } from '../components/FilterDialog';
import { CfBlockedDialog } from '../components/CfBlockedDialog';
import { AppRouter, Routes, BookDetailParams } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'SearchTab';

@Component
export struct SearchTab {
  /** 父级注册的"打开域名选择"回调 —— 让 CF 弹窗能拉起 DomainSelector。 */
  onOpenDomainSelector: () => void = (): void => {};

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State private query: string = '';
  @State private books: Book[] = [];
  @State private currentPage: number = 1;
  @State private totalPages: number = 0;
  @State private loading: boolean = false;
  @State private refreshing: boolean = false;
  @State private hasSearched: boolean = false;
  @State private filterValues: FilterValues = { language: 'all', order: 'default', extension: 'all' };

  private filterController: CustomDialogController = new CustomDialogController({
    builder: FilterDialog({
      initial: this.filterValues,
      onApply: (v: FilterValues): void => this.applyFilters(v),
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
  });

  private cfController: CustomDialogController = new CustomDialogController({
    builder: CfBlockedDialog({
      onSwitchLine: (): void => this.onOpenDomainSelector(),
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
  });

  // ── 行为 ──

  private buildOptions(page: number): SearchOptions {
    const opts: SearchOptions = {};
    opts.message = this.query.trim();
    opts.page = page;
    opts.limit = 20;

    const langItem: FilterItem | undefined = LANGUAGE_FILTERS.find(
      (f: FilterItem): boolean => f.key === this.filterValues.language
    );
    if (langItem !== undefined && langItem.apiValue !== undefined) {
      opts.languages = [langItem.apiValue];
    }

    const ordItem: FilterItem | undefined = ORDER_FILTERS.find(
      (f: FilterItem): boolean => f.key === this.filterValues.order
    );
    if (ordItem !== undefined && ordItem.apiValue !== undefined) {
      opts.order = ordItem.apiValue;
    }

    const extItem: FilterItem | undefined = EXTENSION_FILTERS.find(
      (f: FilterItem): boolean => f.key === this.filterValues.extension
    );
    if (extItem !== undefined && extItem.apiValue !== undefined) {
      opts.extensions = [extItem.apiValue];
    }
    return opts;
  }

  private async runSearch(page: number = 1): Promise<void> {
    if (this.query.trim().length === 0) {
      this.books = [];
      this.hasSearched = false;
      this.totalPages = 0;
      return;
    }
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasSearched = true;
    try {
      const opts: SearchOptions = this.buildOptions(page);
      const result: SearchPage = await SearchVM.run(opts);
      this.books = result.books;
      this.currentPage = result.currentPage;
      this.totalPages = result.totalPages;
    } catch (err) {
      this.handleError(err);
    } finally {
      this.loading = false;
    }
  }

  private handleError(err: Object): void {
    if (err instanceof CfBlockedError) {
      this.cfController.open();
      return;
    }
    const msg: string = SearchVM.describeError(err);
    SearchTab.toast(msg);
    Logger.w(TAG, `search failed: ${msg}`);
  }

  private static toast(msg: string): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 2200 };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, `toast failed`);
    }
  }

  private applyFilters(v: FilterValues): void {
    this.filterValues = v;
    if (this.hasSearched) {
      this.runSearch(1);
    }
  }

  private goPrevPage(): void {
    if (this.currentPage > 1 && !this.loading) {
      this.runSearch(this.currentPage - 1);
    }
  }

  private goNextPage(): void {
    if (this.currentPage < this.totalPages && !this.loading) {
      this.runSearch(this.currentPage + 1);
    }
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

  /** 当前是否有筛选生效 */
  private hasActiveFilters(): boolean {
    return this.filterValues.language !== 'all'
      || this.filterValues.order !== 'default'
      || this.filterValues.extension !== 'all';
  }

  // ── Builders ──

  @Builder
  private topBar() {
    Column() {
      Blank().height(this.statusBarHeight)
      Column({ space: 12 }) {
        Row() {
          Text($r('app.string.tab_search'))
            .fontSize(AppFontSize.headline)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1);
        }
        .width('100%');

        SearchBar({
          text: $query,
          onSubmit: (q: string): void => {
            this.runSearch(1);
          },
        });

        Row({ space: 8 }) {
          Button() {
            Row({ space: 4 }) {
              Image($r('app.media.ic_settings'))
                .width(14).height(14)
                .objectFit(ImageFit.Contain);
              Text($r('app.string.search_filter'))
                .fontSize(AppFontSize.bodySm)
                .fontColor(this.hasActiveFilters() ? AppColors.textOnPrimary : AppColors.textPrimary);
            }
          }
          .height(34)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.hasActiveFilters() ? AppColors.brandPrimary : AppColors.surfaceAlt)
          .borderRadius(AppRadius.pill)
          .onClick(() => {
            this.filterController.open();
          });

          if (this.totalPages > 0) {
            Text(`${this.books.length} ${this.totalPages > 1 ? `· ${this.currentPage}/${this.totalPages} 页` : ''}`)
              .fontSize(AppFontSize.bodySm)
              .fontColor(AppColors.textSecondary);
          }

          Blank().layoutWeight(1);
        }
        .width('100%');
      }
      .width('100%')
      .padding({ left: AppSpace.s16, right: AppSpace.s16, top: AppSpace.s12, bottom: AppSpace.s8 })
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    });
  }

  @Builder
  private resultsList() {
    if (this.loading && !this.refreshing && this.books.length === 0) {
      Column() {
        LoadingProgress().width(36).height(36).color(AppColors.brandPrimary);
        Text($r('app.string.search_searching'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textSecondary)
          .margin({ top: 12 });
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center);
    } else if (!this.hasSearched) {
      EmptyState({
        icon: $r('app.media.ic_empty_search'),
        title: $r('app.string.search_start_title'),
        message: $r('app.string.search_start_msg'),
      });
    } else if (this.books.length === 0) {
      EmptyState({
        icon: $r('app.media.ic_empty_no_results'),
        title: $r('app.string.search_no_results_title'),
        message: $r('app.string.search_no_results_msg'),
      });
    } else {
      List({ space: 8 }) {
        ForEach(this.books, (book: Book) => {
          ListItem() {
            HorizontalBookCard({ book: book, onTap: (b: Book): void => this.goDetail(b) });
          }
          .padding({ left: AppSpace.s16, right: AppSpace.s16 });
        }, (book: Book, idx: number) => `${book.id}_${idx}`);

        // 分页栏
        if (this.totalPages > 1) {
          ListItem() {
            this.pagination();
          }
          .padding({ left: AppSpace.s16, right: AppSpace.s16, top: AppSpace.s8 });
        }

        ListItem() {
          Column().height(100).width('100%');
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .width('100%');
    }
  }

  @Builder
  private pagination() {
    Row({ space: 12 }) {
      Button('‹')
        .width(40)
        .height(40)
        .fontSize(AppFontSize.title)
        .fontColor(this.currentPage > 1 ? AppColors.textPrimary : AppColors.textTertiary)
        .backgroundColor(AppColors.surfaceAlt)
        .borderRadius(20)
        .enabled(this.currentPage > 1 && !this.loading)
        .onClick(() => this.goPrevPage());

      Text(`${this.currentPage} / ${this.totalPages}`)
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center);

      Button('›')
        .width(40)
        .height(40)
        .fontSize(AppFontSize.title)
        .fontColor(this.currentPage < this.totalPages ? AppColors.textPrimary : AppColors.textTertiary)
        .backgroundColor(AppColors.surfaceAlt)
        .borderRadius(20)
        .enabled(this.currentPage < this.totalPages && !this.loading)
        .onClick(() => this.goNextPage());
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 });
  }

  build() {
    Column() {
      this.topBar();

      Refresh({ refreshing: $$this.refreshing }) {
        this.resultsList();
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing(() => {
        if (this.hasSearched) {
          this.runSearch(this.currentPage).finally((): void => {
            this.refreshing = false;
          });
        } else {
          this.refreshing = false;
        }
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgCanvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
