#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${root}"

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  git config --global --add safe.directory "${root}"
fi

ul check && ul gen --check

echo "✅ UL gates passed"
