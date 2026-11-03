#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "📦 Installing dependencies..."
bun install --frozen-lockfile

echo "📝 Repository dead code"
./node_modules/.bin/knip

echo "📝 Production dead code"
./node_modules/.bin/knip --production --include files

echo "✅ Dead-code check complete"
