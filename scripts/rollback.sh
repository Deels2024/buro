#!/usr/bin/env sh
# Application rollback only; schema downgrades are intentionally never automatic.
set -eu
umask 077
mkdir -p .releases
exec 9>.releases/operation.lock
flock -n 9 || { echo "Deployment or backup is already running." >&2; exit 1; }
release="${1:-$(cat .releases/previous 2>/dev/null || true)}"
case "$release" in *[!a-f0-9]*|'') echo "A recorded commit SHA is required." >&2; exit 1;; esac
[ "${#release}" -eq 40 ] || exit 1
[ -f ".releases/$release.compose.yml" ] && [ -f ".releases/$release.nginx.conf" ]
for component in api web admin; do docker image inspect "bureau/$component:$release" >/dev/null; done
export BN_RELEASE_SHA="$release"
# Saved compose uses paths relative to the project, not to .releases.
cp nginx/default.conf .releases/rollback-failed.nginx.conf
cp ".releases/$release.nginx.conf" nginx/default.conf
docker compose --project-directory . -f ".releases/$release.compose.yml" up -d --no-build --wait --wait-timeout 300
./scripts/check-release.sh "$release"
printf '%s\n' "$release" > .releases/current
