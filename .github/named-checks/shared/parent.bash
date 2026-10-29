#!/usr/bin/env bash
# Sourced by this node's named checks; not itself a check (no .sh-executable bit).
# The graph ancestor these checks compare against: workspace at its recorded .3 SHA.

# shellcheck disable=SC2034
parent_sha="${NAMED_CHECKS_PARENT_SHA:-152333b64b2b75099cdae6843757581caad9518e}"

require_parent() {
  if ! git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null; then
    git fetch --quiet --no-tags origin "${parent_sha}" 2>/dev/null || true
  fi
  if ! git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null; then
    echo "❌ workspace .3 commit ${parent_sha} not found; fetch it first" >&2
    exit 1
  fi
}
