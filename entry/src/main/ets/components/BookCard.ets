/*
 * BookCard.ets
 *
 * 两套外观：
 *   - VerticalBookCard：用于横向列表（首页推荐区）
 *   - HorizontalBookCard：用于全屏列表（搜索结果）
 *
 * 都接收 Book 对象，点击发出 onTap(book)。
 */

import { Book } from '../model/Book';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { BookCoverImage } from './BookCoverImage';

@Component
export struct VerticalBookCard {
  @Prop book: Book = new Book();
  onTap: (book: Book) => void = (_: Book): void => {};

  build() {
    Column({ space: 8 }) {
      BookCoverImage({
        url: this.book.cover ?? '',
        title: this.book.title,
        width_: 110,
        height_: 154,
        radius: 8,
      });

      Text(this.book.title.length > 0 ? this.book.title : '未知书名')
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(110);

      if (this.book.author !== undefined && this.book.author.length > 0) {
        Text(this.book.author)
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(110);
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width(110)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => this.onTap(this.book));
  }
}

@Component
export struct HorizontalBookCard {
  @Prop book: Book = new Book();
  onTap: (book: Book) => void = (_: Book): void => {};

  private metaLine(): string {
    const parts: string[] = [];
    if (this.book.year !== undefined) {
      parts.push(`${this.book.year}`);
    }
    if (this.book.pages !== undefined) {
      parts.push(`${this.book.pages}p`);
    }
    if (this.book.filesizeString !== undefined && this.book.filesizeString.length > 0) {
      parts.push(this.book.filesizeString);
    } else if (this.book.filesize !== undefined && this.book.filesize > 0) {
      parts.push(`${(this.book.filesize / 1024 / 1024).toFixed(1)}MB`);
    }
    if (this.book.extension !== undefined && this.book.extension.length > 0) {
      parts.push(this.book.extension.toUpperCase());
    }
    return parts.join(' · ');
  }

  build() {
    Row({ space: 12 }) {
      BookCoverImage({
        url: this.book.cover ?? '',
        title: this.book.title,
        width_: 72,
        height_: 102,
        radius: 8,
      });

      Column({ space: 6 }) {
        Text(this.book.title.length > 0 ? this.book.title : '未知书名')
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');

        if (this.book.author !== undefined && this.book.author.length > 0) {
          Text(this.book.author)
            .fontSize(AppFontSize.bodySm)
            .fontColor(AppColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
        }

        Blank().layoutWeight(1);

        Text(this.metaLine())
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .height(102);
    }
    .width('100%')
    .padding(AppSpace.s12)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => this.onTap(this.book));
  }
}
