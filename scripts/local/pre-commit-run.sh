#!/usr/bin/env bash
set -euo pipefail

# The ci shell installs no git hooks and links no .pre-commit-config.yaml; it hands the
# generated config in PRE_COMMIT_CONFIG_FILE. Passing it with --config leaves no link in
# the worktree, so a later developer shell still installs its hooks.
if [ -n "${PRE_COMMIT_CONFIG_FILE:-}" ]; then
  exec pre-commit run --config "${PRE_COMMIT_CONFIG_FILE}" "$@"
fi
exec pre-commit run "$@"
