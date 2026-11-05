#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"

./scripts/validate/go-publish-guard.sh "${tag}"
./scripts/local/build.sh
./scripts/validate/go-proxy-roundtrip.sh "${tag}"

echo "✅ Go module ${tag} is published through the proxy"
