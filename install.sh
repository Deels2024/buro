#!/usr/bin/env sh
set -eu

if ! command -v docker >/dev/null 2>&1; then
  echo "Не найден Docker. Установите Docker Engine и повторите запуск."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Не найден Docker Compose v2."
  exit 1
fi

if ! docker compose up --help 2>/dev/null | grep -q -- "--wait"; then
  echo "Нужен Docker Compose 2.20 или новее (поддержка флага --wait)."
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Не найден OpenSSL, необходимый для генерации секретов."
  exit 1
fi

if [ ! -f .env ]; then
  cp .env.example .env
fi

random_hex() {
  openssl rand -hex 32
}

fernet_key() {
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n'
}

replace_placeholder() {
  placeholder="$1"
  value="$2"
  sed -i "s|$placeholder|$value|g" .env
}

if grep -q "__APP_SECRET__" .env; then replace_placeholder "__APP_SECRET__" "$(random_hex)"; fi
if grep -q "__LOOKUP_PEPPER__" .env; then replace_placeholder "__LOOKUP_PEPPER__" "$(random_hex)"; fi
if grep -q "__PII_FERNET_KEY__" .env; then replace_placeholder "__PII_FERNET_KEY__" "$(fernet_key)"; fi
if grep -q "__POSTGRES_PASSWORD__" .env; then replace_placeholder "__POSTGRES_PASSWORD__" "$(random_hex)"; fi
if grep -q "__MINIO_PASSWORD__" .env; then replace_placeholder "__MINIO_PASSWORD__" "$(random_hex)"; fi

. ./.env
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout "${INSTALL_WAIT_TIMEOUT:-300}"

if [ "${BN_ENVIRONMENT:-development}" != "production" ]; then
  docker compose exec -T \
    -e SMOKE_BASE_URL=http://gateway \
    api python scripts/smoke_stack.py
fi

echo
echo "Бюро находок запущено."
echo "Пользовательский сайт: ${PUBLIC_BASE_URL:-http://localhost}"
echo "Админка: ${ADMIN_BASE_URL:-http://admin.localhost}"
echo "API: ${PUBLIC_BASE_URL:-http://localhost}/v1"
echo "Документация API: ${PUBLIC_BASE_URL:-http://localhost}/docs"
echo "MinIO: ${S3_PUBLIC_URL:-http://localhost:9000}"
