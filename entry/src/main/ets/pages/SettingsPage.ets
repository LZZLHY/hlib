/*
 * SettingsPage.ets — 设置完整页（P3）
 *
 * Sections：
 *   账户：头像 + 用户名 + 邮箱 + 剩余下载次数 + 退出登录
 *   网络：当前线路（点开 DomainSelector）+ 重新测速
 *   外观：主题 三段式（跟随系统 / 浅色 / 深色）+ 即时生效
 *   下载：下载历史入口
 *   关于：版本号
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { AppColors } from '../theme/AppColors';
import { AppFontSize, AppRadius, AppSpace } from '../theme/AppTextStyles';
import { AppStorageKeys, ThemeMode } from '../storage/AppStorageKeys';
import { User } from '../model/User';
import { AuthVM } from '../viewmodel/AuthVM';
import { SpeedTestVM } from '../viewmodel/SpeedTestVM';
import { DownloadVM } from '../viewmodel/DownloadVM';
import { HomeVM } from '../viewmodel/HomeVM';
import { LANGUAGE_FILTERS, FilterItem } from '../api/SearchFilters';
import { FavoritesStore } from '../storage/FavoritesStore';
import { DownloadHistoryStore } from '../storage/DownloadHistoryStore';
import { ReadingPositionStore } from '../storage/ReadingPositionStore';
import { PendingDownloadStore } from '../storage/PendingDownloadStore';
import { HttpClient } from '../api/HttpClient';
import { DomainManifest } from '../api/DomainManifest';
import { PreferencesStore } from '../storage/PreferencesStore';
import { DomainSelectorDialog } from '../components/DomainSelectorDialog';
import { CustomDomainDialog } from '../components/CustomDomainDialog';
import { AppRouter, Routes } from '../utils/AppRouter';
import { Logger } from '../utils/Logger';

const TAG: string = 'SettingsPage';

type DownloadDir = 'default' | 'cache';

@Component
export struct SettingsPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp(AppStorageKeys.USER) private user: User | null = null;
  @StorageProp(AppStorageKeys.DOMAIN) private domain: string = '';
  @StorageLink(AppStorageKeys.THEME_MODE) private themeMode: ThemeMode = 'system';
  @StorageLink(AppStorageKeys.LOCALE) private locale: string = '';
  @StorageLink(AppStorageKeys.DOWNLOAD_PATH) private downloadPath: string = '';

  @State private appVersion: string = '1.0.0';

  // ── 网络加固：代理与 Manifest UI 状态 ──
  @State private proxyEnabled: boolean = false;
  @State private proxyHost: string = '';
  @State private proxyPortStr: string = '';
  @State private manifestEnabled: boolean = false;
  @State private manifestUrl: string = '';
  @State private manifestVersion: string = '';
  @State private manifestCount: number = 0;
  @State private manifestRefreshing: boolean = false;

  /** 首页推荐内容地区（LANGUAGE_FILTERS 的 key，如 'all'/'chinese'/'english'）。 */
  @State private contentLang: string = 'all';

  aboutToAppear(): void {
    this.loadNetworkPrefs().catch((e: Object): void => {
      Logger.w(TAG, `loadNetworkPrefs failed: ${(e as Error).message}`);
    });
  }

  private async loadNetworkPrefs(): Promise<void> {
    this.proxyEnabled = await PreferencesStore.getBoolean('settings', AppStorageKeys.PROXY_ENABLED, false);
    this.proxyHost = await PreferencesStore.getString('settings', AppStorageKeys.PROXY_HOST, '');
    const port: number = await PreferencesStore.getNumber('settings', AppStorageKeys.PROXY_PORT, 0);
    this.proxyPortStr = port > 0 ? port.toString() : '';

    this.manifestEnabled = DomainManifest.isEnabled();
    this.manifestUrl = DomainManifest.getUrl();
    this.manifestVersion = DomainManifest.getLastVersion();
    this.manifestCount = DomainManifest.getRemoteCount();

    const lang: string = await PreferencesStore.getString('settings', AppStorageKeys.CONTENT_LANG, '');
    this.contentLang = lang.length === 0 ? 'all' : lang;
  }

  /** 切换首页内容地区。写盘 + 同步到 HttpClient (siteLanguageV2 cookie + Accept-Language) + 触发 HomeVM.refresh()。 */
  private async setContentLang(key: string): Promise<void> {
    if (key === this.contentLang) {
      return;
    }
    this.contentLang = key;
    await PreferencesStore.putString('settings', AppStorageKeys.CONTENT_LANG, key);
    // 关键：同步到 HttpClient，下一次请求才会带上 siteLanguageV2 cookie
    HttpClient.instance.setSiteLanguage(key);
    SettingsPage.toastResource($r('app.string.settings_content_lang_changed'));
    HomeVM.refresh().catch((e: Object): void => {
      Logger.w(TAG, `home refresh after lang change failed: ${(e as Error).message}`);
    });
  }

  private domainController: CustomDialogController = new CustomDialogController({
    builder: DomainSelectorDialog({
      onSelect: (d: string): void => this.applyDomain(d),
      onCustomTap: (): void => this.openCustomDomain(),
    }),
    autoCancel: true,
    customStyle: true,
  });

  private customDomainController: CustomDialogController = new CustomDialogController({
    builder: CustomDomainDialog({
      onConfirm: (d: string): void => this.applyDomain(d),
    }),
    autoCancel: true,
    customStyle: true,
  });

  // ── Actions ──

  private applyDomain(d: string): void {
    AppStorage.setOrCreate<string>(AppStorageKeys.DOMAIN, d);
    HttpClient.instance.setDomain(d);
    SettingsPage.toast(`已切换到 ${d}`);
  }

  private openDomainSelector(): void {
    this.domainController.open();
  }

  private openCustomDomain(): void {
    this.customDomainController.open();
  }

  private async retestSpeed(): Promise<void> {
    SettingsPage.toast('开始测速…');
    try {
      await SpeedTestVM.testAll(true);
      SettingsPage.toast('测速完成');
    } catch (e) {
      Logger.w(TAG, `speedTest failed: ${(e as Error).message}`);
      SettingsPage.toast('测速失败');
    }
  }

  private setTheme(mode: ThemeMode): void {
    this.themeMode = mode;
    SettingsPage.applyThemeMode(this.getUIContext().getHostContext() as common.UIAbilityContext, mode);
  }

  /** 切换应用语言。'' 表示跟随系统。 */
  private setLocale(value: string): void {
    this.locale = value;
    try {
      // 空串 → 清除应用偏好语言（跟随系统）
      i18n.System.setAppPreferredLanguage(value.length === 0 ? '' : value);
      SettingsPage.toast(value.length === 0 ? '已跟随系统' : `已切换到 ${value}`);
    } catch (e) {
      Logger.w(TAG, `setAppPreferredLanguage failed: ${(e as Error).message}`);
    }
  }

  private setDownloadDir(dir: DownloadDir): void {
    this.downloadPath = dir === 'cache' ? 'cache' : '';
    SettingsPage.toast(dir === 'cache' ? '已切换到缓存目录' : '已切换到默认目录');
  }

  private currentDownloadDir(): DownloadDir {
    return this.downloadPath === 'cache' ? 'cache' : 'default';
  }

  private confirmClearCache(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.settings_clear_cache'),
      message: $r('app.string.settings_clear_cache_msg'),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.common_ok'),
        fontColor: '#E53935',
        action: (): void => {
          SettingsPage.runClearCache().catch((e: Error): void => {
            Logger.w(TAG, `clearCache failed: ${e.message}`);
          });
        },
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        fontColor: '#666666',
        action: (): void => {},
      },
    });
  }

  private static async runClearCache(): Promise<void> {
    await FavoritesStore.clear();
    await DownloadHistoryStore.clear();
    await ReadingPositionStore.clear();
    await PendingDownloadStore.clear();
    AppStorage.setOrCreate<number[]>(AppStorageKeys.FAVORITE_IDS, []);
    AppStorage.setOrCreate<object[]>(AppStorageKeys.FAVORITE_BOOKS, []);
    AppStorage.setOrCreate<object[]>(AppStorageKeys.DOWNLOAD_TASKS, []);
    await DownloadVM.refreshHistory();
    SettingsPage.toastResource($r('app.string.settings_clear_cache_done'));
  }

  private static toastResource(msg: ResourceStr): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 1500 };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, 'toast failed');
    }
  }

  private static applyThemeMode(ctx: common.UIAbilityContext | null, mode: ThemeMode): void {
    if (ctx === null) {
      return;
    }
    let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === 'light') {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (mode === 'dark') {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      ctx.getApplicationContext().setColorMode(target);
    } catch (e) {
      Logger.w(TAG, `setColorMode failed: ${(e as Error).message}`);
    }
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.settings_logout_confirm'),
      message: '',
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.settings_logout'),
        fontColor: '#E53935',
        action: (): void => {
          AuthVM.logout()
            .then((): void => {
              AppRouter.replace(Routes.LOGIN);
            })
            .catch((e: Error): void => {
              Logger.w(TAG, `logout failed: ${e.message}`);
              SettingsPage.toast(`退出失败：${e.message}`);
            });
        },
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        fontColor: '#666666',
        action: (): void => {},
      },
    });
  }

  private goHistory(): void {
    AppRouter.push(Routes.HISTORY);
  }

  private static toast(msg: string): void {
    try {
      const opts: promptAction.ShowToastOptions = { message: msg, duration: 1500 };
      promptAction.openToast(opts);
    } catch (e) {
      Logger.w(TAG, 'toast failed');
    }
  }

  // ── Builders ──

  @Builder
  private topBar() {
    Column() {
      Blank().height(this.statusBarHeight)
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_back')).width(22).height(22);
        }
        .width(40)
        .height(40)
        .backgroundColor(AppColors.surfaceAlt)
        .onClick(() => AppRouter.pop());

        Text($r('app.string.settings_title'))
          .fontSize(AppFontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
    });
  }

  @Builder
  private sectionHeader(label: ResourceStr) {
    Text(label)
      .fontSize(AppFontSize.bodySm)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColors.textTertiary)
      .padding({ top: AppSpace.s16, bottom: AppSpace.s8 });
  }

  @Builder
  private accountCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        // 头像（首字母）
        Stack() {
          Column()
            .width(48)
            .height(48)
            .backgroundColor(AppColors.brandPrimary)
            .borderRadius(24);
          Text(this.userInitial())
            .fontSize(AppFontSize.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textOnPrimary);
        }
        .width(48)
        .height(48);

        Column({ space: 4 }) {
          Text(this.user !== null && this.user.name.length > 0 ? this.user.name : '未登录')
            .fontSize(AppFontSize.body)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary);
          if (this.user !== null && this.user.email.length > 0) {
            Text(this.user.email)
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%');

      if (this.user !== null) {
        Divider().color(AppColors.divider).strokeWidth(0.5);

        Row() {
          Text($r('app.string.settings_downloads_left'))
            .fontSize(AppFontSize.bodySm)
            .fontColor(AppColors.textSecondary)
            .layoutWeight(1);
          Text(`${this.user.downloadsLeft} / ${this.user.downloadsLimit !== undefined ? this.user.downloadsLimit : 10}`)
            .fontSize(AppFontSize.bodySm)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary);
        }
        .width('100%');

        Divider().color(AppColors.divider).strokeWidth(0.5);

        Row() {
          Text($r('app.string.settings_logout'))
            .fontSize(AppFontSize.body)
            .fontColor(AppColors.error)
            .layoutWeight(1);
          Image($r('app.media.ic_chevron_right')).width(16).height(16);
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .onClick(() => this.confirmLogout());
      }
    }
    .width('100%')
    .padding(AppSpace.s16)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private settingRow(title: ResourceStr, value: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1);
      Text(value)
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ right: 4 });
      Image($r('app.media.ic_chevron_right')).width(16).height(16);
    }
    .width('100%')
    .padding({ left: AppSpace.s16, right: AppSpace.s16, top: 14, bottom: 14 })
    .onClick(() => onTap());
  }

  @Builder
  private networkCard() {
    Column() {
      this.settingRow(
        $r('app.string.settings_current_line'),
        this.domain.length > 0 ? this.domain : '默认',
        (): void => this.openDomainSelector(),
      );
      Divider().color(AppColors.divider).strokeWidth(0.5).margin({ left: AppSpace.s16 });
      this.settingRow(
        $r('app.string.settings_speed_test'),
        '',
        (): void => {
          this.retestSpeed();
        },
      );
    }
    .width('100%')
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private manifestCard() {
    Column({ space: 12 }) {
      // 标题 + 开关
      Row() {
        Text($r('app.string.settings_manifest_title'))
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.manifestEnabled })
          .onChange((on: boolean): void => {
            this.toggleManifest(on).catch((e: Object): void => {
              Logger.w(TAG, `toggleManifest: ${(e as Error).message}`);
            });
          });
      }
      .width('100%');

      // URL 输入（启用时才显示）
      if (this.manifestEnabled) {
        Column({ space: 6 }) {
          Text($r('app.string.settings_manifest_url'))
            .fontSize(AppFontSize.bodySm)
            .fontColor(AppColors.textSecondary)
            .alignSelf(ItemAlign.Start);
          TextInput({ placeholder: $r('app.string.settings_manifest_url_hint'), text: this.manifestUrl })
            .height(40)
            .borderRadius(AppRadius.sm)
            .backgroundColor(AppColors.surfaceAlt)
            .fontSize(AppFontSize.bodySm)
            .onChange((v: string): void => {
              this.setManifestUrl(v).catch((e: Object): void => {
                Logger.w(TAG, `setManifestUrl: ${(e as Error).message}`);
              });
            });
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);

        // 状态行
        Row() {
          Text(this.manifestCount > 0
            ? `${this.manifestVersion.length > 0 ? this.manifestVersion : '—'} · ${this.manifestCount}`
            : '')
            .fontSize(AppFontSize.caption)
            .fontColor(AppColors.textTertiary)
            .layoutWeight(1);
          if (this.manifestCount === 0) {
            Text($r('app.string.settings_manifest_empty'))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textTertiary);
          }
        }
        .width('100%');

        Row({ space: 8 }) {
          Button($r('app.string.settings_manifest_refresh'))
            .layoutWeight(1)
            .height(36)
            .fontSize(AppFontSize.bodySm)
            .backgroundColor(AppColors.brandPrimaryLight)
            .fontColor(AppColors.brandPrimary)
            .borderRadius(AppRadius.sm)
            .enabled(!this.manifestRefreshing)
            .onClick((): void => {
              this.refreshManifest().catch((e: Object): void => {
                Logger.w(TAG, `refreshManifest: ${(e as Error).message}`);
              });
            });
          Button($r('app.string.settings_manifest_clear'))
            .layoutWeight(1)
            .height(36)
            .fontSize(AppFontSize.bodySm)
            .backgroundColor(AppColors.surfaceAlt)
            .fontColor(AppColors.textPrimary)
            .borderRadius(AppRadius.sm)
            .onClick((): void => {
              this.clearManifestCache().catch((e: Object): void => {
                Logger.w(TAG, `clearManifestCache: ${(e as Error).message}`);
              });
            });
        }
        .width('100%');
      }
    }
    .width('100%')
    .padding(AppSpace.s16)
    .margin({ top: 8 })
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private proxyCard() {
    Column({ space: 12 }) {
      // 标题 + 开关
      Row() {
        Text($r('app.string.settings_proxy_title'))
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.proxyEnabled })
          .onChange((on: boolean): void => {
            this.toggleProxy(on).catch((e: Object): void => {
              Logger.w(TAG, `toggleProxy: ${(e as Error).message}`);
            });
          });
      }
      .width('100%');

      // 启用时展开 host / port 输入
      if (this.proxyEnabled) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text($r('app.string.settings_proxy_host'))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textSecondary);
            TextInput({ placeholder: $r('app.string.settings_proxy_host_hint'), text: this.proxyHost })
              .height(40)
              .borderRadius(AppRadius.sm)
              .backgroundColor(AppColors.surfaceAlt)
              .fontSize(AppFontSize.bodySm)
              .onChange((v: string): void => {
                this.setProxyHost(v).catch((e: Object): void => {
                  Logger.w(TAG, `setProxyHost: ${(e as Error).message}`);
                });
              });
          }
          .layoutWeight(2)
          .alignItems(HorizontalAlign.Start);

          Column({ space: 4 }) {
            Text($r('app.string.settings_proxy_port'))
              .fontSize(AppFontSize.caption)
              .fontColor(AppColors.textSecondary);
            TextInput({ placeholder: $r('app.string.settings_proxy_port_hint'), text: this.proxyPortStr })
              .type(InputType.Number)
              .height(40)
              .borderRadius(AppRadius.sm)
              .backgroundColor(AppColors.surfaceAlt)
              .fontSize(AppFontSize.bodySm)
              .onChange((v: string): void => {
                this.setProxyPort(v).catch((e: Object): void => {
                  Logger.w(TAG, `setProxyPort: ${(e as Error).message}`);
                });
              });
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%');

        Text($r('app.string.settings_proxy_note'))
          .fontSize(AppFontSize.caption)
          .fontColor(AppColors.textTertiary)
          .alignSelf(ItemAlign.Start);
      }
    }
    .width('100%')
    .padding(AppSpace.s16)
    .margin({ top: 8 })
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private contentLangCard() {
    Column({ space: 10 }) {
      Text($r('app.string.settings_content_lang_title'))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start);

      // 横向滚动按钮列表（10 种语言 + 不限）
      Scroll() {
        Row({ space: 8 }) {
          ForEach(LANGUAGE_FILTERS, (item: FilterItem): void => {
            Button() {
              Text(item.label)
                .fontSize(AppFontSize.bodySm)
                .fontColor(this.contentLang === item.key ? AppColors.textOnPrimary : AppColors.textPrimary)
                .fontWeight(this.contentLang === item.key ? FontWeight.Bold : FontWeight.Regular);
            }
            .height(34)
            .padding({ left: 14, right: 14 })
            .backgroundColor(this.contentLang === item.key ? AppColors.brandPrimary : AppColors.surfaceAlt)
            .borderRadius(AppRadius.pill)
            .onClick((): void => {
              this.setContentLang(item.key).catch((e: Object): void => {
                Logger.w(TAG, `setContentLang: ${(e as Error).message}`);
              });
            });
          }, (item: FilterItem): string => item.key);
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%');

      Text($r('app.string.settings_content_lang_note'))
        .fontSize(AppFontSize.caption)
        .fontColor(AppColors.textTertiary)
        .alignSelf(ItemAlign.Start);
    }
    .width('100%')
    .padding(AppSpace.s16)
    .margin({ top: 8 })
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private themeButton(mode: ThemeMode, label: ResourceStr) {
    Button() {
      Text(label)
        .fontSize(AppFontSize.bodySm)
        .fontColor(this.themeMode === mode ? AppColors.textOnPrimary : AppColors.textPrimary)
        .fontWeight(this.themeMode === mode ? FontWeight.Bold : FontWeight.Regular);
    }
    .layoutWeight(1)
    .height(40)
    .backgroundColor(this.themeMode === mode ? AppColors.brandPrimary : AppColors.surface)
    .borderRadius(AppRadius.sm)
    .onClick(() => this.setTheme(mode));
  }

  @Builder
  private appearanceCard() {
    Column({ space: 12 }) {
      Text($r('app.string.settings_theme'))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start);

      Row({ space: 8 }) {
        this.themeButton('system', $r('app.string.settings_theme_system'));
        this.themeButton('light', $r('app.string.settings_theme_light'));
        this.themeButton('dark', $r('app.string.settings_theme_dark'));
      }
      .width('100%');
    }
    .width('100%')
    .padding(AppSpace.s16)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private dirPill(dir: DownloadDir, label: ResourceStr) {
    Button() {
      Text(label)
        .fontSize(AppFontSize.bodySm)
        .fontWeight(this.currentDownloadDir() === dir ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.currentDownloadDir() === dir ? AppColors.textOnPrimary : AppColors.textPrimary);
    }
    .layoutWeight(1)
    .height(40)
    .backgroundColor(this.currentDownloadDir() === dir ? AppColors.brandPrimary : AppColors.surfaceAlt)
    .borderRadius(AppRadius.sm)
    .onClick(() => this.setDownloadDir(dir));
  }

  @Builder
  private downloadCard() {
    Column() {
      this.settingRow(
        $r('app.string.settings_history'),
        '',
        (): void => this.goHistory(),
      );
      Divider().color(AppColors.divider).strokeWidth(0.5).margin({ left: AppSpace.s16 });

      // 下载目录选择
      Column({ space: 10 }) {
        Text($r('app.string.settings_download_dir'))
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textPrimary)
          .alignSelf(ItemAlign.Start);
        Row({ space: 8 }) {
          this.dirPill('default', $r('app.string.settings_download_dir_default'));
          this.dirPill('cache', $r('app.string.settings_download_dir_cache'));
        }
        .width('100%');
      }
      .width('100%')
      .padding({ left: AppSpace.s16, right: AppSpace.s16, top: 12, bottom: 12 })
      .alignItems(HorizontalAlign.Start);

      Divider().color(AppColors.divider).strokeWidth(0.5).margin({ left: AppSpace.s16 });

      // 清除缓存
      Row() {
        Text($r('app.string.settings_clear_cache'))
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.error)
          .layoutWeight(1);
        Image($r('app.media.ic_chevron_right')).width(16).height(16);
      }
      .width('100%')
      .padding({ left: AppSpace.s16, right: AppSpace.s16, top: 14, bottom: 14 })
      .onClick(() => this.confirmClearCache());
    }
    .width('100%')
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private langPill(value: string, label: ResourceStr) {
    Button() {
      Text(label)
        .fontSize(AppFontSize.bodySm)
        .fontWeight(this.locale === value ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.locale === value ? AppColors.textOnPrimary : AppColors.textPrimary);
    }
    .layoutWeight(1)
    .height(40)
    .backgroundColor(this.locale === value ? AppColors.brandPrimary : AppColors.surfaceAlt)
    .borderRadius(AppRadius.sm)
    .onClick(() => this.setLocale(value));
  }

  @Builder
  private languageCard() {
    Column({ space: 12 }) {
      Text($r('app.string.settings_language'))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start);

      Row({ space: 8 }) {
        this.langPill('', $r('app.string.settings_language_system'));
        this.langPill('zh-Hans', $r('app.string.settings_language_zh'));
        this.langPill('en-US', $r('app.string.settings_language_en'));
      }
      .width('100%');
    }
    .width('100%')
    .padding(AppSpace.s16)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  private goErrorLog(): void {
    AppRouter.push(Routes.ERROR_LOG);
  }

  // ── 代理设置 Actions ──

  private async toggleProxy(on: boolean): Promise<void> {
    this.proxyEnabled = on;
    await PreferencesStore.putBoolean('settings', AppStorageKeys.PROXY_ENABLED, on);
    this.applyProxyToHttpClient();
  }

  private async setProxyHost(v: string): Promise<void> {
    this.proxyHost = v;
    await PreferencesStore.putString('settings', AppStorageKeys.PROXY_HOST, v);
    this.applyProxyToHttpClient();
  }

  private async setProxyPort(v: string): Promise<void> {
    this.proxyPortStr = v;
    const n: number = parseInt(v, 10);
    const port: number = isNaN(n) ? 0 : n;
    await PreferencesStore.putNumber('settings', AppStorageKeys.PROXY_PORT, port);
    this.applyProxyToHttpClient();
  }

  private applyProxyToHttpClient(): void {
    const port: number = parseInt(this.proxyPortStr, 10);
    if (this.proxyEnabled && this.proxyHost.length > 0 && !isNaN(port) && port > 0) {
      HttpClient.instance.setProxy(this.proxyHost, port);
    } else {
      HttpClient.instance.clearProxy();
    }
  }

  // ── 镜像同步 Actions ──

  private async toggleManifest(on: boolean): Promise<void> {
    this.manifestEnabled = on;
    await DomainManifest.setEnabled(on);
  }

  private async setManifestUrl(v: string): Promise<void> {
    this.manifestUrl = v;
    await DomainManifest.setUrl(v);
  }

  private async refreshManifest(): Promise<void> {
    if (this.manifestRefreshing) {
      return;
    }
    this.manifestRefreshing = true;
    SettingsPage.toastResource($r('app.string.settings_manifest_refreshing'));
    try {
      const ok: boolean = await DomainManifest.refreshFromRemote();
      this.manifestVersion = DomainManifest.getLastVersion();
      this.manifestCount = DomainManifest.getRemoteCount();
      SettingsPage.toastResource(
        ok ? $r('app.string.settings_manifest_refreshed') : $r('app.string.settings_manifest_failed'),
      );
      if (ok) {
        // 拉到新镜像后重新测速
        SpeedTestVM.testAll(true).catch((e: Object): void => {
          Logger.w(TAG, `post-manifest test failed: ${(e as Error).message}`);
        });
      }
    } finally {
      this.manifestRefreshing = false;
    }
  }

  private async clearManifestCache(): Promise<void> {
    await DomainManifest.clearRemote();
    this.manifestVersion = '';
    this.manifestCount = 0;
    SettingsPage.toast('已清除同步缓存');
  }

  @Builder
  private diagnosticsCard() {
    Column() {
      this.settingRow(
        $r('app.string.settings_error_log'),
        '',
        (): void => this.goErrorLog(),
      );
    }
    .width('100%')
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  @Builder
  private aboutCard() {
    Row() {
      Text($r('app.string.settings_about_version'))
        .fontSize(AppFontSize.body)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1);
      Text(this.appVersion)
        .fontSize(AppFontSize.bodySm)
        .fontColor(AppColors.textTertiary);
    }
    .width('100%')
    .padding({ left: AppSpace.s16, right: AppSpace.s16, top: 14, bottom: 14 })
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadius.md);
  }

  private userInitial(): string {
    if (this.user === null) {
      return '?';
    }
    const t: string = this.user.name.length > 0 ? this.user.name : this.user.email;
    return t.length > 0 ? t.charAt(0).toUpperCase() : '?';
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar();

        Scroll() {
          Column() {
            this.sectionHeader($r('app.string.settings_section_account'));
            this.accountCard();

            this.sectionHeader($r('app.string.settings_section_network'));
            this.networkCard();
            this.manifestCard();
            this.proxyCard();
            this.contentLangCard();

            this.sectionHeader($r('app.string.settings_section_appearance'));
            this.appearanceCard();
            this.languageCard();

            this.sectionHeader($r('app.string.settings_section_download'));
            this.downloadCard();

            this.sectionHeader($r('app.string.settings_section_diagnostics'));
            this.diagnosticsCard();

            this.sectionHeader($r('app.string.settings_section_about'));
            this.aboutCard();

            Blank().height(40);
          }
          .width('100%')
          .padding({ left: 28, right: 28 });
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
