#!/usr/bin/env bash
set -euo pipefail

# The ci shell installs no git hooks and links no .pre-commit-config.yaml. Use
# PRE_COMMIT_CONFIG_FILE when set, else build the generated config from the flake.
# --config leaves no link in the worktree, so a later developer shell still installs its hooks.
config="${PRE_COMMIT_CONFIG_FILE:-}"
if [ -z "${config}" ] && [ ! -e .pre-commit-config.yaml ]; then
  system="$(nix eval --raw --impure --expr builtins.currentSystem)"
  config="$(nix build --no-link --print-out-paths ".#checks.${system}.pre-commit-check.config.configFile")"
fi
if [ -n "${config}" ]; then
  exec pre-commit run --config "${config}" "$@"
fi
exec pre-commit run "$@"
