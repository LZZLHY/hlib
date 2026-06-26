/*
 * DomainFailover.ets — 域名漂移策略的抽象接口
 *
 * 解耦：此前 HttpClient.request 直接读 AppStorage[SPEED_RESULTS] 并写 AppStorage[DOMAIN]，
 * 让传输层硬依赖 UI 状态键，违反分层。现在 HttpClient 只依赖此接口；
 * 具体实现（AppStorageDomainFailover）由上层在启动时注入。
 */

export interface DomainFailover {
  /**
   * 选一个可用、且不在 exclude 集合中、且不等于 current 的备用域名。
   * 无可选时返回 null。
   */
  pickFallback(current: string, exclude: Set<string>): string | null;

  /** 通知外界生效域名已切换（用于同步 UI 线路指示）。 */
  onDomainSwitched(newDomain: string): void;
}
