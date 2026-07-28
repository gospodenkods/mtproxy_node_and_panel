import Docker from 'dockerode';
import { readFileSync } from 'fs';

export type FirewallPreset = 'nft-v3' | 'nft-v2' | 'iptables-v3' | 'iptables-v2' | 'off';

export interface FirewallStatus {
  preset: FirewallPreset;
  ports: number[];
  configured: boolean;
}

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const allowedPresets = new Set<FirewallPreset>(['nft-v3', 'nft-v2', 'iptables-v3', 'iptables-v2', 'off']);

function validatePorts(ports: unknown): number[] {
  if (!Array.isArray(ports) || ports.length === 0 || ports.length > 32) {
    throw new Error('ports must contain between 1 and 32 TCP ports');
  }
  const normalized = [...new Set(ports.map(Number))];
  if (normalized.some((port) => !Number.isInteger(port) || port < 1 || port > 65535)) {
    throw new Error('ports must contain valid TCP port numbers');
  }
  return normalized;
}

async function getOwnImage(): Promise<string> {
  const containerId = readFileSync('/etc/hostname', 'utf8').trim();
  const info = await docker.getContainer(containerId).inspect();
  if (!info.Config.Image) throw new Error('Cannot determine service-node image');
  return info.Config.Image;
}

async function runOnHost(command: string[]): Promise<string> {
  const image = await getOwnImage();
  const container = await docker.createContainer({
    Image: image,
    Entrypoint: ['/usr/bin/nsenter'],
    Cmd: ['-t', '1', '-m', '-u', '-n', '-i', '--', ...command],
    HostConfig: {
      AutoRemove: false,
      NetworkMode: 'host',
      PidMode: 'host',
      Privileged: true,
    },
    Tty: true,
    Labels: { 'mtproxy.role': 'firewall-helper' },
  });

  try {
    await container.start();
    const result = await container.wait();
    const logs = await container.logs({ stdout: true, stderr: true });
    const output = logs.toString('utf8').replace(/[\u0000-\u0008]/g, '').trim();
    if (result.StatusCode !== 0) {
      throw new Error(output || `Firewall helper exited with code ${result.StatusCode}`);
    }
    return output;
  } finally {
    await container.remove({ force: true }).catch(() => {});
  }
}

export async function getFirewallStatus(): Promise<FirewallStatus> {
  const output = await runOnHost([
    '/bin/sh',
    '-c',
    'test -r /etc/mtproxy-meko-firewall.conf && cat /etc/mtproxy-meko-firewall.conf || true',
  ]);
  const presetMatch = output.match(/^PRESET=(.+)$/m);
  const portsMatch = output.match(/^PORT_LIST=(.+)$/m);
  const preset = presetMatch?.[1] as FirewallPreset | undefined;
  if (!preset || !allowedPresets.has(preset)) {
    return { preset: 'off', ports: [], configured: false };
  }
  const ports = (portsMatch?.[1] || '')
    .split(',')
    .map(Number)
    .filter((port) => Number.isInteger(port) && port >= 1 && port <= 65535);
  return { preset, ports, configured: preset !== 'off' };
}

export async function applyFirewallPreset(preset: unknown, ports: unknown): Promise<FirewallStatus> {
  if (typeof preset !== 'string' || !allowedPresets.has(preset as FirewallPreset)) {
    throw new Error('Unknown firewall preset');
  }
  const normalizedPorts = preset === 'off' ? [] : validatePorts(ports);
  await runOnHost([
    '/usr/local/sbin/mtproxy-meko-firewall',
    preset,
    normalizedPorts.join(','),
  ]);
  return getFirewallStatus();
}
