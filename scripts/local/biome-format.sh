#!/usr/bin/env bash
set -euo pipefail

if [[ ! -x node_modules/.bin/biome ]]; then
  echo "❌ run the setup task first (task setup): dependencies are not installed" >&2
  exit 1
fi
exec ./node_modules/.bin/biome format --write --no-errors-on-unmatched "$@"
