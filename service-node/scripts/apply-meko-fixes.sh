#!/usr/bin/env bash
set -euo pipefail

SYSCTL_FILE="/etc/sysctl.d/99-telemt-meko.conf"
NGINX_PORT="${1:-443}"

if [ "$(id -u)" -ne 0 ]; then
  echo "MEKO tuning must be run as root" >&2
  exit 1
fi

if command -v modprobe >/dev/null 2>&1; then
  modprobe tcp_bbr 2>/dev/null || true
fi

cat > "$SYSCTL_FILE" <<'EOF'
# telemt TCP tuning based on MTPROTO_FIX_By_MEKO (via vaalaav/telemt-install)
# SYN limiting is intentionally excluded: do not stack independent limiters.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
fs.file-max = 2097152
net.ipv4.tcp_keepalive_time = 45
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_syncookies = 1
EOF

sysctl -p "$SYSCTL_FILE" || echo "Warning: some MEKO sysctl values are not supported by this kernel" >&2

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "${NGINX_PORT}/tcp"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
  firewall-cmd --permanent --add-port="${NGINX_PORT}/tcp"
  firewall-cmd --reload
fi

echo "MEKO host tuning applied; telemt containers use nofile=65535."
