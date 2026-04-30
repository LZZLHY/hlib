/*
 * LoginPage.ets — 登录页（P1.5 Navigation 版）
 *
 * 变更：
 *   - 去 @Entry，加 export struct
 *   - build() 包 NavDestination
 *   - router.replaceUrl -> AppRouter.replace
 */

import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys } from '../storage/AppStorageKeys';
import { AuthVM } from '../viewmodel/AuthVM';
import { HttpClient } from '../api/HttpClient';
import { CfBlockedError } from '../api/ApiTypes';
import { ErrorHelper } from '../utils/ErrorHelper';
import { DomainSelectorDialog } from '../components/DomainSelectorDialog';
import { CustomDomainDialog } from '../components/CustomDomainDialog';
import { CfBlockedDialog } from '../components/CfBlockedDialog';
import { AppRouter, Routes } from '../utils/AppRouter';
import { QrLoginParser, QrCredential } from '../utils/QrLoginParser';
import { Logger } from '../utils/Logger';

const TAG: string = 'LoginPage';
const EMAIL_RE: RegExp = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

@Component
export struct LoginPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // ── 表单状态 ──
  @State private email: string = '';
  @State private password: string = '';
  @State private userId: string = '';
  @State private userKey: string = '';
  @State private isTokenMode: boolean = false;
  @State private showPassword: boolean = false;
  @State private isLoading: boolean = false;
  @State private emailError: string = '';
  @State private passwordError: string = '';
  @State private tokenError: string = '';

  @StorageLink(AppStorageKeys.DOMAIN) private domain: string = '';

  // ── 弹窗 ──
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

  private cfController: CustomDialogController = new CustomDialogController({
    builder: CfBlockedDialog({
      onSwitchLine: (): void => this.openDomainSelector(),
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
  });

  // ── 行为 ──

  private openDomainSelector(): void {
    this.domainController.open();
  }

  private openCustomDomain(): void {
    this.customDomainController.open();
  }

  /** 调系统扫码服务，从结果中解析 userId/userKey，成功则直接 token 登录。 */
  private onScanQr(): void {
    if (this.isLoading) {
      return;
    }
    // 守卫：部分设备无扫码 syscap
    if (!canIUse('SystemCapability.Multimedia.Scan.Core') ||
        !canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
      LoginPage.toast('当前设备不支持扫码', 1800);
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx === null || ctx === undefined) {
      LoginPage.toast('上下文未就绪', 1500);
      return;
    }
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: true,
    };
    try {
      scanBarcode.startScanForResult(ctx, options)
        .then((result: scanBarcode.ScanResult): void => {
          const value: string = LoginPage.readScanValue(result);
          this.handleScanResult(value);
        })
        .catch((err: BusinessError): void => {
          if (err && err.code !== undefined && err.code !== 0) {
            Logger.w(TAG, `scan canceled or failed: code=${err.code} msg=${err.message}`);
          }
        });
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Logger.w(TAG, `startScanForResult failed: code=${err.code} msg=${err.message}`);
      LoginPage.toast('扫码服务不可用', 1800);
    }
  }

  private static readScanValue(result: scanBarcode.ScanResult): string {
    if (result === undefined || result === null) return '';
    const v: string | undefined = result.originalValue;
    return v !== undefined ? v : '';
  }

  private handleScanResult(raw: string): void {
    const cred: QrCredential | null = QrLoginParser.parse(raw);
    if (cred === null) {
      LoginPage.toast('二维码格式不识别', 2000);
      return;
    }
    // 切到 token 模式 + 填入 + 自动提交
    this.isTokenMode = true;
    this.userId = cred.userId;
    this.userKey = cred.userKey;
    this.tokenError = '';
    this.submit().catch((e: Error): void => {
      Logger.w(TAG, `submit after scan failed: ${e.message}`);
    });
  }

  private applyDomain(d: string): void {
    AppStorage.setOrCreate<string>(AppStorageKeys.DOMAIN, d);
    HttpClient.instance.setDomain(d);
    LoginPage.toast(`已切换到 ${d}`, 1500);
  }

  private static toast(msg: string, duration: number = 2000): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: duration };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, `toast failed: ${(e as Error).message}`);
    }
  }

  private async submit(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    if (!this.validate()) {
      return;
    }
    this.isLoading = true;
    try {
      if (this.isTokenMode) {
        await AuthVM.loginWithToken(this.userId.trim(), this.userKey.trim());
      } else {
        await AuthVM.login(this.email.trim(), this.password);
      }
      Logger.i(TAG, 'login success, replace to MainPage');
      AppRouter.replace(Routes.MAIN);
    } catch (err) {
      this.handleLoginError(err);
    } finally {
      this.isLoading = false;
    }
  }

  private handleLoginError(err: Object): void {
    if (err instanceof CfBlockedError) {
      this.cfController.open();
      return;
    }
    const msg: string = ErrorHelper.describe(err, '登录');
    Logger.w(TAG, `login err: ${(err as Error).message}`);
    LoginPage.toast(msg, 2200);
  }

  private validate(): boolean {
    let ok: boolean = true;
    if (this.isTokenMode) {
      this.tokenError = '';
      if (this.userId.trim().length === 0 || this.userKey.trim().length === 0) {
        this.tokenError = '请输入 userId 与 userKey';
        ok = false;
      }
    } else {
      this.emailError = '';
      this.passwordError = '';
      const e: string = this.email.trim();
      if (e.length === 0) {
        this.emailError = '请输入邮箱';
        ok = false;
      } else if (!EMAIL_RE.test(e)) {
        this.emailError = '邮箱格式不正确';
        ok = false;
      }
      if (this.password.length === 0) {
        this.passwordError = '请输入密码';
        ok = false;
      } else if (this.password.length < 6) {
        this.passwordError = '密码至少 6 位';
        ok = false;
      }
    }
    return ok;
  }

  // ── UI ──

  @Builder
  private appBar() {
    Row() {
      // domain pill
      Row({ space: 6 }) {
        Circle({ width: 8, height: 8 }).fill(AppColors.successTeal);
        Text(this.domain.length > 0 ? this.domain : 'pkuedu.online')
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Image($r('app.media.ic_chevron_down')).width(12).height(12);
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(AppColors.surfaceAlt)
      .borderRadius(AppRadius.pill)
      .onClick(() => this.openDomainSelector());

      Blank().layoutWeight(1);
    }
    .width('100%')
    .padding({ left: AppSpace.s16, right: AppSpace.s16, top: AppSpace.s12, bottom: AppSpace.s8 });
  }

  @Builder
  private hero() {
    Column({ space: 16 }) {
      Stack() {
        Circle({ width: 80, height: 80 })
          .fill(AppColors.brandPrimaryLight);
        Image($r('app.media.startIcon'))
          .width(48)
          .height(48);
      }
      .width(80)
      .height(80);

      Text($r('app.string.login_welcome'))
        .fontSize(AppFontSize.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary);

      Text($r('app.string.login_subtitle'))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textSecondary);
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%');
  }

  @Builder
  private formField(label: ResourceStr, error: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textSecondary)
        .alignSelf(ItemAlign.Start);
      // 输入框留给下方各自实现
      if (error.length > 0) {
        Text(error)
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.error)
          .alignSelf(ItemAlign.Start);
      }
    }
  }

  @Builder
  private emailMode() {
    Column({ space: 16 }) {
      // email
      Column({ space: 4 }) {
        Text($r('app.string.login_email'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textSecondary)
          .alignSelf(ItemAlign.Start);
        TextInput({ placeholder: 'name@example.com', text: this.email })
          .type(InputType.Email)
          .height(48)
          .borderRadius(AppRadius.md)
          .backgroundColor(AppColors.surfaceAlt)
          .fontColor(AppColors.textPrimary)
          .placeholderColor(AppColors.textTertiary)
          .borderWidth(this.emailError.length > 0 ? 1 : 0)
          .borderColor(AppColors.error)
          .enabled(!this.isLoading)
          .onChange((v: string) => {
            this.email = v;
            if (this.emailError.length > 0) this.emailError = '';
          });
        if (this.emailError.length > 0) {
          Text(this.emailError)
            .fontSize(AppFontSize.caption)
            .fontColor(AppColors.error)
            .alignSelf(ItemAlign.Start);
        }
      }
      .width('100%');

      // password
      Column({ space: 4 }) {
        Text($r('app.string.login_password'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textSecondary)
          .alignSelf(ItemAlign.Start);
        Stack({ alignContent: Alignment.End }) {
          TextInput({ placeholder: '••••••••', text: this.password })
            .type(this.showPassword ? InputType.Normal : InputType.Password)
            .height(48)
            .borderRadius(AppRadius.md)
            .backgroundColor(AppColors.surfaceAlt)
            .fontColor(AppColors.textPrimary)
            .placeholderColor(AppColors.textTertiary)
            .borderWidth(this.passwordError.length > 0 ? 1 : 0)
            .borderColor(AppColors.error)
            .padding({ left: 12, right: 48 })
            .enabled(!this.isLoading)
            .onChange((v: string) => {
              this.password = v;
              if (this.passwordError.length > 0) this.passwordError = '';
            });
          // eye toggle
          Button() {
            Text(this.showPassword ? '🙈' : '👁')
              .fontSize(18);
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .margin({ right: 6 })
          .onClick(() => {
            this.showPassword = !this.showPassword;
          });
        }
        .width('100%');

        if (this.passwordError.length > 0) {
          Text(this.passwordError)
            .fontSize(AppFontSize.caption)
            .fontColor(AppColors.error)
            .alignSelf(ItemAlign.Start);
        }
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private tokenMode() {
    Column({ space: 16 }) {
      Column({ space: 4 }) {
        Text($r('app.string.login_userid'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textSecondary)
          .alignSelf(ItemAlign.Start);
        TextInput({ placeholder: 'remix_userid', text: this.userId })
          .height(48)
          .borderRadius(AppRadius.md)
          .backgroundColor(AppColors.surfaceAlt)
          .fontColor(AppColors.textPrimary)
          .enabled(!this.isLoading)
          .onChange((v: string) => {
            this.userId = v;
            if (this.tokenError.length > 0) this.tokenError = '';
          });
      }
      .width('100%');

      Column({ space: 4 }) {
        Text($r('app.string.login_userkey'))
          .fontSize(AppFontSize.bodySm)
          .fontColor(AppColors.textSecondary)
          .alignSelf(ItemAlign.Start);
        TextInput({ placeholder: 'remix_userkey', text: this.userKey })
          .height(48)
          .borderRadius(AppRadius.md)
          .backgroundColor(AppColors.surfaceAlt)
          .fontColor(AppColors.textPrimary)
          .enabled(!this.isLoading)
          .onChange((v: string) => {
            this.userKey = v;
            if (this.tokenError.length > 0) this.tokenError = '';
          });
      }
      .width('100%');

      if (this.tokenError.length > 0) {
        Text(this.tokenError)
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.error)
          .alignSelf(ItemAlign.Start);
      }
    }
    .width('100%');
  }

  /**
   * 登录页按返回键 → 直接退出 Ability。
   * 不能让 Navigation 默认 pop——会让栈空，露出 RootPage 的绿色根占位。
   */
  private onLoginBackPressed = (): boolean => {
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
      Column() {
        Blank().height(this.statusBarHeight)
        this.appBar();

        Scroll() {
          Column({ space: 24 }) {
            Blank().height(20);

            this.hero();

            Blank().height(8);

            if (this.isTokenMode) {
              this.tokenMode();
            } else {
              this.emailMode();
            }

            // 扫码 + 模式切换
            Row({ space: 12 }) {
              // 扫一扫
              Row({ space: 6 }) {
                Image($r('app.media.ic_scan_qr')).width(16).height(16);
                Text('扫码登录')
                  .fontSize(AppFontSize.bodySm)
                  .fontColor(AppColors.brandPrimary);
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(AppRadius.pill)
              .backgroundColor(AppColors.brandPrimaryLight)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
              .onClick(() => this.onScanQr());

              Blank().layoutWeight(1);

              Text(this.isTokenMode
                ? '使用邮箱密码登录'
                : '使用 Token 登录?')
                .fontSize(AppFontSize.bodySm)
                .fontColor(AppColors.brandPrimary)
                .onClick(() => {
                  this.isTokenMode = !this.isTokenMode;
                  this.emailError = '';
                  this.passwordError = '';
                  this.tokenError = '';
                });
            }
            .width('100%');

            // 提交按钮
            Button() {
              Row({ space: 8 }) {
                if (this.isLoading) {
                  LoadingProgress().width(20).height(20).color(AppColors.textOnPrimary);
                }
                Text($r('app.string.login_button'))
                  .fontSize(AppFontSize.bodyLg)
                  .fontColor(AppColors.textOnPrimary)
                  .fontWeight(FontWeight.Bold);
              }
            }
            .width('100%')
            .height(52)
            .backgroundColor(AppColors.brandPrimary)
            .borderRadius(AppRadius.pill)
            .opacity(this.isLoading ? 0.7 : 1)
            .onClick(() => this.submit());

            // 注册提示
            Text($r('app.string.login_no_account_hint'))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary)
              .textAlign(TextAlign.Center)
              .padding({ top: 16 });

            Blank().height(40);
          }
          .width('100%')
          .padding({ left: AppSpace.s24, right: AppSpace.s24 });
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(this.onLoginBackPressed);
  }
}
