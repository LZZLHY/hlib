/*
 * ReaderPage.ets — 在线阅读（P4 打磨版）
 *
 * 在 ArkWeb 容器里加载 Z-Library 的 readOnlineUrl，
 * 加载前同步 HttpClient 的 remix_userid / remix_userkey cookie 到 WebCookieManager，
 * 让站内授权能继承 App 的登录态。
 *
 * P4 升级：
 *   - 字体大小三档（小/中/大），通过注入 CSS root font-size 生效
 *   - 全屏切换（点击屏幕空白处隐藏/显示顶栏与工具栏）
 *   - Web 内返回手势：先 webview.accessBackward()，再 AppRouter.pop()
 *   - 工具栏：返回 / 标题 / 字体 / 刷新；底栏：上下页占位
 */

import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius } from '../theme/AppTextStyles';
import { HttpClient } from '../api/HttpClient';
import { ReadingPositionStore } from '../storage/ReadingPositionStore';
import { AppRouter, ReaderParams } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'ReaderPage';

type ReaderFont = 'small' | 'medium' | 'large';

@Component
export struct ReaderPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State private url: string = '';
  @State private title: string = 'Reader';
  @State private progress: number = 0;
  @State private webReady: boolean = false;
  @State private errorMsg: string = '';
  @State private fullscreen: boolean = false;
  @State private fontLevel: ReaderFont = 'medium';
  @State private fontMenuOpen: boolean = false;

  /** 用于阅读进度持久化的 bookId（无值则不记忆） */
  private bookId: string = '';
  /** 待恢复的阅读进度（0..100），onPageEnd 后注入 */
  private pendingScrollPercent: number = -1;
  /** 已恢复过一次（避免重复 scrollTo） */
  private hasRestored: boolean = false;
  /** 上次保存的进度，用于节流 */
  private lastSavedPercent: number = -1;
  /** 加载超时计时器 */
  private loadTimeoutId: number = -1;
  private static readonly LOAD_TIMEOUT_MS: number = 20000;

  private webController: webview.WebviewController = new webview.WebviewController();

  /** 把 HttpClient cookie 注入到 WebView 的 cookie store。
   *  同时为 API 域和 reader 子域都注入（host-only cookie 不跨子域）。 */
  private injectCookies(): void {
    try {
      const domain: string = HttpClient.instance.getDomain();
      const cookie: string = HttpClient.instance.exportCookieHeader();
      if (cookie.length === 0 || domain.length === 0) {
        return;
      }
      const parts: string[] = cookie.split(';');
      const baseUrl: string = `https://${domain}`;
      // 计算 reader 子域，以便为其也注入 cookie
      const readerUrl: string = `https://reader.${domain}`;
      const targets: string[] = [baseUrl, readerUrl];
      for (let t = 0; t < targets.length; t++) {
        const target: string = targets[t];
        for (let i = 0; i < parts.length; i++) {
          const item: string = parts[i].trim();
          if (item.length === 0) {
            continue;
          }
          try {
            webview.WebCookieManager.configCookieSync(target, item);
          } catch (e) {
            const eq: number = item.indexOf('=');
            const name: string = eq > 0 ? item.substring(0, eq) : '(unknown)';
            Logger.w(TAG, `configCookie(${name}) for ${target} failed: ${(e as Error).message}`);
          }
        }
      }
      Logger.i(TAG, `cookies injected for ${baseUrl} + reader (${parts.length} items)`);
    } catch (e) {
      Logger.w(TAG, `injectCookies failed: ${(e as Error).message}`);
    }
  }

  private onRefresh(): void {
    if (!this.webReady) {
      return;
    }
    try {
      this.webController.refresh();
    } catch (e) {
      Logger.w(TAG, `refresh failed: ${(e as Error).message}`);
    }
  }

  /** 返回：优先 web 内 history，回退 AppRouter.pop() */
  private onBack(): void {
    if (this.webReady) {
      try {
        if (this.webController.accessBackward()) {
          this.webController.backward();
          return;
        }
      } catch (e) {
        Logger.w(TAG, `accessBackward failed: ${(e as Error).message}`);
      }
    }
    AppRouter.pop();
  }

  /** 切全屏：隐藏顶栏 / 工具栏，留 web 占满。再次点击恢复。 */
  private toggleFullscreen(): void {
    this.fullscreen = !this.fullscreen;
    if (this.fontMenuOpen) {
      this.fontMenuOpen = false;
    }
  }

  private toggleFontMenu(): void {
    this.fontMenuOpen = !this.fontMenuOpen;
  }

  /** 设置字体档位，注入 CSS。 */
  private setFontLevel(level: ReaderFont): void {
    this.fontLevel = level;
    this.fontMenuOpen = false;
    this.applyFontInjection();
  }

  /** 注入 CSS：root font-size 决定 rem 缩放，对绝大多数 epub 阅读 webview 都生效。 */
  private applyFontInjection(): void {
    if (!this.webReady) {
      return;
    }
    const px: number = ReaderPage.fontPx(this.fontLevel);
    const css: string = `document.documentElement.style.fontSize='${px}px';` +
      `var s=document.getElementById('hlib-reader-font');if(!s){s=document.createElement('style');s.id='hlib-reader-font';document.head.appendChild(s);}` +
      `s.innerHTML='body,p,span,div{font-size:${px}px !important;line-height:1.7 !important;}';`;
    try {
      this.webController.runJavaScript(css);
    } catch (e) {
      Logger.w(TAG, `runJavaScript failed: ${(e as Error).message}`);
    }
  }

  private static fontPx(level: ReaderFont): number {
    if (level === 'small') return 14;
    if (level === 'large') return 22;
    return 17;
  }

  // ── 阅读进度持久化 ──

  /** 退出页前保存 + 清理超时。 */
  aboutToDisappear(): void {
    this.saveScroll();
    this.clearLoadTimeout();
  }

  private startLoadTimeout(): void {
    this.clearLoadTimeout();
    this.loadTimeoutId = setTimeout((): void => {
      if (this.progress < 100 && this.errorMsg.length === 0) {
        Logger.w(TAG, `load timeout (${ReaderPage.LOAD_TIMEOUT_MS}ms), progress=${this.progress}, url=${this.url}`);
        this.errorMsg = '加载超时，请检查网络或尝试其他镜像站';
      }
    }, ReaderPage.LOAD_TIMEOUT_MS);
  }

  private clearLoadTimeout(): void {
    if (this.loadTimeoutId >= 0) {
      clearTimeout(this.loadTimeoutId);
      this.loadTimeoutId = -1;
    }
  }

  /** 异步从 store 取上次进度，加到 pendingScrollPercent，等 page end 后恢复。 */
  private loadSavedPosition(): void {
    if (this.bookId.length === 0) {
      return;
    }
    ReadingPositionStore.get(this.bookId)
      .then((p: number | undefined): void => {
        if (p !== undefined && p > 0.5) {
          this.pendingScrollPercent = p;
        }
      })
      .catch((e: Error): void => {
        Logger.w(TAG, `loadSavedPosition failed: ${e.message}`);
      });
  }

  /** 注入 JS 滚动到 pendingScrollPercent。 */
  private restoreScroll(): void {
    if (this.hasRestored || this.pendingScrollPercent < 0 || !this.webReady) {
      return;
    }
    const p: number = this.pendingScrollPercent;
    const js: string = `(function(){var h=document.documentElement.scrollHeight-window.innerHeight;` +
      `if(h>0){window.scrollTo(0,Math.round(h*${p}/100));}})();`;
    try {
      this.webController.runJavaScript(js);
      this.hasRestored = true;
    } catch (e) {
      Logger.w(TAG, `restoreScroll failed: ${(e as Error).message}`);
    }
  }

  /** 注入 JS 读取当前 scrollY，转 percent，写回 store。节流：差值 ≥ 1 才写。 */
  private saveScroll(): void {
    if (this.bookId.length === 0 || !this.webReady) {
      return;
    }
    const js: string = `(function(){var h=document.documentElement.scrollHeight-window.innerHeight;` +
      `return h>0?(window.scrollY/h*100):0;})()`;
    try {
      this.webController.runJavaScript(js, (err: BusinessError, result: string): void => {
        if (err !== undefined && err !== null && err.code !== 0) {
          return;
        }
        if (result === undefined || result === null || result.length === 0) {
          return;
        }
        const num: number = Number.parseFloat(result);
        if (!Number.isFinite(num)) {
          return;
        }
        if (Math.abs(num - this.lastSavedPercent) < 1) {
          return;
        }
        this.lastSavedPercent = num;
        ReadingPositionStore.save(this.bookId, num).catch((e: Error): void => {
          Logger.w(TAG, `save position failed: ${e.message}`);
        });
      });
    } catch (e) {
      Logger.w(TAG, `saveScroll failed: ${(e as Error).message}`);
    }
  }

  @Builder
  private topBar() {
    Column() {
      Blank().height(this.statusBarHeight)
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_back')).width(20).height(20);
        }
        .width(36)
        .height(36)
        .backgroundColor('#33000000')
        .onClick(() => this.onBack());

        Text(this.title)
          .fontSize(AppFontSize.body)
          .fontColor(Color.White)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_font_size')).width(18).height(18);
        }
        .width(36)
        .height(36)
        .backgroundColor(this.fontMenuOpen ? '#66FFFFFF' : '#33000000')
        .enabled(this.webReady)
        .onClick(() => this.toggleFontMenu());

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_refresh')).width(20).height(20);
        }
        .width(36)
        .height(36)
        .backgroundColor('#33000000')
        .enabled(this.webReady)
        .onClick(() => this.onRefresh());

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_fullscreen')).width(18).height(18);
        }
        .width(36)
        .height(36)
        .backgroundColor('#33000000')
        .onClick(() => this.toggleFullscreen());
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .backgroundColor('#CC0E7C7B')
    .backgroundBlurStyle(BlurStyle.Thin);
  }

  @Builder
  private fontPill(level: ReaderFont, label: string, size: number) {
    Button() {
      Text(label)
        .fontSize(size)
        .fontWeight(this.fontLevel === level ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.fontLevel === level ? AppColors.textOnPrimary : AppColors.textPrimary);
    }
    .layoutWeight(1)
    .height(40)
    .backgroundColor(this.fontLevel === level ? AppColors.brandPrimary : AppColors.surfaceAlt)
    .borderRadius(AppRadius.sm)
    .onClick(() => this.setFontLevel(level));
  }

  @Builder
  private fontMenu() {
    Column({ space: 8 }) {
      Row() {
        Text('字体大小')
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textSecondary)
          .layoutWeight(1);
      }
      .width('100%');

      Row({ space: 8 }) {
        this.fontPill('small', 'A', 14);
        this.fontPill('medium', 'A', 18);
        this.fontPill('large', 'A', 22);
      }
      .width('100%');
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.surface)
    .border({ width: { top: 0.5 }, color: AppColors.divider });
  }

  @Builder
  private webView() {
    if (this.url.length === 0) {
      Column() {
        Text('未提供阅读链接')
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textSecondary);
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center);
    } else if (this.errorMsg.length > 0) {
      Column() {
        Image($r('app.media.ic_empty_warning')).width(48).height(48).objectFit(ImageFit.Contain);
        Text(this.errorMsg)
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textSecondary)
          .margin({ top: 12 });
        Button($r('app.string.common_retry'))
          .height(40)
          .padding({ left: 24, right: 24 })
          .backgroundColor(AppColors.brandPrimary)
          .fontColor(AppColors.textOnPrimary)
          .borderRadius(20)
          .margin({ top: 16 })
          .onClick(() => {
            this.errorMsg = '';
            this.onRefresh();
          });
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);
    } else {
      Web({ src: this.url, controller: this.webController })
        .layoutWeight(1)
        .width('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .mixedMode(MixedMode.All)
        .zoomAccess(true)
        .onControllerAttached(() => {
          this.webReady = true;
          try {
            this.webController.setCustomUserAgent(HttpClient.instance.defaultUserAgent());
          } catch (e) {
            Logger.w(TAG, `setCustomUserAgent failed: ${(e as Error).message}`);
          }
          Logger.i(TAG, `loading reader: ${this.url}`);
          this.startLoadTimeout();
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.progress = event.newProgress;
          if (event.newProgress >= 100) {
            this.clearLoadTimeout();
            if (this.fontLevel !== 'medium') {
              this.applyFontInjection();
            }
            this.restoreScroll();
          }
        })
        .onPageEnd(() => {
          this.clearLoadTimeout();
          if (this.fontLevel !== 'medium') {
            this.applyFontInjection();
          }
          this.restoreScroll();
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          this.clearLoadTimeout();
          const desc: string = event.error !== undefined ? event.error.getErrorInfo() : 'unknown';
          Logger.w(TAG, `web error: ${desc}`);
          this.errorMsg = `加载失败: ${desc}`;
        })
        .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => {
          // Z-Library reader 子域经常存在证书不匹配，信任并继续加载
          Logger.w(TAG, `ssl error on reader, accepting`);
          try {
            event.handler.handleConfirm();
          } catch (e) {
            Logger.w(TAG, `ssl handleConfirm failed: ${(e as Error).message}`);
          }
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          const code: number = event.response.getResponseCode();
          if (code >= 400) {
            this.clearLoadTimeout();
            Logger.w(TAG, `http error ${code} on reader`);
            this.errorMsg = `HTTP ${code}：服务器拒绝请求，请尝试其他镜像站`;
          }
        });
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          if (!this.fullscreen) {
            this.topBar();

            if (this.progress > 0 && this.progress < 100) {
              Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
                .color(AppColors.brandPrimary)
                .height(2)
                .width('100%');
            }
          }

          this.webView();

          if (!this.fullscreen && this.fontMenuOpen) {
            this.fontMenu();
          }
        }
        .width('100%')
        .height('100%');

        // 全屏时浮动恢复按钮
        if (this.fullscreen) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_fullscreen')).width(18).height(18);
          }
          .width(40)
          .height(40)
          .backgroundColor('#88000000')
          .margin({ top: 16, right: 16 })
          .onClick(() => this.toggleFullscreen());
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      const info: NavPathInfo | undefined = ctx.pathInfo;
      if (info !== undefined && info.param !== undefined) {
        const p: ReaderParams = info.param as ReaderParams;
        this.title = p.title;
        this.bookId = p.bookId !== undefined ? p.bookId : '';
        this.injectCookies();
        this.loadSavedPosition();
        this.url = p.url;
      }
    });
  }
}
