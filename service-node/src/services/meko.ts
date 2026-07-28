import { config } from '../config';
import * as store from '../store';
import * as proxyService from './proxy';
import { applyFirewallPreset, FirewallStatus, runOnHost } from './firewall';

export interface ApplyMekoResult {
  success: boolean;
  firewall: FirewallStatus;
  ports: number[];
  updatedProxies: number;
  errors: string[];
}

export async function applyAllMekoRecommendations(): Promise<ApplyMekoResult> {
  const proxies = store.getAllProxies();
  const ports = [...new Set([
    config.nginxPort,
    ...proxies.map((proxy) => proxy.listenPort).filter((port): port is number => !!port),
  ])].sort((a, b) => a - b);

  await runOnHost(['/usr/local/sbin/mtproxy-meko-tuning', String(ports[0] || config.nginxPort)]);
  const firewall = await applyFirewallPreset('nft-v3', ports);

  let updatedProxies = 0;
  const errors: string[] = [];
  for (const proxy of proxies) {
    try {
      await proxyService.updateProxy(proxy.id, {
        maxConnections: 16384,
        clientHandshake: 15,
        tgConnect: 30,
        clientKeepalive: 120,
        serverClientMss: 0,
      });
      updatedProxies += 1;
    } catch (error: any) {
      errors.push(`${proxy.name || proxy.id}: ${error.message}`);
    }
  }

  return {
    success: errors.length === 0,
    firewall,
    ports,
    updatedProxies,
    errors,
  };
}
