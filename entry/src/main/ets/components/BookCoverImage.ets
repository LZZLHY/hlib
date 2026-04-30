/*
 * BookCoverImage.ets
 *
 * 书籍封面：
 *   - 有 URL 时尝试加载（鸿蒙 Image 自动缓存）
 *   - 无 URL / 加载失败 时回退为单字 monogram + 渐变色块
 *
 * 不引入三方图库。后续如需更稳的缓存可在 PreferencesStore 上加 LRU。
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius } from '../theme/AppTextStyles';

const PALETTE: string[] = [
  '#0E7C7B', '#FF9F1C', '#2EC4B6', '#E71D36', '#5C6BC0',
  '#26A69A', '#EC407A', '#7E57C2', '#42A5F5', '#FFA726',
];

@Component
export struct BookCoverImage {
  @Prop url: string = '';
  @Prop title: string = '';
  width_: number = 80;
  height_: number = 112;
  radius: number = 8;

  @State private loadFailed: boolean = false;

  private monogram(): string {
    const t: string = this.title.trim();
    return t.length > 0 ? t.charAt(0).toUpperCase() : '?';
  }

  private bgColor(): string {
    const t: string = this.title.trim();
    let sum: number = 0;
    for (let i = 0; i < t.length; i++) {
      sum = sum + t.charCodeAt(i);
    }
    return PALETTE[sum % PALETTE.length];
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 兜底色块
      Column() {
        Text(this.monogram())
          .fontSize(this.width_ * 0.45)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold);
      }
      .width(this.width_)
      .height(this.height_)
      .backgroundColor(this.bgColor())
      .borderRadius(this.radius)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);

      // 真实图（加载成功时覆盖在色块之上）
      if (this.url.length > 0 && !this.loadFailed) {
        Image(this.url)
          .width(this.width_)
          .height(this.height_)
          .borderRadius(this.radius)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.startIcon'))
          .onError(() => {
            this.loadFailed = true;
          });
      }
    }
    .width(this.width_)
    .height(this.height_)
    .borderRadius(this.radius)
    .clip(true)
    .shadow({ radius: 8, color: AppColors.shadowCard, offsetX: 0, offsetY: 2 });
  }
}
