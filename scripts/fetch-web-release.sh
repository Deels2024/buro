#!/usr/bin/env sh
# Download the tested web files for this checkout. Never compile on a production VPS.
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
  "$url/web.tar.gz" -o "$work/web.tar.gz"
curl --fail --silent --show-error --location --connect-timeout 15 --max-time 30 --retry 2 \
  "$url/web.sha256" -o "$work/web.sha256"
expected="$(awk 'NF == 2 && $2 == "web.tar.gz" {print $1}' "$work/web.sha256")"
case "$expected" in *[!a-f0-9]*|'') echo "Invalid checksum manifest." >&2; exit 1;; esac
[ "${#expected}" -eq 64 ] || exit 1
(cd "$work" && printf '%s  web.tar.gz\n' "$expected" | sha256sum -c -)
mkdir -p "$destination"
tar -xzf "$work/web.tar.gz" -C "$destination"
[ "$(cat "$destination/release-sha.txt")" = "$release" ]
[ -s "$destination/main.dart.js" ] && [ -s "$destination/index.html" ]
printf 'Installed tested Flutter files for %s\n' "$release"
