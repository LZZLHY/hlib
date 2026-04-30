/*
 * SplashPage.ets
 *
 * 启动屏 + 引导路由（P1.5 Navigation 版）。
 *
 * 现状：
 *   - 不再 @Entry；由 RootPage 在 aboutToAppear 时把 SPLASH 推上栈
 *   - 路由换 AppRouter.replace
 *   - animateTo 命令式 -> 组件 .animation 修饰符 + 状态切换驱动
 */

import { common } from '@kit.AbilityKit';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppSpace } from '../theme/AppTextStyles';
import { Logger } from '../utils/Logger';
import { HttpClient } from '../api/HttpClient';
import { DomainManifest } from '../api/DomainManifest';
import { AuthVM } from '../viewmodel/AuthVM';
import { SpeedTestVM } from '../viewmodel/SpeedTestVM';
import { AppRouter, Routes } from '../utils/AppRouter';

const TAG: string = 'SplashPage';

@Component
export struct SplashPage {
  @State private statusText: ResourceStr = $r('app.string.splash_loading');
  @State private logoScale: number = 0.6;
  @State private logoOpacity: number = 0;

  aboutToAppear(): void {
    setTimeout(() => {
      this.logoScale = 1;
      this.logoOpacity = 1;
    }, 50);
    this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    Logger.i(TAG, 'bootstrap start');

    try {
      await SpeedTestVM.loadCached();
    } catch (e) {
      Logger.w(TAG, 'loadCached failed (ignored)');
    }

    // 异步刷新远程镜像 manifest（仅启用时实际发起请求），完成后顺带触发一次新列表测速
    DomainManifest.refreshFromRemote().then((updated: boolean): void => {
      if (updated) {
        Logger.i(TAG, 'domain manifest updated, retesting');
        SpeedTestVM.testAll(true).catch((err: Object): void => {
          const e: Error = err as Error;
          Logger.w(TAG, `post-manifest speedtest failed: ${e.message}`);
        });
      }
    }).catch((err: Object): void => {
      const e: Error = err as Error;
      Logger.w(TAG, `manifest refresh failed: ${e.message}`);
    });

    SpeedTestVM.testAll(false).catch((err: Object) => {
      const e: Error = err as Error;
      Logger.w(TAG, `bg speedtest failed: ${e.message}`);
    });

    await SplashPage.delay(700);

    let target: string = Routes.LOGIN;
    if (HttpClient.instance.hasAuth()) {
      this.statusText = $r('app.string.splash_checking_network');
      const user = await AuthVM.restoreFromStorage();
      if (user !== null) {
        target = Routes.MAIN;
      }
    }

    Logger.i(TAG, `redirect to ${target}`);
    AppRouter.replace(target);
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  /**
   * 启动期间按返回键 → 直接退出 Ability。
   * 不能让 Navigation 默认 pop——会让栈空，露出 RootPage 的绿色根占位。
   */
  private onSplashBackPressed = (): boolean => {
    const ctx: common.UIAbilityContext | null =
      this.getUIContext().getHostContext() as common.UIAbilityContext | null;
    if (ctx !== null && ctx !== undefined) {
      ctx.terminateSelf().catch((e: Error) => {
        Logger.w(TAG, `terminateSelf failed: ${e.message}`);
      });
    }
    return true;
  };

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [
              [AppColors.brandPrimaryDark, 0.0],
              [AppColors.brandPrimary, 0.5],
              [AppColors.brandPrimary, 1.0],
            ],
          });

        Column({ space: 24 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 120, height: 120 })
              .fill(Color.Transparent)
              .stroke('#33FFFFFF')
              .strokeWidth(1.5);
            Image($r('app.media.startIcon'))
              .width(64)
              .height(64);
          }
          .scale({ x: this.logoScale, y: this.logoScale })
          .opacity(this.logoOpacity)
          .animation({ duration: 700, curve: Curve.EaseOut });

          Text($r('app.string.app_name'))
            .fontSize(AppFontSize.display)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .opacity(this.logoOpacity)
            .animation({ duration: 700, curve: Curve.EaseOut });

          Text($r('app.string.app_subtitle'))
            .fontSize(AppFontSize.body)
            .fontColor('#B3FFFFFF')
            .opacity(this.logoOpacity)
            .animation({ duration: 700, curve: Curve.EaseOut });

          Blank()
            .height(60);

          Row({ space: 8 }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(Color.White);
            Text(this.statusText)
              .fontSize(AppFontSize.bodySm)
              .fontColor('#CCFFFFFF');
          }
          .opacity(this.logoOpacity)
          .animation({ duration: 700, curve: Curve.EaseOut });
        }
        .padding({ left: AppSpace.s32, right: AppSpace.s32 });

        Column() {
          Blank();
          Text('v1.0.0')
            .fontSize(AppFontSize.overline)
            .fontColor('#66FFFFFF')
            .margin({ bottom: 24 });
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End);
      }
      .width('100%')
      .height('100%');
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(this.onSplashBackPressed);
  }
}
