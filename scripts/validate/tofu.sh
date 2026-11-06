#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}/infra/tofu"

echo "📝 Checking OpenTofu formatting..."
tofu fmt -check -recursive

echo "📦 Installing providers from the lock file (no backend)..."
tofu init -backend=false -input=false -lockfile=readonly -no-color >/dev/null

echo "🔨 Validating OpenTofu configuration..."
tofu validate -no-color

echo "✅ OpenTofu configuration is valid"
