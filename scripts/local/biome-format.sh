#!/usr/bin/env bash
set -euo pipefail

[[ -x node_modules/.bin/biome ]] || bun install --frozen-lockfile >&2
exec ./node_modules/.bin/biome format --write --no-errors-on-unmatched "$@"
