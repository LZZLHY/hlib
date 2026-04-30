/*
 * DohResolver.ets
 *
 * DNS over HTTPS 解析工具。
 *
 * 用途（不参与请求路由）：
 *   - 网络诊断：当 HttpClient 请求失败时，后台调一次 DoH 看域名解析是否正常
 *     - 解析成功但请求失败 → IP 层被封锁
 *     - 解析失败 → DNS 污染 / 域名失效
 *   - 设置页"诊断"按钮：显示当前镜像在 Cloudflare DNS 上的解析结果
 *
 * 为什么不直接用 IP 替换 hostname 做请求路由：
 *   HarmonyOS NetworkKit http 模块不暴露 SNI 控制字段；HTTPS 场景下用 IP 作 host
 *   会导致 TLS 握手时 SNI=IP，服务器返回证书不匹配从而失败。除非自实现 socket+TLS
 *   客户端（数百行高风险代码），否则 IP 替换在 HTTPS 站不可行。本文件因此只做查询。
 *
 * Cloudflare DoH 端点：
 *   - https://cloudflare-dns.com/dns-query
 *   - https://1.1.1.1/dns-query
 *   返回 application/dns-json：
 *   { "Status": 0, "Answer": [{ "name":"...", "type":1, "TTL":..., "data":"1.2.3.4" }, ...] }
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

const TAG: string = 'DohResolver';

/** 默认 Cloudflare DoH 端点。备用时用 1.1.1.1 直连 IP。 */
const DOH_URL_PRIMARY: string = 'https://cloudflare-dns.com/dns-query';
const DOH_URL_FALLBACK: string = 'https://1.1.1.1/dns-query';
const DOH_TIMEOUT_MS: number = 6000;

interface DohAnswer {
  name?: string;
  type?: number;
  TTL?: number;
  data?: string;
}

interface DohResponse {
  Status?: number;
  Answer?: DohAnswer[];
}

export interface DnsResolveResult {
  /** 查询的域名 */
  hostname: string;
  /** 解析到的 IPv4 列表（可能为空） */
  ips: string[];
  /** 总耗时（ms）*/
  elapsedMs: number;
  /** 是否成功（Status=0 且至少一条 A 记录）*/
  ok: boolean;
  /** 失败时的简短描述 */
  error: string;
}

export class DohResolver {
  /** 查询 IPv4（type=A）。失败时返回 ok=false，ips 为空。永不抛异常。 */
  static async resolveA(hostname: string): Promise<DnsResolveResult> {
    const cleaned: string = hostname.replace(/^https?:\/\//, '').replace(/\/+$/, '').trim();
    if (cleaned.length === 0) {
      return DohResolver.buildResult(cleaned, [], 0, 'empty hostname');
    }
    // 先试主端点；失败再试 IP 直连端点
    const start: number = Date.now();
    let result: DnsResolveResult = await DohResolver.queryEndpoint(DOH_URL_PRIMARY, cleaned, start);
    if (!result.ok) {
      Logger.d(TAG, `primary DoH failed for ${cleaned}, trying fallback`);
      result = await DohResolver.queryEndpoint(DOH_URL_FALLBACK, cleaned, start);
    }
    return result;
  }

  /** 仅做诊断日志：失败请求后台异步调一次，写入 Logger.i / Logger.w 供排查。 */
  static async diagnoseAsync(hostname: string): Promise<void> {
    try {
      const r: DnsResolveResult = await DohResolver.resolveA(hostname);
      if (r.ok) {
        Logger.i(TAG, `diag ${hostname} → DNS ok, ips=[${r.ips.join(',')}] ${r.elapsedMs}ms (request still failed: likely IP/CDN block)`);
      } else {
        Logger.w(TAG, `diag ${hostname} → DNS failed: ${r.error} (likely DNS poisoning or dead domain)`);
      }
    } catch (e) {
      // 兜底：诊断本身不可抛
      Logger.d(TAG, `diagnoseAsync swallowed: ${(e as Error).message}`);
    }
  }

  // ─── 内部 ────────────────────────────────────────────

  private static async queryEndpoint(endpoint: string, hostname: string, start: number): Promise<DnsResolveResult> {
    const url: string = `${endpoint}?name=${encodeURIComponent(hostname)}&type=A`;
    const req: http.HttpRequest = http.createHttp();
    try {
      const reqOpts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/dns-json' },
        connectTimeout: DOH_TIMEOUT_MS,
        readTimeout: DOH_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      };
      const resp: http.HttpResponse = await req.request(url, reqOpts);
      const elapsed: number = Date.now() - start;
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        return DohResolver.buildResult(hostname, [], elapsed, `http ${resp.responseCode}`);
      }
      const text: string = typeof resp.result === 'string' ? resp.result : '';
      const parsed: DohResponse = JSON.parse(text) as DohResponse;
      if (parsed.Status !== undefined && parsed.Status !== 0) {
        return DohResolver.buildResult(hostname, [], elapsed, `dns status=${parsed.Status}`);
      }
      const ips: string[] = [];
      const answers: DohAnswer[] | undefined = parsed.Answer;
      if (answers !== undefined) {
        for (let i = 0; i < answers.length; i++) {
          // type=1 表示 A 记录
          if (answers[i].type === 1 && answers[i].data !== undefined) {
            ips.push(answers[i].data as string);
          }
        }
      }
      if (ips.length === 0) {
        return DohResolver.buildResult(hostname, [], elapsed, 'no A record');
      }
      return DohResolver.buildResult(hostname, ips, elapsed, '');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const elapsed: number = Date.now() - start;
      return DohResolver.buildResult(hostname, [], elapsed, e.message ?? 'network_error');
    } finally {
      req.destroy();
    }
  }

  private static buildResult(hostname: string, ips: string[], elapsedMs: number, error: string): DnsResolveResult {
    return {
      hostname,
      ips,
      elapsedMs,
      ok: ips.length > 0 && error.length === 0,
      error,
    };
  }
}
