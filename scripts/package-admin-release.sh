#!/usr/bin/env bash
# Extract the Linux/Alpine runtime already built and smoke-tested in CI.
set -euo pipefail
release="$(git rev-parse HEAD)"
output="${1:-.releases/artifacts}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
work="$(mktemp -d)"
container="$(docker create "bureau/admin:$release")"
cleanup() { docker rm "$container" >/dev/null; rm -rf "$work"; }
trap cleanup EXIT
docker cp "$container:/app/." "$work/"
printf '%s\n' "$release" > "$work/release-sha.txt"
test -s "$work/server.js"
test -d "$work/node_modules"
test -d "$work/.next/static"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -czf "$output/admin.tar.gz" -C "$work" .
(cd "$output" && sha256sum admin.tar.gz > admin.sha256)
printf 'Packaged tested admin runtime for %s\n' "$release"
