#!/usr/bin/env sh
# Restores only into a new disposable database. Never overwrites the live database.
set -eu
umask 077
: "${BACKUP_IDENTITY:?Path to the private age identity is required}"
archive="${1:?Encrypted archive is required}"
staging="$(mktemp -d)"
test_db="bureau_restore_$(date -u +%s)_$$"
created=false
cleanup() {
  if [ "$created" = true ]; then docker compose exec -T postgres dropdb -U bureau "$test_db" >/dev/null || true; fi
  rm -rf "$staging"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
age --decrypt -i "$BACKUP_IDENTITY" -o "$staging/payload.tar" "$archive"
# Extract only known members, rather than arbitrary archive paths.
tar -C "$staging" -xf "$staging/payload.tar" database.dump media.tar secrets.tar
tar -tf "$staging/media.tar" >/dev/null
tar -tf "$staging/secrets.tar" >/dev/null
docker compose exec -T postgres createdb -U bureau "$test_db"
created=true
docker compose exec -T postgres pg_restore -U bureau --exit-on-error --no-owner --dbname "$test_db" < "$staging/database.dump"
docker compose exec -T postgres psql -U bureau -d "$test_db" -v ON_ERROR_STOP=1 -c 'SELECT count(*) AS restored_listings FROM listings; SELECT count(*) AS restored_users FROM users;'
printf 'Backup authenticated; database restored in isolation; media and secret archives readable.\n'
