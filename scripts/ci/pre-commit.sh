#!/usr/bin/env bash
set -euo pipefail

dotnet restore dotnet-base.slnx
pre-commit run --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
