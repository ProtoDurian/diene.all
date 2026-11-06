#!/usr/bin/env bash
set -euo pipefail

dest="$1"

prefix="$(jq -r '.bin | to_entries[0].key' package.json)"
[ -z "${prefix}" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1
[ "${prefix}" = "null" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1

case "$2/$3" in
linux/amd64) suffix="linux-x64-baseline" ;;
linux/arm64) suffix="linux-arm64" ;;
darwin/arm64) suffix="darwin-arm64" ;;
*)
  echo "❌ unsupported target: $2/$3" >&2
  exit 1
  ;;
esac

srcpath="${PREBUILT_DIR:-prebuilt}/${prefix}-${suffix}"
[ ! -f "${srcpath}" ] && echo "❌ prebuilt binary not found: ${srcpath} (did compile.sh run into ${PREBUILT_DIR:-prebuilt}/?)" >&2 && exit 1
cp "${srcpath}" "${dest}"
echo "✅ swapped ${srcpath} -> ${dest}"
