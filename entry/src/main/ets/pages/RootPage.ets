/*
 * RootPage.ets
 *
 * 应用唯一的 @Entry 页：只承载 Navigation + 初始路由。
 * 所有业务页面降级为 @Component，挂在 navDestination 注册表中。
 */

import { AppRouter, Routes, EMPTY_NAV_PARAM } from '../utils/AppRouter';
import { AppColors } from '../theme/AppColors';
import { Logger } from '../utils/Logger';

import { SplashPage } from './SplashPage';
import { LoginPage } from './LoginPage';
import { MainPage } from './MainPage';
import { BookDetailPage } from './BookDetailPage';
import { SimilarBooksPage } from './SimilarBooksPage';
import { ReaderPage } from './ReaderPage';
import { SettingsPage } from './SettingsPage';
import { HistoryPage } from './HistoryPage';
import { ErrorLogPage } from './ErrorLogPage';

const TAG: string = 'RootPage';

@Entry
@Component
struct RootPage {
  pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    AppRouter.bind(this.pathStack);
    // 初始路由：Splash 上栈，由它决定后续 replace
    try {
      this.pathStack.pushPathByName(Routes.SPLASH, EMPTY_NAV_PARAM);
    } catch (e) {
      Logger.e(TAG, 'initial push failed', e as Error);
    }
  }

  @Builder
  pageMap(name: string, param: object) {
    if (name === Routes.SPLASH) {
      SplashPage();
    } else if (name === Routes.LOGIN) {
      LoginPage();
    } else if (name === Routes.MAIN) {
      MainPage();
    } else if (name === Routes.BOOK_DETAIL) {
      BookDetailPage();
    } else if (name === Routes.SIMILAR) {
      SimilarBooksPage();
    } else if (name === Routes.READER) {
      ReaderPage();
    } else if (name === Routes.SETTINGS) {
      SettingsPage();
    } else if (name === Routes.HISTORY) {
      HistoryPage();
    } else if (name === Routes.ERROR_LOG) {
      ErrorLogPage();
    }
  }

  build() {
    Navigation(this.pathStack) {
      // 占位根：栈非空时被覆盖；空时显示纯色，避免穿透到系统壁纸。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColors.brandPrimaryDark);
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
