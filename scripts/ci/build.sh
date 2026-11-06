#!/usr/bin/env bash
set -euo pipefail

./scripts/local/typecheck.sh
./scripts/local/build.sh

echo "✅ CI Go build passed"
