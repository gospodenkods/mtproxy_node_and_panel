#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  MTProto Panel - Обновление            ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Парсим аргументы
FORCE_BRANCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --b=*) FORCE_BRANCH="${1#--b=}"; shift ;;
        --b) FORCE_BRANCH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Проверяем права root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: запустите скрипт с правами root (sudo bash update.sh).${NC}"
    exit 1
fi

# Проверяем что мы в директории с docker-compose.yml
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Ошибка: docker-compose.yml не найден.${NC}"
    echo -e "Запустите скрипт из директории панели (/opt/mtproto-panel/panel)."
    exit 1
fi

# Проверяем что это git-репозиторий (или что родительская директория является им)
GIT_ROOT=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || git -C ".." rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$GIT_ROOT" ]; then
    echo -e "${RED}Ошибка: не найден git-репозиторий.${NC}"
    echo -e "Панель должна быть установлена через git clone."
    exit 1
fi

# Проверяем наличие .env
if [ ! -f ".env" ]; then
    echo -e "${RED}Ошибка: файл .env не найден.${NC}"
    echo -e "Убедитесь что панель была установлена через install.sh."
    exit 1
fi

echo -e "${CYAN}[1/4] Получение обновлений из репозитория...${NC}"

cd "$GIT_ROOT"

# Сохраняем локальные изменения если есть (.env, data/)
git stash --include-untracked 2>/dev/null || true

# Определяем ветку (из аргумента или автоматически)
if [ -n "$FORCE_BRANCH" ]; then
    BRANCH="$FORCE_BRANCH"
else
    BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
    BRANCH=${BRANCH:-main}
fi
echo -e "  Ветка: ${YELLOW}${BRANCH}${NC}"

git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"
git stash pop 2>/dev/null || true

echo -e "${GREEN}  Обновления получены.${NC}"

# Возвращаемся в директорию панели
cd "$(dirname "$0")"

# Фиксируем имя проекта, чтобы volume pgdata всегда именовался одинаково
# независимо от того, из какой директории запущен скрипт
export COMPOSE_PROJECT_NAME=mtproto-panel

echo -e "${CYAN}[2/4] Остановка панели...${NC}"
docker compose down
echo -e "${GREEN}  Панель остановлена.${NC}"

echo -e "${CYAN}[3/4] Загрузка обновлённых образов...${NC}"
if docker compose pull 2>/dev/null; then
    echo -e "${GREEN}  Образы загружены из реестра.${NC}"
else
    echo -e "${YELLOW}  Не удалось загрузить образы из реестра, собираем локально...${NC}"
    BUILDX_NO_DEFAULT_ATTESTATIONS=1 DOCKER_BUILDKIT=1 docker compose build
fi

echo -e "${CYAN}  Запуск панели...${NC}"
docker compose up -d
echo -e "  Ожидание запуска..."
sleep 5

echo -e "${CYAN}[4/4] Проверка статуса...${NC}"

if docker compose ps | grep -q "Up"; then
    echo -e "${GREEN}  Панель успешно запущена!${NC}"
else
    echo -e "${RED}Ошибка: один или несколько контейнеров не запустились.${NC}"
    echo -e "Проверьте логи: docker compose logs"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Обновление панели завершено!          ${NC}"
echo -e "${GREEN}========================================${NC}"
