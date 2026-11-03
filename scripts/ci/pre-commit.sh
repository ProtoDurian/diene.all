#!/usr/bin/env bash
set -euo pipefail

bun install --frozen-lockfile
pre-commit run --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
