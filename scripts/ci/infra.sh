#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

bun install --frozen-lockfile

./scripts/validate/tofu.sh
./scripts/validate/secrets.sh
./scripts/validate/wrangler.sh
