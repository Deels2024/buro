#!/usr/bin/env bash
# Exercise both production Dockerfiles using a local release-asset server.
set -euo pipefail
release="$(git rev-parse HEAD)"
work="$(mktemp -d)"
server=""
cleanup() {
  if [ -n "$server" ]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/runtime-$release"
cp .releases/artifacts/web.tar.gz .releases/artifacts/web.sha256 "$work/runtime-$release/"
cp .releases/artifacts/admin.tar.gz .releases/artifacts/admin.sha256 "$work/runtime-$release/"
python3 -m http.server 18765 --bind 127.0.0.1 --directory "$work" >"$work/http.log" 2>&1 &
server="$!"
export BUREAU_RELEASE_BASE_URL=http://127.0.0.1:18765
for attempt in {1..30}; do
  if curl --fail --silent "$BUREAU_RELEASE_BASE_URL/runtime-$release/web.sha256" >/dev/null; then break; fi
  sleep 0.2
done

# Corrupted bytes must fail before they are installed.
printf 'corrupt' >> "$work/runtime-$release/web.tar.gz"
if sh scripts/fetch-web-release.sh "$release" "$work/rejected" >"$work/rejected.log" 2>&1; then
  echo 'Corrupt web artifact was accepted.' >&2; exit 1
fi
test ! -d "$work/rejected"
cp .releases/artifacts/web.tar.gz "$work/runtime-$release/web.tar.gz"
printf 'corrupt' >> "$work/runtime-$release/admin.tar.gz"
if sh scripts/fetch-admin-release.sh "$release" "$work/rejected-admin" >"$work/rejected-admin.log" 2>&1; then
  echo 'Corrupt admin artifact was accepted.' >&2; exit 1
fi
test ! -d "$work/rejected-admin"
cp .releases/artifacts/admin.tar.gz "$work/runtime-$release/admin.tar.gz"

docker build --network=host --build-arg BUREAU_RELEASE_BASE_URL="$BUREAU_RELEASE_BASE_URL" \
  -f flutter/Dockerfile.web -t "bureau/web:$release" .
docker build --network=host --build-arg BUREAU_RELEASE_BASE_URL="$BUREAU_RELEASE_BASE_URL" \
  -f admin/Dockerfile -t "bureau/admin:$release" .
export BN_RELEASE_SHA="$release"
# The default Compose definition must start without the source-build override.
docker compose -f docker-compose.yml up -d --no-build --wait --wait-timeout 180 web admin
./scripts/check-release.sh "$release"
docker compose exec -T web sh -c \
  'test "$(cat /usr/share/nginx/html/release-sha.txt)" = "$1" && test -s /usr/share/nginx/html/main.dart.js' sh "$release"
docker compose exec -T admin sh -c \
  'test "$(cat /app/release-sha.txt)" = "$1" && test -s /app/server.js' sh "$release"
docker compose exec -T api python - <<'PY'
from urllib.request import urlopen

with urlopen('http://admin:3000/', timeout=10) as response:
    assert response.status == 200
    assert 'Бюро' in response.read().decode()
print('Prebuilt admin runtime delivery passed.')
PY
# A previously cached iframe must not receive 304 from normalized archive mtimes.
docker compose exec -T api python - <<'PY'
from urllib.request import Request, urlopen

for headers in [
    {'If-Modified-Since': 'Thu, 01 Jan 2099 00:00:00 GMT'},
    {'If-None-Match': '"0-38a"'},
]:
    request = Request('http://web/yandex-map.html?v=2', headers=headers)
    with urlopen(request, timeout=10) as response:
        assert response.status == 200
        assert 'no-store' in response.headers.get('Cache-Control', '')
        assert response.headers.get('ETag') is None
        assert 'id="retry"' in response.read().decode()
print('Map iframe upgrade delivery passed.')
PY
# A legacy forced command leaves BN_RELEASE_SHA unset and uses :local tags.
# The API/worker must still identify the baked commit and become healthy.
docker compose stop worker
docker compose exec -T api python -c \
  'import os,redis; r=redis.Redis.from_url(os.environ["BN_REDIS_URL"]); assert not r.exists("bureau:worker:lease"), "Worker did not release its lease on SIGTERM"'
for component in api admin web openclip; do docker tag "bureau/$component:$release" "bureau/$component:local"; done
BN_RELEASE_SHA=local docker compose -f docker-compose.yml up -d --no-build --wait --wait-timeout 180
./scripts/check-release.sh "$release"
printf 'Production web/admin delivery passed: checksum rejection, image build, HTTP and legacy release SHA.\n'
