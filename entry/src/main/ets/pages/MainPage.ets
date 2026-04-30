/*
 * MainPage.ets — 主页 Tabs 容器（P3 完整版）
 *
 * 4 个底栏：首页 / 搜索 / 收藏 / 下载。
 * SearchTab 的"切线路"回调由本页持有 DomainSelectorDialog，避免重复创建。
 *
 * aboutToAppear 触发 FavoritesVM.init / DownloadVM.init，把持久化数据回灌 AppStorage。
 */

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../theme/AppColors';
import { AppFontSize } from '../theme/AppTextStyles';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { HomeTab } from '../tabs/HomeTab';
import { SearchTab } from '../tabs/SearchTab';
import { FavoritesTab } from '../tabs/FavoritesTab';
import { DownloadsTab } from '../tabs/DownloadsTab';
import { DomainSelectorDialog } from '../components/DomainSelectorDialog';
import { CustomDomainDialog } from '../components/CustomDomainDialog';
import { HttpClient } from '../api/HttpClient';
import { FavoritesVM } from '../viewmodel/FavoritesVM';
import { DownloadVM } from '../viewmodel/DownloadVM';
import { AppRouter, Routes } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'MainPage';

@Component
export struct MainPage {
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State private currentIndex: number = 0;
  private tabsController: TabsController = new TabsController();

  /** 上次按返回键时间戳，用于"再按一次退出"逻辑。 */
  @State private lastBackTs: number = 0;

  aboutToAppear(): void {
    FavoritesVM.init().catch((e: Error) => {
      Logger.w(TAG, `FavoritesVM.init failed: ${e.message}`);
    });
    const ctx: common.UIAbilityContext | null = this.getUIContext().getHostContext() as common.UIAbilityContext | null;
    DownloadVM.init(ctx === null ? undefined : ctx).catch((e: Error) => {
      Logger.w(TAG, `DownloadVM.init failed: ${e.message}`);
    });
  }

  private goSettings(): void {
    AppRouter.push(Routes.SETTINGS);
  }

  // 全局 DomainSelector，复用给 SearchTab 的 CF 弹窗
  private domainController: CustomDialogController = new CustomDialogController({
    builder: DomainSelectorDialog({
      onSelect: (d: string): void => this.applyDomain(d),
      onCustomTap: (): void => this.openCustomDomain(),
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
  });

  private customDomainController: CustomDialogController = new CustomDialogController({
    builder: CustomDomainDialog({
      onConfirm: (d: string): void => this.applyDomain(d),
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
  });

  private applyDomain(d: string): void {
    AppStorage.setOrCreate<string>(AppStorageKeys.DOMAIN, d);
    HttpClient.instance.setDomain(d);
  }

  private openDomainSelector(): void {
    this.domainController.open();
  }

  private openCustomDomain(): void {
    this.customDomainController.open();
  }

  private switchToSearch(): void {
    this.tabsController.changeIndex(1);
  }

  /**
   * 处理 NavDestination 系统返回（包括手势返回 / 三键返回）。
   *
   * 行为：
   * - 当前 Tab 不在首屏（首页）→ 第一次返回切回首屏 Tab，**不退出 App**
   * - 当前 Tab 已在首屏 → 第一次返回提示「再按一次退出」，2 秒内第二次返回真正退出 Ability
   *
   * 永远返回 true 拦截 Navigation 默认 pop——避免栈空后露出 RootPage 的绿色根占位。
   */
  private onMainBackPressed = (): boolean => {
    if (this.currentIndex !== 0) {
      this.tabsController.changeIndex(0);
      return true;
    }
    const now: number = Date.now();
    if (now - this.lastBackTs < 2000) {
      // 2 秒内第二次返回 → 退出 Ability
      const ctx: common.UIAbilityContext | null =
        this.getUIContext().getHostContext() as common.UIAbilityContext | null;
      if (ctx !== null && ctx !== undefined) {
        ctx.terminateSelf().catch((e: Error) => {
          Logger.w(TAG, `terminateSelf failed: ${e.message}`);
        });
      }
      return true;
    }
    this.lastBackTs = now;
    try {
      promptAction.openToast({ message: '再按一次退出', duration: 1800 });
    } catch (e) {
      Logger.w(TAG, `toast failed: ${(e as Error).message}`);
    }
    return true;
  };

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
          TabContent() {
            HomeTab({
              onSearchTap: (): void => this.switchToSearch(),
              onSettingsTap: (): void => this.goSettings(),
            });
          }
          .tabBar($r('app.string.tab_home'))

          TabContent() {
            SearchTab({ onOpenDomainSelector: (): void => this.openDomainSelector() });
          }
          .tabBar($r('app.string.tab_search'))

          TabContent() {
            FavoritesTab();
          }
          .tabBar($r('app.string.tab_favorites'))

          TabContent() {
            DownloadsTab();
          }
          .tabBar($r('app.string.tab_downloads'))
        }
        .width('100%')
        .height('100%')
        .barHeight(0)
        .barMode(BarMode.Fixed)
        .scrollable(false)
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .backgroundColor(AppColors.bgCanvas);

        // Floating capsule tab bar
        Column() {
          Row() {
            this.floatingTabItem($r('app.string.tab_home'), $r('app.media.ic_tab_home'), $r('app.media.ic_tab_home_filled'), 0);
            this.floatingTabItem($r('app.string.tab_search'), $r('app.media.ic_tab_search'), $r('app.media.ic_tab_search_filled'), 1);
            this.floatingTabItem($r('app.string.tab_favorites'), $r('app.media.ic_tab_favorites'), $r('app.media.ic_tab_favorites_filled'), 2);
            this.floatingTabItem($r('app.string.tab_downloads'), $r('app.media.ic_tab_downloads'), $r('app.media.ic_tab_downloads_filled'), 3);
          }
          .width('100%')
          .height(56)
          .borderRadius(28)
          .backgroundBlurStyle(BlurStyle.Thin, {
            colorMode: ThemeColorMode.SYSTEM,
            adaptiveColor: AdaptiveColor.DEFAULT,
          })
          .shadow({ radius: 16, color: '#1A000000', offsetX: 0, offsetY: 4 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: this.navBarHeight + 12 });
      }
      .width('100%')
      .height('100%');
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(this.onMainBackPressed);
  }

  @Builder
  private floatingTabItem(label: ResourceStr, icon: Resource, iconFilled: Resource, idx: number) {
    Column({ space: 2 }) {
      Image(this.currentIndex === idx ? iconFilled : icon)
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain);
      Text(label)
        .fontSize(AppFontSize.caption)
        .fontColor(this.currentIndex === idx ? AppColors.brandPrimary : AppColors.textSecondary)
        .fontWeight(this.currentIndex === idx ? FontWeight.Bold : FontWeight.Normal);
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.tabsController.changeIndex(idx);
    });
  }
}
