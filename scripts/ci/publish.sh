#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"

./scripts/validate/publish-version.sh "${tag}"

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
dart pub get
cd "${root_dir}/packages/diene_api_engine"

echo "🚀 Publishing diene_api_engine ${tag#v} to pub.dev..."
dart pub publish --force

echo "✅ Published diene_api_engine ${tag#v}"
