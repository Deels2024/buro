#!/usr/bin/env sh
# Run from the project directory in a planned maintenance window.
set -eu
umask 077
command -v age >/dev/null || { echo "Install age before creating encrypted backups." >&2; exit 1; }
: "${BACKUP_RECIPIENT:?Set the public age recipient (age1...)}"
backup_dir="${BACKUP_DIR:-./backups}"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
staging="$(mktemp -d)"
paused=false
cleanup() {
  if [ "$paused" = true ]; then docker compose unpause minio api worker >/dev/null || true; fi
  rm -rf "$staging"
}
trap cleanup EXIT HUP INT TERM
# Pause writers and object storage together so DB references and media are consistent.
docker compose pause api worker minio >/dev/null
paused=true
docker compose exec -T postgres pg_dump -U bureau -d bureau -Fc > "$staging/database.dump"
minio_container="$(docker compose ps -q minio)"
api_container="$(docker compose ps -q api)"
docker run --rm --network none --volumes-from "$minio_container:ro" alpine:3.20 tar -C /data -cf - . > "$staging/media.tar"
docker run --rm --network none --volumes-from "$api_container:ro" alpine:3.20 tar -C /run/bureau-secrets -cf - . > "$staging/secrets.tar"
cp .env docker-compose.yml "$staging/"
cp nginx/default.conf "$staging/nginx.conf"
git rev-parse HEAD > "$staging/checkout-sha"
if [ -f .releases/current ]; then cp .releases/current "$staging/active-sha"; else printf 'unknown\n' > "$staging/active-sha"; fi
docker compose unpause minio api worker >/dev/null
paused=false
archive="$backup_dir/bureau-$(date -u +%Y%m%dT%H%M%SZ).tar.age"
tar -C "$staging" -cf "$staging/payload.tar" database.dump media.tar secrets.tar .env docker-compose.yml nginx.conf checkout-sha active-sha
age -r "$BACKUP_RECIPIENT" -o "$archive.partial" "$staging/payload.tar"
mv "$archive.partial" "$archive"
printf 'Encrypted backup: %s\n' "$archive"
