#!/usr/bin/env bash
set -euo pipefail
release="$(git rev-parse HEAD)"
output="${1:-.releases/artifacts}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
work="$(mktemp -d)"
container="$(docker create "bureau/web:$release")"
cleanup() { docker rm "$container" >/dev/null; rm -rf "$work"; }
trap cleanup EXIT
docker cp "$container:/usr/share/nginx/html/." "$work/"
printf '%s\n' "$release" > "$work/release-sha.txt"
test -s "$work/main.dart.js"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -czf "$output/web.tar.gz" -C "$work" .
(cd "$output" && sha256sum web.tar.gz > web.sha256)
printf 'Packaged tested Flutter files for %s\n' "$release"
