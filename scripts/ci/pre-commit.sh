#!/usr/bin/env bash
set -euo pipefail

./scripts/local/pre-commit-run.sh --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
