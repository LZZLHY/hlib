/*
 * MainPage.ets — 主页 Tabs 容器（P3 完整版）
 *
 * 4 个底栏：首页 / 搜索 / 收藏 / 下载。
 * SearchTab 的"切线路"回调由本页持有 DomainSelectorDialog，避免重复创建。
 *
 * aboutToAppear 触发 FavoritesVM.init / DownloadVM.init，把持久化数据回灌 AppStorage。
 *
 * P4 升级：底部导航使用 HdsTabs + barFloatingStyle 沉浸光感。
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
import { SideBar } from '../components/SideBar';
import { HttpClient } from '../api/HttpClient';
import { FavoritesVM } from '../viewmodel/FavoritesVM';
import { DownloadVM } from '../viewmodel/DownloadVM';
import { AppRouter, Routes } from '../utils/AppRouter';
import { I18n } from '../utils/I18n';
import { Logger } from '../utils/Logger';
import { Layout } from '../utils/Layout';
import { Breakpoint, NavStyle } from '../storage/AppStorageKeys';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';

const TAG: string = 'MainPage';

@Component
export struct MainPage {
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp(AppStorageKeys.BREAKPOINT) bp: Breakpoint = 'sm';
  @StorageProp(AppStorageKeys.NAV_STYLE) navStyle: NavStyle = 'auto';
  @State private currentIndex: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();

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
   * 底部 Tab 项：图标（选中态用 filled 版）+ 文字标签。
   * HdsTabs 的 .tabBar() 只传字符串时不会渲染图标——这里用自定义 Builder 把图标补回来。
   */
  @Builder
  private bottomBarItem(index: number, icon: Resource, iconFilled: Resource, label: ResourceStr) {
    Column({ space: 2 }) {
      Image(this.currentIndex === index ? iconFilled : icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain);
      Text(label)
        .fontSize(AppFontSize.caption)
        .fontColor(this.currentIndex === index ? AppColors.brandPrimary : AppColors.textSecondary)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
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
      promptAction.openToast({ message: I18n.ts('main_press_back_to_exit'), duration: 1800 });
    } catch (e) {
      Logger.w(TAG, `toast failed: ${(e as Error).message}`);
    }
    return true;
  };

  /** 是否使用侧边栏导航（侧栏模式下不应再出现底部悬浮栏）。 */
  private useSideNav(): boolean {
    return Layout.resolveNavStyle(this.bp, this.navStyle) === 'side';
  }

  /** 4 个 Tab 面板（侧栏 / 底栏两种布局共用，避免重复）。 */
  @Builder
  private tabPanels() {
    TabContent() {
      HomeTab({
        onSearchTap: (): void => this.switchToSearch(),
        onSettingsTap: (): void => this.goSettings(),
      });
    }
    .tabBar(this.bottomBarItem(0, $r('app.media.ic_tab_home'), $r('app.media.ic_tab_home_filled'), $r('app.string.tab_home')))

    TabContent() {
      SearchTab({ onOpenDomainSelector: (): void => this.openDomainSelector() });
    }
    .tabBar(this.bottomBarItem(1, $r('app.media.ic_tab_search'), $r('app.media.ic_tab_search_filled'), $r('app.string.tab_search')))

    TabContent() {
      FavoritesTab();
    }
    .tabBar(this.bottomBarItem(2, $r('app.media.ic_tab_favorites'), $r('app.media.ic_tab_favorites_filled'), $r('app.string.tab_favorites')))

    TabContent() {
      DownloadsTab();
    }
    .tabBar(this.bottomBarItem(3, $r('app.media.ic_tab_downloads'), $r('app.media.ic_tab_downloads_filled'), $r('app.string.tab_downloads')))
  }

  build() {
    NavDestination() {
      Row() {
        // ≥lg 用户偏好不为 'bottom' 时挂载 SideBar（贴屏幕左边缘，240vp 固定）
        if (this.useSideNav()) {
          SideBar({
            currentIndex: this.currentIndex,
            onSelect: (i: number): void => {
              this.tabsController.changeIndex(i);
            },
            onSettingsTap: (): void => this.goSettings(),
          });
        }

        // Tabs 铺满剩余宽度（或整屏宽）
        Column() {
          if (this.useSideNav()) {
            // 侧栏模式：隐藏底部栏（barHeight=0 + 不用悬浮样式），避免与 SideBar 重复出现
            HdsTabs({ controller: this.tabsController }) {
              this.tabPanels();
            }
            .barPosition(BarPosition.End)
            .barOverlap(false)
            .barHeight(0)
            .onSelected((index: number) => {
              this.currentIndex = index;
            })
            .backgroundColor(AppColors.bgCanvas)
            .width('100%')
            .height('100%');
          } else {
            // 底栏模式：沉浸光感悬浮底栏
            HdsTabs({ controller: this.tabsController }) {
              this.tabPanels();
            }
            .barPosition(BarPosition.End)
            .barOverlap(true)
            .barFloatingStyle({
              systemMaterialEffect: {
                materialType: hdsMaterial.MaterialType.IMMERSIVE,
                materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
              },
              barBottomMargin: this.navBarHeight + 12,
            })
            .onSelected((index: number) => {
              this.currentIndex = index;
            })
            .backgroundColor(AppColors.bgCanvas)
            .width('100%')
            .height('100%');
          }
        }
        .layoutWeight(1)
        .height('100%');
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(this.onMainBackPressed);
  }
}
