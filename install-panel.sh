#!/usr/bin/env bash
set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/gospodenkods/mtproxy_node_and_panel/main/install.sh"
tmp_script=$(mktemp)
trap 'rm -f "$tmp_script"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$SCRIPT_URL" -o "$tmp_script"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp_script" "$SCRIPT_URL"
else
  echo "Требуется curl или wget." >&2
  exit 1
fi

bash "$tmp_script"
