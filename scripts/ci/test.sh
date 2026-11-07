#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"

./scripts/local/test.sh "${mode}" --coverage

echo "✅ ${mode} CI tests complete"
