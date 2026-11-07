#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}"
cd "${root_dir}"

dart pub get
./scripts/validate/dart-package.sh
./scripts/validate/release-policy.sh

cd "${root_dir}/packages/diene_api_engine"

echo "📦 Building pub.dev dry-run archive..."
dart pub publish --dry-run --skip-validation

echo "📚 Generating Dart API documentation..."
dart doc --dry-run

echo "📊 Running pana package analysis..."
"${root_dir}/scripts/validate/pana-score.sh"

echo "✅ Dart package validation passed"
