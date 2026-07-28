#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/gospodenkods/mtproxy_node_and_panel.git"
SUITE_DIR="/opt/mtproxy-suite"
NODE_DIR="${SUITE_DIR}/service-node"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите скрипт от root: sudo bash install-node.sh" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git
  else
    echo "Установите git и повторите запуск." >&2
    exit 1
  fi
fi

if [ -d "${SUITE_DIR}/.git" ]; then
  git -C "$SUITE_DIR" fetch origin main
  git -C "$SUITE_DIR" reset --hard origin/main
else
  if [ -e "$SUITE_DIR" ]; then
    echo "${SUITE_DIR} уже существует и не является git-репозиторием." >&2
    exit 1
  fi
  git clone --branch main "$REPO_URL" "$SUITE_DIR"
fi

INSTALL_DIR="$NODE_DIR" bash "${NODE_DIR}/install.sh"
