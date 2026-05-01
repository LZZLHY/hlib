/*
 * BookDetailPage.ets — 书籍详情（P3 完整版）
 *
 * 结构：
 *   - topBar: 返回 + 标题（小）+ 收藏按钮
 *   - hero: 大封面 + 标题 + 作者 + 评分（如有）
 *   - actionRow: 在线阅读 / 下载（主按钮）
 *   - metaGrid: 出版社/年份/语言/页数/格式/大小
 *   - description: 折叠展开
 *   - similarStrip: 横刷 + "查看全部" → SimilarBooksPage
 */

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { Book } from '../model/Book';
import { BookDetailVM } from '../viewmodel/BookDetailVM';
import { FavoritesVM } from '../viewmodel/FavoritesVM';
import { DownloadVM } from '../viewmodel/DownloadVM';
import { BookCoverImage } from '../components/BookCoverImage';
import { VerticalBookCard } from '../components/BookCard';
import { EmptyState } from '../components/EmptyState';
import { AppRouter, Routes, BookDetailParams, ReaderParams, SimilarParams } from '../utils/AppRouter';
import { ErrorHelper } from '../utils/ErrorHelper';
import { I18n } from '../utils/I18n';
import { HttpClient } from '../api/HttpClient';
import { UrlUtils } from '../utils/UrlUtils';
import { Logger } from '../utils/Logger';
import { Layout } from '../utils/Layout';
import { AppStorageKeys, Breakpoint } from '../storage/AppStorageKeys';

const TAG: string = 'BookDetailPage';

@Component
export struct BookDetailPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp(AppStorageKeys.BREAKPOINT) bp: Breakpoint = 'sm';
  @State private bookId: string = '';
  @State private hashId: string = '';
  @State private fallbackTitle: string = '';
  @State private fallbackCover: string = '';

  @State private detail: Book | null = null;
  @State private similar: Book[] = [];
  @State private favorited: boolean = false;
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  @State private descExpanded: boolean = false;

  // ── 加载 ──

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const r = await BookDetailVM.load(this.bookId, this.hashId);
      this.detail = r.detail;
      this.similar = r.similar;
      this.favorited = r.favorited;
    } catch (e) {
      this.errorMsg = ErrorHelper.describe(e as Object, 'ctx_load_detail');
      Logger.w(TAG, `load failed: ${(e as Error).message}`);
    } finally {
      this.loading = false;
    }
  }

  // ── 行为 ──

  private async onToggleFavorite(): Promise<void> {
    if (this.detail === null) {
      return;
    }
    try {
      const next: boolean = await FavoritesVM.toggle(this.detail);
      this.favorited = next;
      BookDetailPage.toast(next ? $r('app.string.detail_favorited') : $r('app.string.detail_unfavorited'));
    } catch (e) {
      const msg: string = ErrorHelper.describe(e as Object, 'ctx_favorite');
      Logger.w(TAG, `toggle fav failed: ${(e as Error).message}`);
      BookDetailPage.toastText(msg);
    }
  }

  private async onDownload(): Promise<void> {
    if (this.detail === null) {
      return;
    }
    if (!DownloadVM.canDownload(this.detail)) {
      BookDetailPage.toast($r('app.string.detail_no_download'));
      return;
    }
    try {
      const host: Context | undefined = this.getUIContext().getHostContext();
      if (host === undefined) {
        BookDetailPage.toast($r('app.string.detail_no_context'));
        return;
      }
      const ctx: common.UIAbilityContext = host as common.UIAbilityContext;
      await DownloadVM.start(this.detail, ctx);
      BookDetailPage.toast($r('app.string.detail_dl_queued'));
    } catch (e) {
      const msg: string = ErrorHelper.describe(e as Object, 'ctx_download');
      Logger.w(TAG, `download failed: ${(e as Error).message}`);
      BookDetailPage.toastText(msg);
    }
  }

  private onRead(): void {
    if (this.detail === null) {
      return;
    }
    const rawUrl: string = this.detail.readOnlineUrl !== undefined ? this.detail.readOnlineUrl : '';
    if (rawUrl.length === 0) {
      BookDetailPage.toast($r('app.string.detail_no_read'));
      return;
    }
    // 与 olib `book_detail_screen.dart` 一致：把服务端返回的 reader.<旧域> 重写为
    // reader.<当前镜像域>，并在 URL 后拼 remix_userid/remix_userkey 透传登录态。
    // 切换镜像后旧 reader 子域可能不可达——重写避免 ArkWeb 加载到死链。
    const userId: string = HttpClient.instance.getRemixUserId();
    const userKey: string = HttpClient.instance.getRemixUserKey();
    const finalUrl: string = UrlUtils.rewriteReaderUrl(
      rawUrl,
      HttpClient.instance.getDomain(),
      userId.length > 0 ? userId : undefined,
      userKey.length > 0 ? userKey : undefined,
    );
    const params: ReaderParams = {
      url: finalUrl,
      title: this.detail.title,
      bookId: this.bookId,
    };
    AppRouter.push(Routes.READER, params);
  }

  private onTapSimilarBook(b: Book): void {
    const params: BookDetailParams = {
      bookId: String(b.id),
      hashId: b.hash !== undefined ? b.hash : '',
      title: b.title,
      cover: b.cover !== undefined ? b.cover : '',
    };
    AppRouter.push(Routes.BOOK_DETAIL, params);
  }

  private onMoreSimilar(): void {
    if (this.detail === null) {
      return;
    }
    const params: SimilarParams = {
      bookId: this.bookId,
      hashId: this.hashId,
      title: this.detail.title,
    };
    AppRouter.push(Routes.SIMILAR, params);
  }

  private static toast(msg: ResourceStr): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 1500 };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, 'toast failed');
    }
  }

  private static toastText(msg: string): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 1800 };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, 'toast failed');
    }
  }

  // ── Builders ──

  @Builder
  private topBar() {
    Column() {
      Blank().height(this.statusBarHeight)
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_back')).width(22).height(22);
        }
        .width(40)
        .height(40)
        .backgroundColor(AppColors.surfaceAlt)
        .onClick(() => AppRouter.pop());

        Text(this.detail !== null ? this.detail.title : this.fallbackTitle)
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image(this.favorited ? $r('app.media.ic_heart_filled_red') : $r('app.media.ic_heart_outline'))
            .width(22).height(22);
        }
        .width(40)
        .height(40)
        .backgroundColor(AppColors.surfaceAlt)
        .enabled(this.detail !== null)
        .onClick(() => this.onToggleFavorite());
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    });
  }

  @Builder
  private hero(book: Book) {
    Column({ space: 16 }) {
      // 封面
      BookCoverImage({
        url: book.cover !== undefined ? book.cover : this.fallbackCover,
        title: book.title,
        width_: 140,
        height_: 200,
        radius: 12,
      });

      // 标题
      Text(book.title)
        .fontSize(AppFontSize.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      // 作者
      if (book.author !== undefined && book.author.length > 0) {
        Text(book.author)
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }

      // 评分胶囊（如有）
      if (book.qualityScore !== undefined && book.qualityScore.length > 0) {
        Row({ space: 8 }) {
          Text(`★ ${book.qualityScore}`)
            .fontSize(AppFontSize.bodySm)
            .fontColor(AppColors.warning);
          if (book.interestScore !== undefined && book.interestScore.length > 0) {
            Text(`· 热度 ${book.interestScore}`)
              .fontSize(AppFontSize.bodySm)
              .fontColor(AppColors.textTertiary);
          }
        }
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .backgroundColor(AppColors.surfaceAlt)
        .borderRadius(AppRadius.pill);
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: AppSpace.s24, right: AppSpace.s24, top: AppSpace.s8, bottom: AppSpace.s16 });
  }

  @Builder
  private actionRow(book: Book) {
    Row({ space: 12 }) {
      // 在线阅读
      Button() {
        Row({ space: 6 }) {
          Image($r('app.media.ic_play')).width(16).height(16);
          Text($r('app.string.detail_read'))
            .fontSize(AppFontSize.body)
            .fontColor(AppColors.brandPrimary)
            .fontWeight(FontWeight.Medium);
        }
      }
      .layoutWeight(1)
      .height(48)
      .backgroundColor(AppColors.brandPrimaryLight)
      .borderRadius(AppRadius.pill)
      .enabled(book.readOnlineUrl !== undefined && book.readOnlineUrl.length > 0)
      .opacity(book.readOnlineUrl !== undefined && book.readOnlineUrl.length > 0 ? 1 : 0.5)
      .onClick(() => this.onRead());

      // 下载
      Button() {
        Row({ space: 6 }) {
          Image($r('app.media.ic_download')).width(16).height(16);
          Text($r('app.string.detail_download'))
            .fontSize(AppFontSize.body)
            .fontColor(AppColors.textOnPrimary)
            .fontWeight(FontWeight.Bold);
        }
      }
      .layoutWeight(1)
      .height(48)
      .backgroundColor(AppColors.brandPrimary)
      .borderRadius(AppRadius.pill)
      .enabled(DownloadVM.canDownload(book))
      .opacity(DownloadVM.canDownload(book) ? 1 : 0.5)
      .onClick(() => this.onDownload());
    }
    .width('100%')
    .padding({ left: AppSpace.s24, right: AppSpace.s24 });
  }

  @Builder
  private metaItem(label: ResourceStr, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(AppFontSize.caption)
        .fontColor(AppColors.textTertiary);
      Text(value)
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1);
  }

  /** "—" 占位的本地化字符串。 */
  private dashStr(): string {
    return I18n.ts('detail_meta_unset');
  }

  @Builder
  private metaGrid(book: Book) {
    Column({ space: 14 }) {
      Row({ space: 16 }) {
        this.metaItem($r('app.string.detail_meta_publisher'),
          book.publisher !== undefined && book.publisher.length > 0 ? book.publisher : this.dashStr());
        this.metaItem($r('app.string.detail_meta_year'),
          book.year !== undefined && book.year > 0 ? String(book.year) : this.dashStr());
        this.metaItem($r('app.string.detail_meta_language'),
          book.language !== undefined && book.language.length > 0 ? book.language : this.dashStr());
      }
      .width('100%');

      Row({ space: 16 }) {
        this.metaItem($r('app.string.detail_meta_pages'),
          book.pages !== undefined && book.pages > 0
            ? I18n.format('detail_pages_unit_with_count', [book.pages])
            : this.dashStr());
        this.metaItem($r('app.string.detail_meta_format'),
          book.extension !== undefined && book.extension.length > 0 ? book.extension.toUpperCase() : this.dashStr());
        this.metaItem($r('app.string.detail_meta_size'),
          book.filesizeString !== undefined && book.filesizeString.length > 0 ? book.filesizeString : this.dashStr());
      }
      .width('100%');
    }
    .width('100%')
    .padding({ left: AppSpace.s24, right: AppSpace.s24, top: AppSpace.s16, bottom: AppSpace.s16 })
    .margin({ top: AppSpace.s8 })
    .backgroundColor(AppColors.surfaceAlt)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private descriptionBlock(book: Book) {
    if (book.description !== undefined && book.description.length > 0) {
      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.detail_description'))
            .fontSize(AppFontSize.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1);

          if (book.description.length > 200) {
            Text(this.descExpanded
              ? $r('app.string.detail_desc_collapse')
              : $r('app.string.detail_desc_expand'))
              .fontSize(AppFontSize.bodySm)
              .fontColor(AppColors.brandPrimary)
              .onClick(() => {
                this.descExpanded = !this.descExpanded;
              });
          }
        }
        .width('100%');

        Text(book.description)
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textSecondary)
          .lineHeight(22)
          .maxLines(this.descExpanded ? 9999 : 6)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .padding({ left: AppSpace.s24, right: AppSpace.s24, top: AppSpace.s16 });
    }
  }

  @Builder
  private similarBlock() {
    if (this.similar.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Column() {
            Text($r('app.string.detail_similar'))
              .fontSize(AppFontSize.title)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary);
            Text($r('app.string.detail_similar_subtitle'))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary)
              .margin({ top: 2 });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Text($r('app.string.detail_view_all'))
            .fontSize(AppFontSize.bodySm)
            .fontColor(AppColors.brandPrimary)
            .onClick(() => this.onMoreSimilar());
        }
        .width('100%')
        .padding({ left: AppSpace.s24, right: AppSpace.s24 });

        List({ space: 12 }) {
          ForEach(this.similar, (b: Book) => {
            ListItem() {
              VerticalBookCard({
                book: b,
                onTap: (book: Book): void => this.onTapSimilarBook(book),
              });
            }
          }, (b: Book, idx: number) => `${b.id}_${idx}`);
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(220)
        .padding({ left: AppSpace.s24, right: AppSpace.s24 });
      }
      .width('100%')
      .padding({ top: AppSpace.s16 });
    }
  }

  @Builder
  private skeletonBox(w: Length, h: Length, radius: number = 4) {
    Column()
      .width(w)
      .height(h)
      .backgroundColor(AppColors.surfaceAlt)
      .borderRadius(radius);
  }

  @Builder
  private skeletonLoader() {
    Column({ space: 16 }) {
      // hero: cover + 三行
      Row({ space: 16 }) {
        this.skeletonBox(120, 170, 8);
        Column({ space: 10 }) {
          this.skeletonBox('80%', 22, 4);
          this.skeletonBox('60%', 16, 4);
          this.skeletonBox('40%', 14, 4);
          this.skeletonBox('50%', 14, 4);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%')
      .padding({ left: AppSpace.s24, right: AppSpace.s24, top: AppSpace.s24 });

      // 操作栏
      Row({ space: 12 }) {
        this.skeletonBox(120, 44, 22);
        this.skeletonBox(120, 44, 22);
        this.skeletonBox(44, 44, 22);
      }
      .padding({ left: AppSpace.s24, right: AppSpace.s24 });

      // meta grid: 3 行
      Column({ space: 10 }) {
        this.skeletonBox('100%', 14, 4);
        this.skeletonBox('100%', 14, 4);
        this.skeletonBox('70%', 14, 4);
      }
      .padding({ left: AppSpace.s24, right: AppSpace.s24 })
      .alignItems(HorizontalAlign.Start);

      // description
      Column({ space: 8 }) {
        this.skeletonBox(80, 18, 4);
        this.skeletonBox('100%', 12, 4);
        this.skeletonBox('100%', 12, 4);
        this.skeletonBox('60%', 12, 4);
      }
      .padding({ left: AppSpace.s24, right: AppSpace.s24, top: AppSpace.s8 })
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .layoutWeight(1);
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar();

        if (this.loading && this.detail === null) {
          this.skeletonLoader();
        } else if (this.errorMsg.length > 0 && this.detail === null) {
          EmptyState({
            icon: $r('app.media.ic_empty_warning'),
            title: $r('app.string.common_error'),
            message: this.errorMsg,
            actionLabel: $r('app.string.common_retry'),
            onAction: (): void => {
              this.load();
            },
          });
        } else if (this.detail !== null) {
          Scroll() {
            if (Layout.useDetailTwoColumn(this.bp)) {
              // ≥md 双栏：左封面/操作/meta，右描述/相似。铺满屏幕宽度
              Row({ space: 12 }) {
                Column() {
                  this.hero(this.detail);
                  this.actionRow(this.detail);
                  this.metaGrid(this.detail);
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center);

                Column() {
                  this.descriptionBlock(this.detail);
                  this.similarBlock();
                  Blank().height(40);
                }
                .layoutWeight(2)
                .alignItems(HorizontalAlign.Start);
              }
              .width('100%')
              .alignItems(VerticalAlign.Top);
            } else {
              // sm 单栏
              Column() {
                this.hero(this.detail);
                this.actionRow(this.detail);
                this.metaGrid(this.detail);
                this.descriptionBlock(this.detail);
                this.similarBlock();
                Blank().height(40);
              }
              .width('100%');
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off);
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
        const p: BookDetailParams = info.param as BookDetailParams;
        this.bookId = p.bookId;
        this.hashId = p.hashId;
        this.fallbackTitle = p.title;
        this.fallbackCover = p.cover;
        this.load();
      }
    });
  }
}
