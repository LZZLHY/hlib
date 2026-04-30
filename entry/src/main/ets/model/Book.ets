/*
 * Book.ets — Z-Library 书籍模型
 * 字段命名与服务端 JSON 对齐；提供安全的 fromJson 工厂避免 null 崩溃。
 */

export interface BookJson {
  id?: number | string;
  content_type?: string;
  title?: string;
  author?: string;
  volume?: string;
  year?: number | string;
  edition?: string;
  publisher?: string;
  identifier?: string;
  language?: string;
  pages?: number | string;
  series?: string;
  cover?: string;
  terms_hash?: string;
  active?: number | string;
  deleted?: number | string;
  filesize?: number | string;
  filesizeString?: string;
  extension?: string;
  md5?: string;
  sha256?: string;
  href?: string;
  hash?: string;
  kindleAvailable?: boolean;
  sendToEmailAvailable?: boolean;
  interestScore?: string;
  qualityScore?: string;
  dl?: string;
  readOnlineUrl?: string;
  description?: string;
  _isUserSavedBook?: boolean;
  readOnlineAvailable?: boolean;
}

export class Book {
  id: number = 0;
  contentType?: string;
  title: string = '';
  author?: string;
  volume?: string;
  year?: number;
  edition?: string;
  publisher?: string;
  identifier?: string;
  language?: string;
  pages?: number;
  series?: string;
  cover?: string;
  termsHash?: string;
  filesize?: number;
  filesizeString?: string;
  extension?: string;
  md5?: string;
  sha256?: string;
  href?: string;
  hash?: string;
  kindleAvailable?: boolean;
  sendToEmailAvailable?: boolean;
  interestScore?: string;
  qualityScore?: string;
  dl?: string;
  readOnlineUrl?: string;
  description?: string;
  isUserSavedBook?: boolean;
  readOnlineAvailable?: boolean;

  static fromJson(json: BookJson | undefined | null): Book {
    const b = new Book();
    if (!json) {
      return b;
    }
    b.id = Book.toInt(json.id) ?? 0;
    b.contentType = json.content_type;
    b.title = (json.title ?? '').toString();
    b.author = json.author;
    b.volume = json.volume;
    b.year = Book.toInt(json.year);
    b.edition = json.edition;
    b.publisher = json.publisher;
    b.identifier = json.identifier;
    b.language = json.language;
    b.pages = Book.toInt(json.pages);
    b.series = json.series;
    b.cover = json.cover;
    b.termsHash = json.terms_hash;
    b.filesize = Book.toInt(json.filesize);
    b.filesizeString = json.filesizeString;
    b.extension = json.extension;
    b.md5 = json.md5;
    b.sha256 = json.sha256;
    b.href = json.href;
    b.hash = json.hash;
    b.kindleAvailable = json.kindleAvailable;
    b.sendToEmailAvailable = json.sendToEmailAvailable;
    b.interestScore = json.interestScore;
    b.qualityScore = json.qualityScore;
    b.dl = json.dl;
    b.readOnlineUrl = json.readOnlineUrl;
    b.description = json.description;
    b.isUserSavedBook = json._isUserSavedBook;
    b.readOnlineAvailable = json.readOnlineAvailable;
    return b;
  }

  static fromJsonList(arr: BookJson[] | undefined | null): Book[] {
    if (!arr) {
      return [];
    }
    const out: Book[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(Book.fromJson(arr[i]));
    }
    return out;
  }

  /** 是否在线可读 */
  hasReadOnline(): boolean {
    return !!this.readOnlineUrl && this.readOnlineUrl.length > 0;
  }

  private static toInt(v: number | string | undefined | null): number | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v === 'number') {
      return Number.isFinite(v) ? Math.trunc(v) : undefined;
    }
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : undefined;
  }
}
