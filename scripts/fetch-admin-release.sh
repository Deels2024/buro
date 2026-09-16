#!/usr/bin/env sh
# Never run npm/Next.js compilation on the live production VPS.
set -eu
release="${1:?Release SHA is required}"
destination="${2:?Destination is required}"
case "$release" in *[!a-f0-9]*|'') exit 1;; esac
[ "${#release}" -eq 40 ] || exit 1
base="${BUREAU_RELEASE_BASE_URL:-https://github.com/Deels2024/buro/releases/download}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM
url="$base/runtime-$release"
curl --fail --silent --show-error --location --connect-timeout 15 --max-time 180 --retry 2 \
  "$url/admin.tar.gz" -o "$work/admin.tar.gz"
curl --fail --silent --show-error --location --connect-timeout 15 --max-time 30 --retry 2 \
  "$url/admin.sha256" -o "$work/admin.sha256"
expected="$(awk 'NF == 2 && $2 == "admin.tar.gz" {print $1}' "$work/admin.sha256")"
case "$expected" in *[!a-f0-9]*|'') echo "Invalid checksum manifest." >&2; exit 1;; esac
[ "${#expected}" -eq 64 ] || exit 1
(cd "$work" && printf '%s  admin.tar.gz\n' "$expected" | sha256sum -c -)
mkdir -p "$work/runtime"
tar -xzf "$work/admin.tar.gz" -C "$work/runtime"
[ "$(cat "$work/runtime/release-sha.txt")" = "$release" ]
[ -s "$work/runtime/server.js" ]
[ -d "$work/runtime/node_modules" ] && [ -d "$work/runtime/.next/static" ]
mkdir -p "$destination"
cp -a "$work/runtime/." "$destination/"
printf 'Installed tested admin runtime for %s\n' "$release"
