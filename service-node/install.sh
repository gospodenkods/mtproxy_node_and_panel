#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-/opt/mtproxy-suite/service-node}"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  MTProto Service Node — Установка      ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Ошибка: запустите скрипт от root (sudo).${NC}"
    echo -e "  sudo bash <(wget -qO- ...)"
    exit 1
fi

# Check curl
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}curl не найден. Устанавливаю...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq curl
    elif command -v yum &> /dev/null; then
        yum install -y -q curl
    elif command -v apk &> /dev/null; then
        apk add --no-cache curl
    fi
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Не удалось установить curl.${NC}"
        exit 1
    fi
fi

# Check openssl
if ! command -v openssl &> /dev/null; then
    echo -e "${YELLOW}openssl не найден. Устанавливаю...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq openssl
    elif command -v yum &> /dev/null; then
        yum install -y -q openssl
    elif command -v apk &> /dev/null; then
        apk add --no-cache openssl
    fi
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}Не удалось установить openssl.${NC}"
        exit 1
    fi
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker не найден. Устанавливаю Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка установки Docker.${NC}"
        exit 1
    fi
fi

if ! docker compose version &> /dev/null 2>&1; then
    echo -e "${YELLOW}Docker Compose не найден. Устанавливаю...${NC}"
    COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    COMPOSE_VERSION=${COMPOSE_VERSION:-v2.34.0}
    ARCH=$(uname -m)
    [ "$ARCH" = "x86_64" ] && ARCH="x86_64"
    [ "$ARCH" = "aarch64" ] && ARCH="aarch64"
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${ARCH}" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

if ! docker compose version &> /dev/null 2>&1; then
    echo -e "${RED}Не удалось установить Docker Compose.${NC}"
    exit 1
fi

# Check git
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}Git не найден. Устанавливаю git...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq git
    elif command -v yum &> /dev/null; then
        yum install -y -q git
    elif command -v apk &> /dev/null; then
        apk add --no-cache git
    fi
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Не удалось установить git.${NC}"
        exit 1
    fi
fi

# The monorepo is prepared by the root install-node.sh wrapper.
if [ ! -f "$INSTALL_DIR/docker-compose.yml" ] || [ ! -f "$INSTALL_DIR/package.json" ]; then
    echo -e "${RED}Файлы сервис-ноды не найдены в ${INSTALL_DIR}.${NC}"
    echo -e "Запускайте установку через корневой install-node.sh."
    exit 1
fi
cd "$INSTALL_DIR"

# Ask for port
echo ""
read -p "Порт сервис-ноды [8443]: " PORT
PORT=${PORT:-8443}

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo -e "${RED}Некорректный номер порта${NC}"
    exit 1
fi

read -p "Порт прокси (nginx) [443]: " NGINX_PORT
NGINX_PORT=${NGINX_PORT:-443}

if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_PORT" -lt 1 ] || [ "$NGINX_PORT" -gt 65535 ]; then
    echo -e "${RED}Некорректный номер порта${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}MEKO SYN firewall preset:${NC}"
echo "  1) nftables V3 — TCP fingerprint, рекомендуется для Docker"
echo "  2) nftables V2 — TTL + packet length"
echo "  3) iptables V3 — u32 fingerprint"
echo "  4) iptables V2 — TTL + packet length"
echo "  5) Не применять"
read -p "Выбор [1]: " FIREWALL_CHOICE
case "${FIREWALL_CHOICE:-1}" in
    1) FIREWALL_PRESET="nft-v3" ;;
    2) FIREWALL_PRESET="nft-v2" ;;
    3) FIREWALL_PRESET="iptables-v3" ;;
    4) FIREWALL_PRESET="iptables-v2" ;;
    5) FIREWALL_PRESET="off" ;;
    *) echo -e "${RED}Некорректный вариант firewall preset.${NC}"; exit 1 ;;
esac

# Generate 32-char token
AUTH_TOKEN=$(openssl rand -hex 16)

echo ""
echo -e "${GREEN}Конфигурация:${NC}"
echo -e "  Порт API:    ${YELLOW}${PORT}${NC}"
echo -e "  Порт прокси: ${YELLOW}${NGINX_PORT}${NC}"
echo -e "  Токен: ${YELLOW}${AUTH_TOKEN}${NC}"
echo ""
echo -e "${YELLOW}⚠  СОХРАНИТЕ ТОКЕН! Он понадобится для подключения из панели.${NC}"
echo ""

# Create .env file
cat > .env << EOF
PORT=${PORT}
NGINX_PORT=${NGINX_PORT}
AUTH_TOKEN=${AUTH_TOKEN}
EOF

# Create data directory
mkdir -p data

# Apply the host-level part of the MEKO fixes. Container-level nofile limits and
# telemt settings are applied by the service node when each proxy is created.
bash scripts/apply-meko-fixes.sh "$NGINX_PORT"
install -m 0755 scripts/apply-meko-firewall.sh /usr/local/sbin/mtproxy-meko-firewall
/usr/local/sbin/mtproxy-meko-firewall "$FIREWALL_PRESET" "$NGINX_PORT"

# Build and start
echo -e "${CYAN}Запуск сервис-ноды...${NC}"
export COMPOSE_PROJECT_NAME=mtproto-node
docker network create mtproto-net 2>/dev/null || true

echo -e "  Загрузка образа из GHCR..."
if docker compose pull 2>/dev/null; then
    echo -e "  ${GREEN}Образ загружен из GHCR${NC}"
else
    echo -e "${YELLOW}  Не удалось загрузить образ, собираем локально (может занять несколько минут)...${NC}"
    if ! docker compose build; then
        echo -e "${RED}Ошибка при сборке образа.${NC}"
        exit 1
    fi
fi

if ! docker compose up -d; then
    echo -e "${RED}Ошибка при запуске контейнеров.${NC}"
    exit 1
fi

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
SERVER_IP=${SERVER_IP:-"0.0.0.0"}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Сервис-нода запущена!                 ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "  API:     ${CYAN}http://${SERVER_IP}:${PORT}${NC}"
echo -e "  Токен:   ${YELLOW}${AUTH_TOKEN}${NC}"
echo -e "  Каталог: ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "${GREEN}========================================${NC}"
