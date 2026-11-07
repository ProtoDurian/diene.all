#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

rm -rf dist prebuilt coverage reports
if [[ -d node_modules ]]; then
  find node_modules -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
