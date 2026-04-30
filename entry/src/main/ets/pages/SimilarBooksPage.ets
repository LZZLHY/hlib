/*
 * SimilarBooksPage.ets — 相似书籍完整页（P3）
 *
 * 流程：onReady → 取参 → ZLibraryClient.similar(bookId, hashId) → 列表展示
 *      点击书目 push 新一层 BookDetailPage
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppSpace } from '../theme/AppTextStyles';
import { Book } from '../model/Book';
import { ZLibraryClient } from '../api/ZLibraryClient';
import { HorizontalBookCard } from '../components/BookCard';
import { EmptyState } from '../components/EmptyState';
import { AppRouter, Routes, BookDetailParams, SimilarParams } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'SimilarBooksPage';

@Component
export struct SimilarBooksPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State private bookId: string = '';
  @State private hashId: string = '';
  @State private parentTitle: string = '';

  @State private books: Book[] = [];
  @State private loading: boolean = true;
  @State private errorMsg: string = '';

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const list: Book[] = await ZLibraryClient.instance.similar(this.bookId, this.hashId);
      this.books = list;
    } catch (e) {
      this.errorMsg = (e as Error).message;
      Logger.w(TAG, `similar failed: ${this.errorMsg}`);
    } finally {
      this.loading = false;
    }
  }

  private onTapBook(b: Book): void {
    const params: BookDetailParams = {
      bookId: String(b.id),
      hashId: b.hash !== undefined ? b.hash : '',
      title: b.title,
      cover: b.cover !== undefined ? b.cover : '',
    };
    AppRouter.push(Routes.BOOK_DETAIL, params);
  }

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
          Text($r('app.string.similar_title'))
            .fontSize(AppFontSize.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary);
          if (this.parentTitle.length > 0) {
            Text(this.parentTitle)
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 });
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    });
  }

  @Builder
  private list() {
    List({ space: 12 }) {
      ForEach(this.books, (b: Book) => {
        ListItem() {
          HorizontalBookCard({
            book: b,
            onTap: (book: Book): void => this.onTapBook(book),
          });
        }
      }, (b: Book, idx: number) => `${b.id}_${idx}`);

      ListItem().height(40);
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: AppSpace.s24, right: AppSpace.s24 })
    .scrollBar(BarState.Off);
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar();

        if (this.loading) {
          Column() {
            LoadingProgress().width(36).height(36).color(AppColors.brandPrimary);
            Text($r('app.string.similar_loading'))
              .fontSize(AppFontSize.bodySm)
              .fontColor(AppColors.textSecondary)
              .margin({ top: 12 });
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center);
        } else if (this.errorMsg.length > 0) {
          EmptyState({
            icon: $r('app.media.ic_empty_warning'),
            title: $r('app.string.common_error'),
            message: this.errorMsg,
            actionLabel: $r('app.string.common_retry'),
            onAction: (): void => {
              this.load();
            },
          });
        } else if (this.books.length === 0) {
          EmptyState({
            icon: $r('app.media.ic_empty_mailbox'),
            title: $r('app.string.similar_empty_title'),
            message: $r('app.string.similar_empty_msg'),
          });
        } else {
          this.list();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onReady((ctx: NavDestinationContext) => {
      const info: NavPathInfo | undefined = ctx.pathInfo;
      if (info !== undefined && info.param !== undefined) {
        const p: SimilarParams = info.param as SimilarParams;
        this.bookId = p.bookId;
        this.hashId = p.hashId;
        this.parentTitle = p.title;
        this.load();
      }
    });
  }
}
