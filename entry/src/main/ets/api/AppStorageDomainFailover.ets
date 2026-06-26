/*
 * AppStorageDomainFailover.ets — DomainFailover 的默认实现（适配 AppStorage）
 *
 * 把"读测速结果挑最快可用节点 + 把生效域名写回 AppStorage 供 UI 订阅"这套
 * 与 AppStorage 耦合的逻辑收敛到这一个适配器里。HttpClient 不再直接碰 AppStorage。
 *
 * 由 EntryAbility 在启动时注入：HttpClient.instance.setFailover(new AppStorageDomainFailover())。
 */

import { AppStorageKeys } from '../storage/AppStorageKeys';
import { DomainTestResult } from '../model/DomainTestResult';
import { DomainFailover } from './DomainFailover';

export class AppStorageDomainFailover implements DomainFailover {
  /** 从 SPEED_RESULTS（已按延迟升序）挑第一个 alive、未排除、非当前的域名。 */
  pickFallback(current: string, exclude: Set<string>): string | null {
    const results: DomainTestResult[] | undefined =
      AppStorage.get<DomainTestResult[]>(AppStorageKeys.SPEED_RESULTS);
    if (results === undefined || results.length === 0) {
      return null;
    }
    for (let i = 0; i < results.length; i++) {
      const r: DomainTestResult = results[i];
      const ms: number | null = r.latencyMs;
      if (ms !== null && ms > 0 && r.domain !== current && !exclude.has(r.domain)) {
        return r.domain;
      }
    }
    return null;
  }

  /** 把生效域名写回 AppStorage：UI 线路指示更新，首页 @Watch 在可用节点上重载。 */
  onDomainSwitched(newDomain: string): void {
    AppStorage.setOrCreate<string>(AppStorageKeys.DOMAIN, newDomain);
  }
}
