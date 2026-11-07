#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

NAMED_CHECKS_PARENT_SHA="$(cat .github/named-checks/bun-cli/parent.sha)" exec .github/named-checks/bun-base/taskfile-no-logic.sh
