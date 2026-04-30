/*
 * AppRouter.ets
 *
 * 全局导航门面：包装 NavPathStack。
 * 在 RootPage 的 aboutToAppear() 中调 AppRouter.bind(stack) 注入根 stack；
 * 业务代码用 AppRouter.push/replace/pop 等价替换 router.pushUrl/replaceUrl/back。
 *
 * 这是 P1.5 Navigation 迁移的核心抽象，让其他页面无需感知 NavPathStack。
 */

import { Logger } from './Logger';

const TAG: string = 'AppRouter';

/** 当 push 不带 param 时使用的空载体类型（满足 ArkTS arkts-no-untyped-obj-literals）。 */
export interface EmptyNavParam {}

/** 共享的空 param 实例。 */
export const EMPTY_NAV_PARAM: EmptyNavParam = {};

export class Routes {
  static readonly SPLASH: string = 'Splash';
  static readonly LOGIN: string = 'Login';
  static readonly MAIN: string = 'Main';
  static readonly BOOK_DETAIL: string = 'BookDetail';
  static readonly SIMILAR: string = 'Similar';
  static readonly READER: string = 'Reader';
  static readonly SETTINGS: string = 'Settings';
  static readonly HISTORY: string = 'History';
  static readonly ERROR_LOG: string = 'ErrorLog';
}

/** BookDetailPage 入参 */
export interface BookDetailParams {
  bookId: string;
  hashId: string;
  title: string;
  cover: string;
}

/** ReaderPage 入参 */
export interface ReaderParams {
  url: string;
  title: string;
  /** 用于阅读进度记忆。可空时 ReaderPage 不做记忆。 */
  bookId?: string;
}

/** SimilarBooksPage 入参 */
export interface SimilarParams {
  bookId: string;
  hashId: string;
  title: string;
}

export class AppRouter {
  private static stack: NavPathStack | null = null;

  /** RootPage 在 aboutToAppear 时调一次。 */
  static bind(stack: NavPathStack): void {
    AppRouter.stack = stack;
    Logger.i(TAG, 'pathStack bound');
  }

  /** 入栈一个路由。 */
  static push(name: string, param?: object): void {
    const s: NavPathStack | null = AppRouter.stack;
    if (s === null) {
      Logger.w(TAG, `push(${name}) ignored: not bound`);
      return;
    }
    try {
      s.pushPathByName(name, param !== undefined ? param : EMPTY_NAV_PARAM);
    } catch (e) {
      Logger.w(TAG, `push(${name}) failed: ${(e as Error).message}`);
    }
  }

  /** 替换栈顶。 */
  static replace(name: string, param?: object): void {
    const s: NavPathStack | null = AppRouter.stack;
    if (s === null) {
      Logger.w(TAG, `replace(${name}) ignored: not bound`);
      return;
    }
    try {
      s.replacePathByName(name, param !== undefined ? param : EMPTY_NAV_PARAM);
    } catch (e) {
      Logger.w(TAG, `replace(${name}) failed: ${(e as Error).message}`);
    }
  }

  /** 出栈一项。 */
  static pop(): void {
    const s: NavPathStack | null = AppRouter.stack;
    if (s === null) {
      return;
    }
    try {
      s.pop();
    } catch (e) {
      Logger.w(TAG, `pop failed: ${(e as Error).message}`);
    }
  }

  /** 出栈到指定路由名。 */
  static popTo(name: string): void {
    const s: NavPathStack | null = AppRouter.stack;
    if (s === null) {
      return;
    }
    try {
      s.popToName(name);
    } catch (e) {
      Logger.w(TAG, `popTo(${name}) failed: ${(e as Error).message}`);
    }
  }

  /** 清空整个栈，常用于退登。 */
  static clear(): void {
    const s: NavPathStack | null = AppRouter.stack;
    if (s === null) {
      return;
    }
    try {
      s.clear();
    } catch (e) {
      Logger.w(TAG, `clear failed: ${(e as Error).message}`);
    }
  }
}
