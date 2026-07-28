import { config } from '../config';
import * as store from '../store';
import * as proxyService from './proxy';
import { applyFirewallPreset, FirewallStatus, runOnHost } from './firewall';

export interface ApplyMekoResult {
  success: boolean;
  firewall: FirewallStatus;
  ports: number[];
  updatedProxies: number;
  profile: 'mobile-reference';
  warnings: string[];
  errors: string[];
}

export async function applyAllMekoRecommendations(): Promise<ApplyMekoResult> {
  const proxies = store.getAllProxies();
  const ports = [config.nginxPort];
  const warnings: string[] = [];

  await runOnHost(['/usr/local/sbin/mtproxy-meko-tuning', String(ports[0] || config.nginxPort)]);
  // The known-fast reference host has no active SYN fingerprint limiter.
  // Keep manual MEKO presets available, but the one-click mobile profile must
  // not reject or delay clients whose first packets do not match a fingerprint.
  const firewall = await applyFirewallPreset('off', []);

  if (config.nginxPort !== 443) {
    warnings.push(
      `Service node publishes TCP ${config.nginxPort}; mobile networks work most reliably on TCP 443. ` +
      'Set NGINX_PORT=443 and publish host port 443 before deployment.',
    );
  }

  let updatedProxies = 0;
  const errors: string[] = [];
  for (const proxy of proxies) {
    try {
      await proxyService.updateProxy(proxy.id, {
        listenPort: 0,
        directOutbound: true,
        vpnSubscription: '',
        natIp: '',
        tunnelInterface: '',
        maxConnections: 16384,
        clientHandshake: 0,
        tgConnect: 0,
        clientKeepalive: 0,
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
    profile: 'mobile-reference',
    warnings,
    errors,
  };
}
