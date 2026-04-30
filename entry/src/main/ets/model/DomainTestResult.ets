/*
 * DomainTestResult.ets — 镜像域可达性测速结果
 */

export class DomainTestResult {
  /** 不含协议的域名（如 'pkuedu.online'） */
  domain: string;
  /** null=未测；-1=失败；>0=耗时 ms */
  latencyMs: number | null;

  constructor(domain: string, latencyMs: number | null = null) {
    this.domain = domain;
    this.latencyMs = latencyMs;
  }

  get ok(): boolean {
    return this.latencyMs !== null && this.latencyMs > 0;
  }
}
