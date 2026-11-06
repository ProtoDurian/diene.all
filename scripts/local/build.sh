#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🔨 Building the web app..."
./node_modules/.bin/vite build --config web/vite.config.ts

echo "🔨 Bundling the Worker..."
wrangler deploy --dry-run --outdir dist/worker

for artifact in dist/web/index.html dist/worker/index.js; do
  [[ ! -f ${artifact} ]] && echo "❌ Build artifact missing: ${artifact}" >&2 && exit 1
done
echo "✅ Build artifacts present: dist/web/index.html, dist/worker/index.js"
