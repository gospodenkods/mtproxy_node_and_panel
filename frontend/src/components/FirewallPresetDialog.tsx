import { FormEvent, useEffect, useState } from 'react';
import { Alert, Button, Dialog, Select, TextInput } from '@gravity-ui/uikit';
import {
  applyAllMekoRecommendations,
  applyNodeFirewall,
  FirewallPreset,
  getNodeFirewall,
  NodeData,
} from '../api';

interface Props {
  node: NodeData | null;
  onClose: () => void;
}

const options = [
  { value: 'nft-v3', content: 'nftables V3 — fingerprint (рекомендуется)' },
  { value: 'nft-v2', content: 'nftables V2 — TTL + length' },
  { value: 'iptables-v3', content: 'iptables V3 — u32 fingerprint' },
  { value: 'iptables-v2', content: 'iptables V2 — TTL + length' },
  { value: 'off', content: 'Отключить MEKO firewall' },
];

export default function FirewallPresetDialog({ node, onClose }: Props) {
  const [preset, setPreset] = useState<FirewallPreset>('nft-v3');
  const [ports, setPorts] = useState('443');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [resultMessage, setResultMessage] = useState('');

  useEffect(() => {
    if (!node) return;
    setLoading(true);
    setError('');
    setResultMessage('');
    getNodeFirewall(node.id)
      .then((status) => {
        setPreset(status.preset);
        setPorts(status.ports.length > 0 ? status.ports.join(', ') : '443');
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [node]);

  const handleApply = async (event: FormEvent) => {
    event.preventDefault();
    if (!node) return;
    const parsedPorts = ports
      .split(',')
      .map((value) => Number(value.trim()))
      .filter((value) => Number.isInteger(value));
    if (preset !== 'off' && (
      parsedPorts.length === 0 ||
      parsedPorts.some((port) => port < 1 || port > 65535)
    )) {
      setError('Укажите корректные TCP-порты через запятую');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const status = await applyNodeFirewall(node.id, preset, preset === 'off' ? [] : parsedPorts);
      setPreset(status.preset);
      onClose();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  const handleApplyAll = async () => {
    if (!node || !confirm(
      'Применить быстрый мобильный профиль? Все прокси будут переведены на прямой исходящий трафик и общий внешний порт, VPN будет отключён, а дополнительный MEKO SYN limiter — снят.',
    )) return;
    setSaving(true);
    setError('');
    setResultMessage('');
    try {
      const result = await applyAllMekoRecommendations(node.id);
      setPreset(result.firewall.preset);
      setPorts(result.ports.join(', '));
      setResultMessage(
        `Мобильный профиль применён: прямой выход, внешний TCP ${result.ports.join(', ')}, обновлено прокси: ${result.updatedProxies}.`,
      );
      const messages = [...result.warnings, ...result.errors];
      if (messages.length > 0) {
        setError(messages.join('; '));
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={!!node} onClose={onClose} size="m">
      <Dialog.Header caption={`MEKO firewall — ${node?.name || ''}`} />
      <Dialog.Body>
        <form id="firewall-preset-form" onSubmit={handleApply}>
          {error && <div style={{ marginBottom: 16 }}><Alert theme="danger" message={error} /></div>}
          {resultMessage && <div style={{ marginBottom: 16 }}><Alert theme="success" message={resultMessage} /></div>}
          <div style={{ marginBottom: 16, padding: 12, borderRadius: 8, background: 'var(--g-color-base-generic)' }}>
            <div style={{ fontWeight: 600, marginBottom: 6 }}>Быстрый профиль для мобильных клиентов</div>
            <div style={{ color: 'var(--g-color-text-secondary)', marginBottom: 10 }}>
              Повторяет ключевые параметры проверенного быстрого сервера: TCP 443, прямой исходящий
              трафик, BBR/fq, минимальные таймауты Telemt и отсутствие дополнительного SYN limiter.
            </div>
            <Button view="action" onClick={handleApplyAll} loading={saving || loading} width="max">
              Оптимизировать мобильное подключение
            </Button>
          </div>
          <Alert
            theme="warning"
            message="Правила применяются на хосте сервис-ноды. При смене пресета предыдущие MEKO-цепочки удаляются."
          />
          <div className="dialog-field" style={{ marginTop: 16 }}>
            <label>Пресет</label>
            <Select
              value={[preset]}
              onUpdate={(value) => setPreset((value[0] || 'off') as FirewallPreset)}
              options={options}
              width="max"
              disabled={loading}
            />
          </div>
          {preset !== 'off' && (
            <div className="dialog-field">
              <label>TCP-порты через запятую</label>
              <TextInput
                value={ports}
                onUpdate={setPorts}
                placeholder="443, 8443"
                size="l"
                disabled={loading}
              />
            </div>
          )}
        </form>
      </Dialog.Body>
      <Dialog.Footer
        onClickButtonApply={handleApply as any}
        onClickButtonCancel={onClose}
        textButtonApply={preset === 'off' ? 'Отключить' : 'Применить'}
        textButtonCancel="Отмена"
        loading={loading || saving}
      />
    </Dialog>
  );
}
