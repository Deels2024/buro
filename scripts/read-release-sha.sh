#!/usr/bin/env sh
# Resolve only public Git ref metadata; no credentials or Git objects are needed.
set -eu
git_dir="${1:-.git}"
release="$(cat "$git_dir/HEAD")"
case "$release" in
  'ref: '*)
    ref="${release#ref: }"
    case "$ref" in refs/heads/*|refs/remotes/*) ;; *) echo "Unsupported Git ref." >&2; exit 1;; esac
    case "$ref" in *..*) echo "Invalid Git ref." >&2; exit 1;; esac
    if [ -f "$git_dir/$ref" ]; then
      release="$(cat "$git_dir/$ref")"
    else
      release="$(awk -v ref="$ref" '$2 == ref {print $1}' "$git_dir/packed-refs")"
    fi
    ;;
esac
case "$release" in *[!a-f0-9]*|'') echo "Cannot identify the checkout commit." >&2; exit 1;; esac
[ "${#release}" -eq 40 ] || { echo "Expected a full Git commit SHA." >&2; exit 1; }
printf '%s\n' "$release"
