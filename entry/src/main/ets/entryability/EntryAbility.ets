import { AbilityConstant, ConfigurationConstant, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { I18n } from '../utils/I18n';
import { Logger } from '../utils/Logger';
import { SecretStore } from '../utils/SecretStore';
import { PreferencesStore } from '../storage/PreferencesStore';
import { AuthStore } from '../storage/AuthStore';
import { ErrorReportStore } from '../storage/ErrorReportStore';
import { AppStorageKeys, DEFAULT_DOMAIN, ThemeMode, NavStyle, Breakpoint } from '../storage/AppStorageKeys';
import { HttpClient } from '../api/HttpClient';
import { DomainManifest } from '../api/DomainManifest';
import { Layout } from '../utils/Layout';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  /** errorManager observer id，onDestroy 时反注册防止累积。 */
  private errorObserverId: number = -1;

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    Logger.i(TAG, 'onCreate');
    try {
      // 0) 给 I18n 工具注入 ApplicationContext，让 ErrorHelper / 各页 toast 能 sync 取本地化字符串
      I18n.bindContext(this.context);

      // 1) 初始化偏好存储（必须最先完成，后续 Store 都依赖它）
      await PreferencesStore.init(this.context);
      await ErrorReportStore.init();

      // 1.2) 初始化 HUKS 凭证加密 master key（必须在 AuthStore 读凭证之前）
      await SecretStore.init();

      // 1.3) 加载远程镜像 manifest 配置 + 上次缓存（不发起网络请求）
      await DomainManifest.loadFromStorage();

      // 1.5) 注册全局未捕获异常 → ErrorReportStore
      try {
        const observer: errorManager.ErrorObserver = {
          onUnhandledException: (errMsg: string): void => {
            ErrorReportStore.append({
              ts: new Date().toISOString(),
              level: 'error',
              tag: 'UnhandledException',
              message: errMsg,
            });
            Logger.w(TAG, `UnhandledException: ${errMsg}`);
          },
        };
        // errorManager.on 返回 observer id（number），用于 onDestroy 时反注册
        this.errorObserverId = errorManager.on('error', observer);
      } catch (e) {
        Logger.w(TAG, `errorManager.on failed: ${(e as Error).message}`);
      }

      // 2) 把可观测的偏好钉到 AppStorage（PersistentStorage 自动保存到 ArkUI 内部文件）
      PersistentStorage.persistProp<string>(AppStorageKeys.DOMAIN, DEFAULT_DOMAIN);
      PersistentStorage.persistProp<ThemeMode>(AppStorageKeys.THEME_MODE, 'system');
      PersistentStorage.persistProp<string>(AppStorageKeys.LOCALE, '');
      PersistentStorage.persistProp<string>(AppStorageKeys.DOWNLOAD_PATH, '');
      PersistentStorage.persistProp<NavStyle>(AppStorageKeys.NAV_STYLE, 'auto');
      PersistentStorage.persistProp<string>(AppStorageKeys.PRIVACY_AGREED_VERSION, '');

      // 3) 应用偏好到 HttpClient
      const savedDomain = AppStorage.get<string>(AppStorageKeys.DOMAIN) ?? DEFAULT_DOMAIN;
      HttpClient.instance.setDomain(savedDomain);

      // 3.1) 读取并应用 HTTP 代理偏好
      const proxyEnabled: boolean = await PreferencesStore.getBoolean('settings', AppStorageKeys.PROXY_ENABLED, false);
      if (proxyEnabled) {
        const proxyHost: string = await PreferencesStore.getString('settings', AppStorageKeys.PROXY_HOST, '');
        const proxyPort: number = await PreferencesStore.getNumber('settings', AppStorageKeys.PROXY_PORT, 0);
        if (proxyHost.length > 0 && proxyPort > 0) {
          HttpClient.instance.setProxy(proxyHost, proxyPort);
          Logger.i(TAG, `applied proxy: ${proxyHost}:${proxyPort}`);
        }
      }

      // 3.2) 读取并应用首页内容地区偏好（注入 siteLanguageV2 cookie + Accept-Language）
      const contentLang: string = await PreferencesStore.getString('settings', AppStorageKeys.CONTENT_LANG, '');
      HttpClient.instance.setSiteLanguage(contentLang);
      Logger.i(TAG, `applied siteLanguage: ${contentLang.length > 0 ? contentLang : '(none)'}`);

      // 4) 恢复登录态（如果有）
      const cred = await AuthStore.getCredentials();
      if (cred) {
        HttpClient.instance.setAuth(cred.userId, cred.userKey);
        Logger.i(TAG, `restored auth for user ${cred.userId}`);
      }

      // 5) 应用主题
      this.applyThemeMode(AppStorage.get<ThemeMode>(AppStorageKeys.THEME_MODE) ?? 'system');

      // 6) 应用偏好语言（'' 表示跟随系统）
      const savedLocale: string = AppStorage.get<string>(AppStorageKeys.LOCALE) ?? '';
      try {
        i18n.System.setAppPreferredLanguage(savedLocale);
      } catch (e) {
        Logger.w(TAG, `setAppPreferredLanguage failed: ${(e as Error).message}`);
      }

      // 7) 读取应用版本号写入 AppStorage（关于页 / 启动屏订阅，避免硬编码字面量）
      try {
        const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
          bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT,
        );
        const ver: string = info.versionName !== undefined && info.versionName.length > 0
          ? info.versionName
          : '1.0.0';
        AppStorage.setOrCreate<string>(AppStorageKeys.APP_VERSION, ver);
        Logger.i(TAG, `app version: ${ver}`);
      } catch (e) {
        Logger.w(TAG, `read versionName failed: ${(e as Error).message}`);
        AppStorage.setOrCreate<string>(AppStorageKeys.APP_VERSION, '1.0.0');
      }
    } catch (e) {
      Logger.e(TAG, 'onCreate init failed', e as Error);
      // 容错：哪怕初始化失败也至少能让 UI 起来
      try {
        this.applyThemeMode('system');
      } catch {
        // ignore
      }
    }
  }

  onDestroy(): void {
    Logger.i(TAG, 'onDestroy');
    if (this.errorObserverId >= 0) {
      try {
        errorManager.off('error', this.errorObserverId);
      } catch (e) {
        Logger.w(TAG, `errorManager.off failed: ${(e as Error).message}`);
      }
      this.errorObserverId = -1;
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    Logger.i(TAG, 'onWindowStageCreate');

    // 沉浸式窗口：全屏布局 + 状态栏/导航栏透明
    try {
      const mainWindow: window.Window = await windowStage.getMainWindow();
      await mainWindow.setWindowLayoutFullScreen(true);
      const barProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: '#FF000000',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#FF000000',
      };
      await mainWindow.setWindowSystemBarProperties(barProps);

      // Store safe area heights (vp) for UI components to use as padding
      try {
        const sysArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const density: number = display.getDefaultDisplaySync().densityPixels;
        AppStorage.setOrCreate<number>('statusBarHeight', sysArea.topRect.height / density);
        AppStorage.setOrCreate<number>('navBarHeight', sysArea.bottomRect.height / density);

        // 初始屏宽 + 断点写入；后续由 windowSizeChange 监听更新
        const props: window.WindowProperties = mainWindow.getWindowProperties();
        const widthVp: number = props.windowRect.width / density;
        const bp: Breakpoint = Layout.breakpointOf(widthVp);
        AppStorage.setOrCreate<number>(AppStorageKeys.SCREEN_WIDTH_VP, widthVp);
        AppStorage.setOrCreate<Breakpoint>(AppStorageKeys.BREAKPOINT, bp);
        Logger.i(TAG, `initial layout: ${widthVp.toFixed(0)}vp -> ${bp}`);

        // 监听窗口尺寸变化（折叠展开/分屏切换/旋转），实时刷新断点
        mainWindow.on('windowSizeChange', (size: window.Size): void => {
          try {
            const w: number = size.width / density;
            const b: Breakpoint = Layout.breakpointOf(w);
            AppStorage.setOrCreate<number>(AppStorageKeys.SCREEN_WIDTH_VP, w);
            AppStorage.setOrCreate<Breakpoint>(AppStorageKeys.BREAKPOINT, b);
          } catch (sze) {
            Logger.w(TAG, `windowSizeChange handler failed: ${(sze as Error).message}`);
          }
        });
      } catch (ex) {
        Logger.w(TAG, `getWindowAvoidArea / size init failed: ${(ex as Error).message}`);
      }
    } catch (e) {
      Logger.w(TAG, `setWindowLayoutFullScreen failed: ${(e as Error).message}`);
    }

    windowStage.loadContent('pages/RootPage', (err) => {
      if (err.code) {
        Logger.e(TAG, 'loadContent failed', err);
        return;
      }
      Logger.i(TAG, 'loadContent ok');
    });
  }

  onWindowStageDestroy(): void {
    Logger.i(TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.i(TAG, 'onForeground');
  }

  onBackground(): void {
    Logger.i(TAG, 'onBackground');
  }

  private applyThemeMode(mode: ThemeMode): void {
    let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === 'light') {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (mode === 'dark') {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      this.context.getApplicationContext().setColorMode(target);
    } catch (e) {
      Logger.w(TAG, `setColorMode failed: ${(e as Error).message}`);
    }
  }
}