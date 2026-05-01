/*
 * DomainSelectorDialog.ets
 * 镜像线路选择 + 延迟可视化。
 *
 * 上游传入：
 *   - onSelect(domain)：用户敲定线路时回调（弹窗会先关闭再回调）
 *   - onCustomTap()：用户点"自定义线路"时回调（弹窗先关闭再回调，由调用方再唤起 CustomDomainDialog）
 *
 * 内部：
 *   - @StorageLink AppStorageKeys.SPEED_RESULTS：实时反映 SpeedTestVM 的并发测速进度
 *   - @StorageLink AppStorageKeys.DOMAIN：当前域名（用于高亮）
 */

import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { DomainTestResult } from '../model/DomainTestResult';
import { DomainManifest } from '../api/DomainManifest';
import { SpeedTestVM } from '../viewmodel/SpeedTestVM';

/** Z-Library 官方 .onion 地址（需用 Tor Browser 打开。多年不变。） */
const ZLIB_ONION_URL: string = 'http://loginzlib2vrak5zzpcocc3ouizykn6k5qecgj2tzlnab5wcbqhembyd.onion';

@CustomDialog
export struct DomainSelectorDialog {
  controller?: CustomDialogController;
  onSelect: (domain: string) => void = (_: string): void => {};
  onCustomTap: () => void = (): void => {};

  @StorageLink(AppStorageKeys.DOMAIN) private currentDomain: string = '';
  @StorageLink(AppStorageKeys.SPEED_RESULTS) private results: DomainTestResult[] = [];
  @State private retesting: boolean = false;

  /** 把 results + 当前生效镜像列表（内置 + 远程）合并去重，保证未测的也能显示。 */
  private buildDisplayList(): DomainTestResult[] {
    const map: Map<string, DomainTestResult> = new Map<string, DomainTestResult>();
    for (let i = 0; i < this.results.length; i++) {
      map.set(this.results[i].domain, this.results[i]);
    }
    const all: string[] = DomainManifest.getActiveDomains();
    for (let i = 0; i < all.length; i++) {
      if (!map.has(all[i])) {
        map.set(all[i], new DomainTestResult(all[i], null));
      }
    }
    if (this.currentDomain.length > 0 && !map.has(this.currentDomain)) {
      map.set(this.currentDomain, new DomainTestResult(this.currentDomain, null));
    }
    const arr: DomainTestResult[] = [];
    map.forEach((v: DomainTestResult) => arr.push(v));
    arr.sort((a: DomainTestResult, b: DomainTestResult): number => {
      if (a.domain === this.currentDomain) {
        return -1;
      }
      if (b.domain === this.currentDomain) {
        return 1;
      }
      const la: number = a.latencyMs !== null && a.latencyMs > 0 ? a.latencyMs : 999999;
      const lb: number = b.latencyMs !== null && b.latencyMs > 0 ? b.latencyMs : 999999;
      return la - lb;
    });
    return arr;
  }

  private async doRetest(): Promise<void> {
    if (this.retesting) return;
    this.retesting = true;
    try {
      await SpeedTestVM.testAll(true);
    } finally {
      this.retesting = false;
    }
  }

  private handleSelect(domain: string): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onSelect(domain);
  }

  private handleCustom(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onCustomTap();
  }

  /** 复制 .onion 地址到剪贴板，引导用 Tor Browser 打开。 */
  private async copyOnionUrl(): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, ZLIB_ONION_URL);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      DomainSelectorDialog.toast($r('app.string.domain_dialog_onion_copied'));
    } catch (err) {
      const e: Error = err as Error;
      DomainSelectorDialog.toast(e.message);
    }
  }

  private static toast(msg: ResourceStr | string): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 2500 };
      promptAction.openToast(opts);
    } catch {
      // ignore
    }
  }

  // ─── 子构件 ──────────────────────────────

  @Builder
  private latencyBadge(item: DomainTestResult) {
    if (item.latencyMs === null) {
      Text(this.retesting ? '...' : '—')
        .fontSize(AppFontSize.caption)
        .fontColor(AppColors.textTertiary);
    } else if (item.latencyMs < 0) {
      Image($r('app.media.ic_error_x')).width(14).height(14);
    } else {
      Text(`${item.latencyMs}ms`)
        .fontSize(AppFontSize.caption)
        .fontColor(item.latencyMs <= 200
          ? AppColors.progressGreen
          : (item.latencyMs <= 800 ? AppColors.progressYellow : AppColors.progressOrange))
        .fontWeight(FontWeight.Medium);
    }
  }

  @Builder
  private domainRow(item: DomainTestResult) {
    Row({ space: 12 }) {
      // 选中圆点
      Stack() {
        Circle({ width: 16, height: 16 })
          .fill(item.domain === this.currentDomain ? AppColors.brandPrimary : Color.Transparent)
          .stroke(item.domain === this.currentDomain ? Color.Transparent : AppColors.divider)
          .strokeWidth(1.5);
        if (item.domain === this.currentDomain) {
          Image($r('app.media.ic_check')).width(10).height(10);
        }
      }
      .width(16)
      .height(16);

      Text(item.domain)
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      this.latencyBadge(item);
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .borderRadius(AppRadius.sm)
    .backgroundColor(item.domain === this.currentDomain ? AppColors.brandPrimaryLight : Color.Transparent)
    .onClick(() => this.handleSelect(item.domain));
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text($r('app.string.domain_dialog_title'))
          .fontSize(AppFontSize.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1);

        Button() {
          Image($r('app.media.ic_close')).width(16).height(16);
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.controller !== undefined) {
            this.controller.close();
          }
        });
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 16, bottom: 8 });

      // 列表
      List({ space: 4 }) {
        ForEach(this.buildDisplayList(), (item: DomainTestResult) => {
          ListItem() {
            this.domainRow(item);
          }
        }, (item: DomainTestResult) => item.domain);
      }
      .layoutWeight(1)
      .padding({ left: 12, right: 12 })
      .scrollBar(BarState.Auto);

      // 底部操作
      Row({ space: 12 }) {
        Button() {
          Row({ space: 6 }) {
            if (this.retesting) {
              LoadingProgress().width(16).height(16).color(AppColors.brandPrimary);
            }
            Text($r('app.string.domain_dialog_retest'))
              .fontSize(AppFontSize.body)
              .fontColor(AppColors.brandPrimary);
          }
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor(AppColors.brandPrimaryLight)
        .borderRadius(AppRadius.pill)
        .onClick(() => this.doRetest());

        Button($r('app.string.domain_dialog_custom'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(AppColors.surfaceAlt)
          .fontColor(AppColors.textPrimary)
          .borderRadius(AppRadius.pill)
          .onClick(() => this.handleCustom());
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 });

      // Tor 兑底：复制 .onion 地址。不内嵌 Tor，由用户自己用 Tor Browser 打开。
      Row({ space: 4 }) {
        Text($r('app.string.domain_dialog_onion_hint'))
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.textTertiary);
        Text($r('app.string.domain_dialog_onion_copy'))
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.brandPrimary)
          .fontWeight(FontWeight.Medium)
          .onClick((): void => { this.copyOnionUrl(); });
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, bottom: 16 });
    }
    .width('92%')
    .height('70%')
    .constraintSize({ maxWidth: 520 })
    .backgroundColor('#E6FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thick, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    })
    .borderRadius(AppRadius.lg);
  }
}
