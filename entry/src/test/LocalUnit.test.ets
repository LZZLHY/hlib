import { describe, it, expect } from '@ohos/hypium';
import { UrlUtils } from '../main/ets/utils/UrlUtils';
import { Book, BookJson } from '../main/ets/model/Book';
import { I18n } from '../main/ets/utils/I18n';

/*
 * LocalUnit.test.ets
 *
 * 本地单测（不需要设备）。覆盖项目中纯计算 / 数据变换的关键函数：
 *   - UrlUtils.rewriteReaderUrl         → 镜像切换时阅读器 URL 的重写规则
 *   - UrlUtils.joinUrl / encodeForm     → URL / 表单序列化
 *   - Book.fromJson                     → 服务端 JSON → Book 模型（含 null-safe / 字符串数字混合）
 *   - I18n.format                       → %s/%d 占位符替换
 *
 * 注：I18n.format 在 bindContext 未调用时，模板资源解析会回退为 key，
 * 所以测试时改传 fallback 参数直接控制模板，避开对 ApplicationContext 的依赖。
 */
export default function localUnitTest() {
  describe('UrlUtils', () => {
    it('rewriteReaderUrl_replacesReaderHostAndZLibraryDomain', 0, () => {
      const result: string = UrlUtils.rewriteReaderUrl(
        'https://reader.z-library.sk/book/123/readonline',
        'pkuedu.online',
        '42',
        'deadbeef',
      );
      // reader 子域切到 reader.<当前镜像>
      expect(result.indexOf('reader.pkuedu.online') >= 0).assertTrue();
      // z-library.sk 替换成当前镜像域
      expect(result.indexOf('z-library.sk') >= 0).assertFalse();
      // user 凭证拼入 query
      expect(result.indexOf('remix_userid=42') >= 0).assertTrue();
      expect(result.indexOf('remix_userkey=deadbeef') >= 0).assertTrue();
    });

    it('rewriteReaderUrl_languagePrefixedDomain_replacesReaderPrefix', 0, () => {
      const result: string = UrlUtils.rewriteReaderUrl(
        'https://reader.z-library.sk/book/1/2',
        'zh.bookroom.digital',
      );
      // zh. 是语言前缀 → reader 应替换该前缀而非拼 reader.zh.
      expect(result.indexOf('reader.bookroom.digital') >= 0).assertTrue();
      expect(result.indexOf('reader.zh.bookroom.digital') >= 0).assertFalse();
    });

    it('rewriteReaderUrl_stripsCdnReaderPrefix', 0, () => {
      const result: string = UrlUtils.rewriteReaderUrl(
        'https://cdn.reader.z-library.sk/book/1/2',
        'example.com',
      );
      expect(result.indexOf('cdn.reader.') >= 0).assertFalse();
      expect(result.indexOf('reader.example.com') >= 0).assertTrue();
    });

    it('rewriteReaderUrl_emptyInput_returnsAsIs', 0, () => {
      expect(UrlUtils.rewriteReaderUrl('', 'example.com')).assertEqual('');
    });

    it('joinUrl_absoluteUrl_returnsAsIs', 0, () => {
      expect(UrlUtils.joinUrl('example.com', 'https://other.org/x')).assertEqual('https://other.org/x');
    });

    it('joinUrl_relativePath_prependsHttpsDomain', 0, () => {
      expect(UrlUtils.joinUrl('example.com', '/a/b')).assertEqual('https://example.com/a/b');
      expect(UrlUtils.joinUrl('example.com/', 'a/b')).assertEqual('https://example.com/a/b');
    });

    it('encodeForm_expandsArraysAsKeyBrackets', 0, () => {
      const out: string = UrlUtils.encodeForm({ langs: ['chinese', 'english'], q: 'hello world' });
      expect(out.indexOf('langs%5B%5D=chinese') >= 0).assertTrue();
      expect(out.indexOf('langs%5B%5D=english') >= 0).assertTrue();
      expect(out.indexOf('q=hello%20world') >= 0).assertTrue();
    });

    it('encodeForm_dropsUndefinedAndEmptyArrays', 0, () => {
      const out: string = UrlUtils.encodeForm({ a: 1, b: undefined, c: [], d: null });
      expect(out).assertEqual('a=1');
    });
  });

  describe('Book.fromJson', () => {
    it('returnsEmptyBookForNullJson', 0, () => {
      const b: Book = Book.fromJson(null);
      expect(b.id).assertEqual(0);
      expect(b.title).assertEqual('');
    });

    it('parsesStringAndNumberFieldsTolerantly', 0, () => {
      const json: BookJson = {
        id: '12345',
        title: 'Deep Work',
        author: 'Cal Newport',
        year: '2016',
        pages: 304,
        extension: 'epub',
        filesize: '1048576',
        hash: 'abc123',
      };
      const b: Book = Book.fromJson(json);
      expect(b.id).assertEqual(12345);
      expect(b.title).assertEqual('Deep Work');
      expect(b.year).assertEqual(2016);
      expect(b.pages).assertEqual(304);
      expect(b.filesize).assertEqual(1048576);
      expect(b.hash).assertEqual('abc123');
    });

    it('handlesNonNumericStringsAsUndefined', 0, () => {
      const json: BookJson = { id: 'notanumber', year: 'N/A' };
      const b: Book = Book.fromJson(json);
      expect(b.id).assertEqual(0);
      expect(b.year).assertUndefined();
    });

    it('fromJsonList_ignoresNullInput', 0, () => {
      expect(Book.fromJsonList(null).length).assertEqual(0);
      expect(Book.fromJsonList(undefined).length).assertEqual(0);
    });
  });

  describe('I18n.format', () => {
    it('replacesPercentSWithString', 0, () => {
      const out: string = I18n.format('no_such_key', ['World'], 'Hello, %s!');
      expect(out).assertEqual('Hello, World!');
    });

    it('replacesPercentDWithNumber', 0, () => {
      const out: string = I18n.format('no_such_key', [42], 'HTTP %d');
      expect(out).assertEqual('HTTP 42');
    });

    it('keepsExtraPlaceholdersIfArgsShort', 0, () => {
      const out: string = I18n.format('no_such_key', ['one'], '%s %s');
      expect(out).assertEqual('one %s');
    });

    it('ignoresExtraArgs', 0, () => {
      const out: string = I18n.format('no_such_key', ['a', 'b', 'c'], 'x=%s');
      expect(out).assertEqual('x=a');
    });
  });
}