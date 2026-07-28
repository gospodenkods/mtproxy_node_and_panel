import { FormEvent, useEffect, useState } from 'react';
import { Alert, Dialog, TextArea } from '@gravity-ui/uikit';
import { getTelemtConfig, ProxyData, updateTelemtConfig } from '../api';

interface Props {
  open: boolean;
  nodeId: number;
  proxy: ProxyData;
  onClose: () => void;
  onSaved?: () => void;
}

export default function TelemtConfigDialog({ open, nodeId, proxy, onClose, onSaved }: Props) {
  const [config, setConfig] = useState('');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    setError('');
    getTelemtConfig(nodeId, proxy.id)
      .then((result) => setConfig(result.config))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [open, nodeId, proxy.id]);

  const handleSave = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    setError('');
    try {
      const result = await updateTelemtConfig(nodeId, proxy.id, config);
      setConfig(result.config);
      onSaved?.();
      onClose();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} size="l">
      <Dialog.Header caption={`config.toml — ${proxy.name || proxy.id}`} />
      <Dialog.Body>
        <form id="telemt-config-form" onSubmit={handleSave}>
          {error && <div style={{ marginBottom: 12 }}><Alert theme="danger" message={error} /></div>}
          <Alert
            theme="warning"
            message="Сохраняйте секции [general], [server] и [access.users], текущий порт и секрет. При ошибке запуска сервис-нода восстановит предыдущую конфигурацию."
          />
          <div style={{ marginTop: 12 }}>
            <TextArea
              value={config}
              onUpdate={setConfig}
              rows={24}
              size="m"
              disabled={loading}
              controlProps={{ spellCheck: false, style: { fontFamily: 'monospace', fontSize: 12 } }}
            />
          </div>
        </form>
      </Dialog.Body>
      <Dialog.Footer
        onClickButtonApply={handleSave as any}
        onClickButtonCancel={onClose}
        textButtonApply="Сохранить и перезапустить"
        textButtonCancel="Отмена"
        loading={loading || saving}
      />
    </Dialog>
  );
}
