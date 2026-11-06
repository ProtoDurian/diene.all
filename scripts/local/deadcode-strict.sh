#!/usr/bin/env bash
set -euo pipefail

./scripts/local/staticcheck-whole.sh
./scripts/local/deadcode-whole.sh
./scripts/local/staticcheck-production.sh
./scripts/local/deadcode-production.sh

echo "✅ Go deadcode strict pass complete"
