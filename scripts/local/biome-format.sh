#!/usr/bin/env bash
set -euo pipefail

# pre-commit runs this in parallel batches; only one may install.
lock=.biome-install.lock
waited=0
until mkdir "${lock}" 2>/dev/null; do
  ((waited++ < 300)) || { echo "❌ ${lock} held for 300s" >&2 && exit 1; }
  sleep 1
done
trap 'rmdir "${lock}"' EXIT
[[ -x node_modules/.bin/biome ]] || bun install --frozen-lockfile >&2
rmdir "${lock}" && trap - EXIT

exec ./node_modules/.bin/biome format --write --no-errors-on-unmatched "$@"
