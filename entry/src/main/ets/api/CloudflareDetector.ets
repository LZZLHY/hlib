/*
 * CloudflareDetector.ets — Cloudflare 拦截识别（纯函数）
 *
 * 从 HttpClient 抽出。命中 5 秒盾 / 人机校验 / cf-mitigated 时返回 true，
 * 由上层抛 CfBlockedError 并提示换线路。
 */

const CF_MARKERS: string[] = [
  'Just a moment...',
  'cf-mitigated',
  'Attention Required! | Cloudflare',
  '__cf_chl_',
  'cdn-cgi/challenge-platform',
];

export class CloudflareDetector {
  static isBlocked(status: number, body: string, headers: Record<string, string | string[]>): boolean {
    if (status === 403 || status === 503) {
      if (headers !== null && headers !== undefined) {
        const headerKeys: string[] = Object.keys(headers);
        for (let i = 0; i < headerKeys.length; i++) {
          if (headerKeys[i].toLowerCase() === 'cf-mitigated') {
            return true;
          }
        }
      }
    }
    for (let i = 0; i < CF_MARKERS.length; i++) {
      if (body.indexOf(CF_MARKERS[i]) >= 0) {
        return true;
      }
    }
    return false;
  }
}
