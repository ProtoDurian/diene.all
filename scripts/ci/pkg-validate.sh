#!/usr/bin/env bash
set -euo pipefail

go mod download
./scripts/local/pkg-validate.sh "${1:-all}"

echo "✅ CI Go library validation passed"
