#!/usr/bin/env bash
# Exercise the real production Dockerfile using a local release-asset server.
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

docker build --network=host --build-arg BUREAU_RELEASE_BASE_URL="$BUREAU_RELEASE_BASE_URL" \
  -f flutter/Dockerfile.web -t "bureau/web:$release" .
export BN_RELEASE_SHA="$release"
# The default Compose definition must start without the source-build override.
docker compose -f docker-compose.yml up -d --no-build --wait --wait-timeout 180 web
./scripts/check-release.sh "$release"
docker compose exec -T web sh -c \
  'test "$(cat /usr/share/nginx/html/release-sha.txt)" = "$1" && test -s /usr/share/nginx/html/main.dart.js' sh "$release"
# A legacy forced command leaves BN_RELEASE_SHA unset and uses :local tags.
# The API/worker must still identify the baked commit and become healthy.
for component in api admin web; do docker tag "bureau/$component:$release" "bureau/$component:local"; done
BN_RELEASE_SHA=local docker compose -f docker-compose.yml up -d --no-build --wait --wait-timeout 180
./scripts/check-release.sh "$release"
printf 'Production web delivery passed: checksum rejection, image build, HTTP and legacy release SHA.\n'
