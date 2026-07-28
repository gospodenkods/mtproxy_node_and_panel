#!/usr/bin/env bash
set -euo pipefail

# Adapted for the mtproxy panel/node Docker layout from:
# https://github.com/Mekotofeuka/MTPROTO_FIX_By_MEKO
# Preset mapping: V3 = TCP fingerprint; V2 = TTL + packet length.

CONFIG_FILE="/etc/mtproxy-meko-firewall.conf"
SERVICE_FILE="/etc/systemd/system/mtproxy-meko-firewall.service"
IPT_CHAIN="MTPR_SYNFIX"
IPT_MARK_CHAIN="MTPR_IOS_MARK"
NFT_TABLE="mtpr_synfix"

usage() {
  echo "Usage: $0 <nft-v3|nft-v2|iptables-v3|iptables-v2|off> <port[,port...]>"
}

validate_ports() {
  local input="$1" port
  IFS=',' read -ra values <<< "$input"
  PORTS=()
  for port in "${values[@]}"; do
    port="${port//[[:space:]]/}"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
      echo "Invalid TCP port: $port" >&2
      exit 2
    fi
    PORTS+=("$port")
  done
  ((${#PORTS[@]} > 0)) || { echo "At least one port is required" >&2; exit 2; }
}

remove_rules() {
  if command -v nft >/dev/null 2>&1; then
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -D INPUT -j "$IPT_CHAIN" 2>/dev/null || true
    iptables -F "$IPT_CHAIN" 2>/dev/null || true
    iptables -X "$IPT_CHAIN" 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j "$IPT_MARK_CHAIN" 2>/dev/null || true
    iptables -t mangle -F "$IPT_MARK_CHAIN" 2>/dev/null || true
    iptables -t mangle -X "$IPT_MARK_CHAIN" 2>/dev/null || true
  fi
}

ensure_package() {
  local command_name="$1" package_name="$2"
  command -v "$command_name" >/dev/null 2>&1 && return
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package_name"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$package_name"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$package_name"
  else
    echo "Cannot install $package_name automatically" >&2
    exit 3
  fi
}

apply_nft() {
  local version="$1" port
  ensure_package nft nftables
  nft delete table inet "$NFT_TABLE" 2>/dev/null || true
  nft add table inet "$NFT_TABLE"
  nft "add chain inet $NFT_TABLE input { type filter hook input priority 0; policy accept; }"
  # Docker-published ports are DNATed before filtering and traverse FORWARD,
  # while host-network/native listeners traverse INPUT. Install the same
  # classifier in both hooks so the selected preset is effective in either
  # deployment mode.
  nft "add chain inet $NFT_TABLE forward { type filter hook forward priority 0; policy accept; }"

  for port in "${PORTS[@]}"; do
    if [[ "$version" == "v3" ]]; then
      nft "add rule inet $NFT_TABLE input tcp dport $port tcp flags & (syn|ack) == syn @th,108,20 0x2ffff @th,160,16 0x204 @th,192,16 0x103 @th,224,24 0x10108 @th,320,32 0x4020000 counter accept comment \"meko_ios_v3_$port\""
      nft "add rule inet $NFT_TABLE forward tcp dport $port tcp flags & (syn|ack) == syn @th,108,20 0x2ffff @th,160,16 0x204 @th,192,16 0x103 @th,224,24 0x10108 @th,320,32 0x4020000 counter accept comment \"meko_ios_v3_fwd_$port\""
    else
      nft "add rule inet $NFT_TABLE input tcp dport $port tcp flags & (syn|ack) == syn ip ttl < 65 meta length 64 counter accept comment \"meko_ios_v2_$port\""
      nft "add rule inet $NFT_TABLE forward tcp dport $port tcp flags & (syn|ack) == syn ip ttl < 65 meta length 64 counter accept comment \"meko_ios_v2_fwd_$port\""
    fi
    nft "add rule inet $NFT_TABLE input tcp dport $port tcp flags & (syn|ack) == syn meter meko_other_$port { ip saddr timeout 60s limit rate 54/minute burst 1 packets } counter accept comment \"meko_other_accept_$port\""
    nft "add rule inet $NFT_TABLE input tcp dport $port tcp flags & (syn|ack) == syn counter reject with tcp reset comment \"meko_other_reject_$port\""
    nft "add rule inet $NFT_TABLE forward tcp dport $port tcp flags & (syn|ack) == syn meter meko_fwd_other_$port { ip saddr timeout 60s limit rate 54/minute burst 1 packets } counter accept comment \"meko_other_accept_fwd_$port\""
    nft "add rule inet $NFT_TABLE forward tcp dport $port tcp flags & (syn|ack) == syn counter reject with tcp reset comment \"meko_other_reject_fwd_$port\""
  done
}

apply_iptables() {
  local version="$1" port
  ensure_package iptables iptables
  iptables -N "$IPT_CHAIN" 2>/dev/null || true
  iptables -F "$IPT_CHAIN"
  iptables -C INPUT -j "$IPT_CHAIN" 2>/dev/null || iptables -I INPUT 1 -j "$IPT_CHAIN"

  if [[ "$version" == "v3" ]]; then
    iptables -t mangle -N "$IPT_MARK_CHAIN" 2>/dev/null || true
    iptables -t mangle -F "$IPT_MARK_CHAIN"
    iptables -t mangle -C PREROUTING -j "$IPT_MARK_CHAIN" 2>/dev/null ||
      iptables -t mangle -I PREROUTING 1 -j "$IPT_MARK_CHAIN"
    iptables -t mangle -A "$IPT_MARK_CHAIN" -m u32 \
      --u32 "32 & 0x000FFFFF = 0x0002FFFF && 40 & 0xFF000000 = 0x02000000 && 44 & 0xFFFF0000 = 0x01030000 && 48 & 0xFFFFFF00 = 0x01010800 && 60 & 0xFFFFFFFF = 0x04020000" \
      -j MARK --set-mark 0x400
  fi

  for port in "${PORTS[@]}"; do
    if [[ "$version" == "v3" ]]; then
      iptables -A "$IPT_CHAIN" -p tcp --dport "$port" --syn -m mark --mark 0x400 -j ACCEPT
    else
      iptables -A "$IPT_CHAIN" -p tcp --dport "$port" --syn -m length --length 64 -m ttl --ttl-lt 65 -j ACCEPT
    fi
    iptables -A "$IPT_CHAIN" -p tcp --dport "$port" --syn \
      -m hashlimit --hashlimit-name "meko_${port}" --hashlimit-mode srcip \
      --hashlimit-upto 54/minute --hashlimit-burst 1 \
      --hashlimit-htable-expire 60000 --hashlimit-htable-size 32768 -j ACCEPT
    iptables -A "$IPT_CHAIN" -p tcp --dport "$port" --syn -j REJECT --reject-with tcp-reset
  done
  iptables -A "$IPT_CHAIN" -j RETURN
}

open_managed_firewall_ports() {
  local port
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    for port in "${PORTS[@]}"; do
      ufw allow "${port}/tcp" >/dev/null
    done
  elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    for port in "${PORTS[@]}"; do
      firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null
    done
    firewall-cmd --reload >/dev/null
  fi
}

install_service() {
  cat > "$CONFIG_FILE" <<EOF
PRESET=$PRESET
PORT_LIST=$PORT_LIST
EOF
  chmod 600 "$CONFIG_FILE"
  cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=MEKO MTProto SYN firewall preset
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/mtproxy-meko-firewall --restore
ExecStop=/usr/local/sbin/mtproxy-meko-firewall off --runtime-only

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable mtproxy-meko-firewall.service >/dev/null 2>&1 || true
}

RESTORE_MODE=false
if [[ "${1:-}" == "--restore" ]]; then
  RESTORE_MODE=true
  [[ -r "$CONFIG_FILE" ]] || exit 0
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set -- "$PRESET" "$PORT_LIST"
fi

PRESET="${1:-}"
PORT_LIST="${2:-}"
[[ -n "$PRESET" ]] || { usage; exit 2; }
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

if [[ "$PRESET" == "off" ]]; then
  remove_rules
  if [[ "${2:-}" != "--runtime-only" ]]; then
    systemctl disable mtproxy-meko-firewall.service >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE" "$CONFIG_FILE"
    systemctl daemon-reload
  fi
  echo "MEKO firewall rules disabled"
  exit 0
fi

case "$PRESET" in
  nft-v3|nft-v2|iptables-v3|iptables-v2) ;;
  *) usage; exit 2 ;;
esac

validate_ports "$PORT_LIST"
remove_rules

case "$PRESET" in
  nft-v3) apply_nft v3 ;;
  nft-v2) apply_nft v2 ;;
  iptables-v3) apply_iptables v3 ;;
  iptables-v2) apply_iptables v2 ;;
esac

open_managed_firewall_ports
if [[ "$RESTORE_MODE" == false ]]; then
  install_service
fi
echo "Applied MEKO firewall preset $PRESET to ports $PORT_LIST"
