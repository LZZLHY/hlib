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
import { AppStorageKeys, PRIVACY_POLICY_VERSION } from '../storage/AppStorageKeys';
import { Logger } from '../utils/Logger';
import { HttpClient } from '../api/HttpClient';
import { DomainManifest } from '../api/DomainManifest';
import { AuthVM } from '../viewmodel/AuthVM';
import { SpeedTestVM } from '../viewmodel/SpeedTestVM';
import { AppRouter, Routes } from '../utils/AppRouter';
import { PrivacyConsentDialog } from '../components/PrivacyConsentDialog';

const TAG: string = 'SplashPage';

@Component
export struct SplashPage {
  @State private statusText: ResourceStr = $r('app.string.splash_loading');
  @State private logoScale: number = 0.6;
  @State private logoOpacity: number = 0;
  @StorageProp(AppStorageKeys.APP_VERSION) private appVersion: string = '';

  /**
   * 隐私同意弹窗控制器。autoCancel:false 强制用户做出选择。
   * 同意 → 写入持久化版本号 → bootstrap()
   * 不同意 → terminateSelf
   * 查看完整政策 → 关闭弹窗 + push PrivacyPage；返回 Splash 后由 onShown 重新拉起
   */
  private consentDialog: CustomDialogController = new CustomDialogController({
    builder: PrivacyConsentDialog({
      onAgree: (): void => this.onPrivacyAgreed(),
      onDecline: (): void => this.onPrivacyDeclined(),
      onViewFull: (): void => this.onViewFullPolicy(),
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true,
  });

  /** 标记当前是否因"查看完整政策"而临时关闭了弹窗，供信号回调判断是否重弹。 */
  @State private viewingFullPolicy: boolean = false;

  /**
   * 监听 PrivacyPage 卸载信号——它在 aboutToDisappear 时写入当前时间戳。
   * 用 @Watch 触发回调而不是依赖 NavDestination.onShown（后者在某些 SDK 上从子路由返回时不触发）。
   */
  @StorageProp(AppStorageKeys.PRIVACY_PAGE_CLOSED_AT) @Watch('onPrivacyPageClosed')
  private privacyPageClosedAt: number = 0;

  aboutToAppear(): void {
    setTimeout(() => {
      this.logoScale = 1;
      this.logoOpacity = 1;
    }, 50);

    // 合规：先检查隐私同意状态。未同意 / 政策版本变更 → 弹窗阻断；任何网络请求都必须在同意后发起。
    const agreedVersion: string = AppStorage.get<string>(AppStorageKeys.PRIVACY_AGREED_VERSION) ?? '';
    if (agreedVersion === PRIVACY_POLICY_VERSION) {
      this.bootstrap();
    } else {
      Logger.i(TAG, `privacy consent required (agreed=${agreedVersion}, current=${PRIVACY_POLICY_VERSION})`);
      // 用 setTimeout 把 dialog.open 推到下一帧，避免 aboutToAppear 阶段开 dialog 报错
      setTimeout((): void => {
        this.consentDialog.open();
      }, 100);
    }
  }

  /** 用户同意 → 持久化当前政策版本号 → 启动 bootstrap。 */
  private onPrivacyAgreed(): void {
    AppStorage.setOrCreate<string>(AppStorageKeys.PRIVACY_AGREED_VERSION, PRIVACY_POLICY_VERSION);
    Logger.i(TAG, `privacy consent accepted (v=${PRIVACY_POLICY_VERSION})`);
    this.bootstrap();
  }

  /** 用户点击"查看完整政策" → 弹窗已被组件自身关闭，这里负责跳转 PrivacyPage。 */
  private onViewFullPolicy(): void {
    Logger.i(TAG, 'open full privacy policy from consent dialog');
    this.viewingFullPolicy = true;
    AppRouter.push(Routes.PRIVACY);
  }

  /**
   * PrivacyPage 卸载（用户返回 Splash）时由 @Watch 触发。
   * 仅在 viewingFullPolicy 为真且尚未同意时重弹。
   */
  private onPrivacyPageClosed(): void {
    if (!this.viewingFullPolicy) {
      return;
    }
    this.viewingFullPolicy = false;
    const v: string = AppStorage.get<string>(AppStorageKeys.PRIVACY_AGREED_VERSION) ?? '';
    if (v === PRIVACY_POLICY_VERSION) {
      // 兜底：极端情况用户在 PrivacyPage 期间通过其他入口同意了，无需再弹
      return;
    }
    Logger.i(TAG, 'returned from full policy, reopening consent dialog');
    setTimeout((): void => {
      this.consentDialog.open();
    }, 200);
  }

  /** 用户拒绝 → 退出 Ability。 */
  private onPrivacyDeclined(): void {
    Logger.i(TAG, 'privacy consent declined, exiting');
    const ctx: common.UIAbilityContext | null =
      this.getUIContext().getHostContext() as common.UIAbilityContext | null;
    if (ctx !== null && ctx !== undefined) {
      ctx.terminateSelf().catch((e: Error) => {
        Logger.w(TAG, `terminateSelf failed: ${e.message}`);
      });
    }
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
          Text(`v${this.appVersion.length > 0 ? this.appVersion : '1.0.0'}`)
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
