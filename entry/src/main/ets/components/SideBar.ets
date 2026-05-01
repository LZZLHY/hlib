/*
 * SideBar.ets
 *
 * ≥lg 大屏的侧边导航。240vp 宽固定，垂直排列 4 项 + 底部齿轮设置入口。
 * 由 MainPage 在 navStyle 解析为 'side' 时挂载；与 floating capsule 互斥显示。
 *
 * 设计要点：
 *   - 选中高亮使用 brandPrimaryLight 圆角矩形 + brandPrimary 文字色
 *   - 安全区：顶部 statusBarHeight，底部 navBarHeight
 *   - 底部齿轮：与 HomeTab 顶栏齿轮的设置入口语义一致
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';

interface SideBarItem {
  label: ResourceStr;
  icon: Resource;
  iconFilled: Resource;
}

@Component
export struct SideBar {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @Prop currentIndex: number = 0;
  onSelect: (idx: number) => void = (_: number): void => {};
  onSettingsTap: () => void = (): void => {};

  private items: SideBarItem[] = [
    { label: $r('app.string.tab_home'),      icon: $r('app.media.ic_tab_home'),      iconFilled: $r('app.media.ic_tab_home_filled')      },
    { label: $r('app.string.tab_search'),    icon: $r('app.media.ic_tab_search'),    iconFilled: $r('app.media.ic_tab_search_filled')    },
    { label: $r('app.string.tab_favorites'), icon: $r('app.media.ic_tab_favorites'), iconFilled: $r('app.media.ic_tab_favorites_filled') },
    { label: $r('app.string.tab_downloads'), icon: $r('app.media.ic_tab_downloads'), iconFilled: $r('app.media.ic_tab_downloads_filled') },
  ];

  @Builder
  private navItem(item: SideBarItem, idx: number) {
    Row({ space: 12 }) {
      Image(this.currentIndex === idx ? item.iconFilled : item.icon)
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain);
      Text(item.label)
        .fontSize(AppFontSize.body)
        .fontColor(this.currentIndex === idx ? AppColors.brandPrimary : AppColors.textSecondary)
        .fontWeight(this.currentIndex === idx ? FontWeight.Bold : FontWeight.Regular)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .borderRadius(AppRadius.md)
    .backgroundColor(this.currentIndex === idx ? AppColors.brandPrimaryLight : Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => this.onSelect(idx));
  }

  build() {
    Column() {
      // 顶部 logo / app name
      Row({ space: 10 }) {
        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .borderRadius(6);
        Text($r('app.string.app_name'))
          .fontSize(AppFontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .margin({ top: this.statusBarHeight + 12, bottom: 8 });

      // 导航项
      Column({ space: 4 }) {
        ForEach(this.items, (item: SideBarItem, idx: number) => {
          this.navItem(item, idx);
        }, (item: SideBarItem, idx: number) => `${idx}`);
      }
      .width('100%')
      .padding({ left: 8, right: 8 });

      Blank().layoutWeight(1);

      // 底部 settings
      Row({ space: 12 }) {
        Image($r('app.media.ic_settings'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain);
        Text($r('app.string.settings_title'))
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textSecondary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .borderRadius(AppRadius.md)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      .onClick(() => this.onSettingsTap())
      .margin({ left: 8, right: 8, bottom: this.navBarHeight + 16 });
    }
    .width(240)
    .height('100%')
    .backgroundColor(AppColors.surface)
    .border({ width: { right: 0.5 }, color: AppColors.divider });
  }
}
