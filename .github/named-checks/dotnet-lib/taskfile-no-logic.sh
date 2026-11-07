#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

NAMED_CHECKS_PARENT_SHA="${NAMED_CHECKS_PARENT_SHA:-$(cat .github/named-checks/dotnet-lib/parent.sha)}" \
  exec .github/named-checks/dotnet-base/taskfile-no-logic.sh
