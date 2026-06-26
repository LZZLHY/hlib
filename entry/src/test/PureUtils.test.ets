import { describe, it, expect } from '@ohos/hypium';
import { QrLoginParser, QrCredential } from '../main/ets/utils/QrLoginParser';
import { Layout } from '../main/ets/utils/Layout';
import { Format } from '../main/ets/utils/Format';
import { Redact } from '../main/ets/utils/Redact';

/*
 * PureUtils.test.ets
 *
 * 纯函数本地单测（不需要设备），补齐此前未覆盖的工具：
 *   - QrLoginParser.parse  → 扫码凭证解析（JSON / URL / cookie 三态 + 非法输入）
 *   - Layout               → 响应式断点派生与导航样式解析
 *   - Format               → 字节 / 日期格式化
 *   - Redact               → 日志脱敏（URL / cookie / headers）
 */
export default function pureUtilsTest() {
  describe('QrLoginParser', () => {
    it('parsesJsonRemixKeys', 0, () => {
      const c: QrCredential | null = QrLoginParser.parse('{"remix_userid":"42","remix_userkey":"abc"}');
      expect(c !== null).assertTrue();
      expect((c as QrCredential).userId).assertEqual('42');
      expect((c as QrCredential).userKey).assertEqual('abc');
    });

    it('parsesUrlQuery', 0, () => {
      const c: QrCredential | null = QrLoginParser.parse('https://z-library.sk/login?remix_userid=7&remix_userkey=zzz');
      expect(c !== null).assertTrue();
      expect((c as QrCredential).userId).assertEqual('7');
      expect((c as QrCredential).userKey).assertEqual('zzz');
    });

    it('parsesCookieString', 0, () => {
      const c: QrCredential | null = QrLoginParser.parse('remix_userid=100; remix_userkey=deadbeef');
      expect(c !== null).assertTrue();
      expect((c as QrCredential).userId).assertEqual('100');
      expect((c as QrCredential).userKey).assertEqual('deadbeef');
    });

    it('returnsNullForGarbage', 0, () => {
      expect(QrLoginParser.parse('just some text')).assertNull();
      expect(QrLoginParser.parse('')).assertNull();
      expect(QrLoginParser.parse(null)).assertNull();
      expect(QrLoginParser.parse(undefined)).assertNull();
    });

    it('returnsNullWhenOnlyOneKeyPresent', 0, () => {
      expect(QrLoginParser.parse('remix_userid=100')).assertNull();
    });
  });

  describe('Layout', () => {
    it('breakpointOf_mapsWidthToBucket', 0, () => {
      expect(Layout.breakpointOf(500)).assertEqual('sm');
      expect(Layout.breakpointOf(700)).assertEqual('md');
      expect(Layout.breakpointOf(1000)).assertEqual('lg');
      expect(Layout.breakpointOf(1600)).assertEqual('xl');
    });

    it('gridCols_increaseWithBreakpoint', 0, () => {
      expect(Layout.gridCols('sm')).assertEqual(3);
      expect(Layout.gridCols('md')).assertEqual(4);
      expect(Layout.gridCols('lg')).assertEqual(5);
      expect(Layout.gridCols('xl')).assertEqual(6);
    });

    it('resolveNavStyle_phoneAlwaysBottom', 0, () => {
      expect(Layout.resolveNavStyle('sm', 'side')).assertEqual('bottom');
      expect(Layout.resolveNavStyle('sm', 'auto')).assertEqual('bottom');
    });

    it('resolveNavStyle_autoUsesSideOnLarge', 0, () => {
      expect(Layout.resolveNavStyle('lg', 'auto')).assertEqual('side');
      expect(Layout.resolveNavStyle('md', 'auto')).assertEqual('bottom');
    });

    it('resolveNavStyle_respectsExplicitPref', 0, () => {
      expect(Layout.resolveNavStyle('lg', 'bottom')).assertEqual('bottom');
      expect(Layout.resolveNavStyle('md', 'side')).assertEqual('side');
    });
  });

  describe('Format', () => {
    it('size_zeroOrNegativeIsDash', 0, () => {
      expect(Format.size(0)).assertEqual('—');
      expect(Format.size(-5)).assertEqual('—');
    });

    it('size_picksUnit', 0, () => {
      expect(Format.size(500)).assertEqual('500 B');
      expect(Format.size(2 * 1024 * 1024)).assertEqual('2.0 MB');
    });

    it('date_takesIsoDatePart', 0, () => {
      expect(Format.date('2026-06-26T10:11:12Z')).assertEqual('2026-06-26');
      expect(Format.date('')).assertEqual('');
    });
  });

  describe('Redact', () => {
    it('url_masksSensitiveQueryValuesKeepsKeys', 0, () => {
      const out: string = Redact.url('https://reader.x.com/book/1?remix_userkey=secret&page=3');
      expect(out.indexOf('remix_userkey=***') >= 0).assertTrue();
      expect(out.indexOf('secret') >= 0).assertFalse();
      expect(out.indexOf('page=3') >= 0).assertTrue();
    });

    it('url_withoutQueryUnchanged', 0, () => {
      expect(Redact.url('https://reader.x.com/book/1')).assertEqual('https://reader.x.com/book/1');
    });

    it('cookie_masksAllValues', 0, () => {
      const out: string = Redact.cookie('remix_userid=42; foo=bar');
      expect(out.indexOf('remix_userid=***') >= 0).assertTrue();
      expect(out.indexOf('foo=***') >= 0).assertTrue();
      expect(out.indexOf('42') >= 0).assertFalse();
    });

    it('headers_masksOnlySensitiveHeaders', 0, () => {
      const raw: Record<string, string> = { 'Cookie': 'a=b', 'Accept': 'application/json' };
      const masked: Record<string, string> = Redact.headers(raw);
      expect(masked['Cookie']).assertEqual('***');
      expect(masked['Accept']).assertEqual('application/json');
    });
  });
}
