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
chmod 600 .env
export BN_RELEASE_SHA="$(git rev-parse HEAD)"

if [ "${BN_ENVIRONMENT:-development}" = "production" ]; then
  if [ -z "${BN_SMSC_LOGIN:-}" ] || [ -z "${BN_SMSC_PASSWORD:-}" ]; then
    echo "Production SMSC credentials are missing: set BN_SMSC_LOGIN and BN_SMSC_PASSWORD in .env." >&2
    exit 1
  fi
  case "${PUBLIC_BASE_URL:-}" in
    https://*) ;;
    *) echo "Production PUBLIC_BASE_URL must be the canonical HTTPS domain." >&2; exit 1 ;;
  esac
  case "${S3_PUBLIC_URL:-}" in
    https://*) ;;
    *) echo "Set S3_PUBLIC_URL=https://edinburo.ru for signed uploads through the gateway." >&2; exit 1 ;;
  esac
  if [ "${ADMIN_COOKIE_SECURE:-false}" != "true" ]; then
    echo "Production ADMIN_COOKIE_SECURE must be true." >&2; exit 1
  fi
  case "${BN_SMSC_URL:-https://smsc.ru/sys/send.php}" in
    https://*) ;;
    *)
      echo "Production BN_SMSC_URL must use HTTPS." >&2
      exit 1
      ;;
  esac
fi

docker compose config --quiet
# Build all images before replacing healthy containers. Never print success after a failed build.
COMPOSE_PARALLEL_LIMIT=1 docker compose build
mkdir -p .releases
chmod 700 .releases
if [ -f .releases/current ]; then cp .releases/current .releases/previous; fi
cp docker-compose.yml ".releases/$BN_RELEASE_SHA.compose.yml"
cp nginx/default.conf ".releases/$BN_RELEASE_SHA.nginx.conf"
if ! docker compose up -d --no-build --wait --wait-timeout "${INSTALL_WAIT_TIMEOUT:-300}"; then
  echo "Release activation failed. Previous images are retained for scripts/rollback.sh." >&2
  exit 1
fi
./scripts/check-release.sh "$BN_RELEASE_SHA"
printf '%s\n' "$BN_RELEASE_SHA" > .releases/current

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
