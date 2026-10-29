#!/usr/bin/env bash
set -euo pipefail

# bun-base is cut from shared: HEAD contains shared's recorded .3 commit.

# The graph ancestor: shared at its recorded .3 commit (parent.sha).
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain shared .3 ${parent_sha}; the branch is not cut from shared" >&2
  exit 1
fi

echo "✅ branch-ancestry: HEAD contains shared .3 ${parent_sha}"
