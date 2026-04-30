/*
 * SearchFilters.ets
 * 搜索筛选项常量与 i18n 资源映射。
 *
 * - 服务端真实参数值：以 string 形式发送（如 'chinese' / 'pdf' / 'popular'）。
 * - 'all' / 'default' 这种"无筛选"项作为 UI 空值，发送时转 undefined。
 */

import { I18n } from '../utils/I18n';

export interface FilterItem {
  /** 内部 key，用于 UI 高亮匹配 */
  key: string;
  /** 发送给服务端的真实值；undefined 表示不发送该参数 */
  apiValue: string | undefined;
  /** Resource 引用，UI 直接绑定到 Text */
  label: Resource;
}

/** 语言筛选 — v1 仅暴露常用 10 项；后续可补全。 */
export const LANGUAGE_FILTERS: FilterItem[] = [
  { key: 'all',                 apiValue: undefined,             label: I18n.t('lang_all') },
  { key: 'chinese',             apiValue: 'chinese',             label: I18n.t('lang_chinese') },
  { key: 'traditional_chinese', apiValue: 'traditional chinese', label: I18n.t('lang_traditional_chinese') },
  { key: 'english',             apiValue: 'english',             label: I18n.t('lang_english') },
  { key: 'japanese',            apiValue: 'japanese',            label: I18n.t('lang_japanese') },
  { key: 'korean',              apiValue: 'korean',              label: I18n.t('lang_korean') },
  { key: 'french',              apiValue: 'french',              label: I18n.t('lang_french') },
  { key: 'german',              apiValue: 'german',              label: I18n.t('lang_german') },
  { key: 'russian',             apiValue: 'russian',             label: I18n.t('lang_russian') },
  { key: 'spanish',             apiValue: 'spanish',             label: I18n.t('lang_spanish') },
];

/** 排序方式 */
export const ORDER_FILTERS: FilterItem[] = [
  { key: 'default',   apiValue: undefined,    label: I18n.t('order_default') },
  { key: 'popular',   apiValue: 'popular',    label: I18n.t('order_popular') },
  { key: 'bestmatch', apiValue: 'bestmatch',  label: I18n.t('order_bestmatch') },
  { key: 'title',     apiValue: 'title',      label: I18n.t('order_title') },
  { key: 'date',      apiValue: 'date',       label: I18n.t('order_date') },
  { key: 'year',      apiValue: 'year',       label: I18n.t('order_year') },
];

/** 文件格式 */
export const EXTENSION_FILTERS: FilterItem[] = [
  { key: 'all',  apiValue: undefined, label: I18n.t('ext_all') },
  { key: 'pdf',  apiValue: 'pdf',     label: I18n.t('ext_pdf') },
  { key: 'epub', apiValue: 'epub',    label: I18n.t('ext_epub') },
  { key: 'mobi', apiValue: 'mobi',    label: I18n.t('ext_mobi') },
  { key: 'txt',  apiValue: 'txt',     label: I18n.t('ext_txt') },
  { key: 'azw',  apiValue: 'azw',     label: I18n.t('ext_azw') },
  { key: 'azw3', apiValue: 'azw3',    label: I18n.t('ext_azw3') },
];
