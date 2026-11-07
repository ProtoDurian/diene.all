#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

flutter pub get >/dev/null
dart analyze --fatal-infos --fatal-warnings

echo "✅ Dart analysis passed"
