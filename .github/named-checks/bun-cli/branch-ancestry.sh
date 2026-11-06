#!/usr/bin/env bash
set -euo pipefail

# bun-cli is cut from bun-base-wo-helm: HEAD contains bun-base-wo-helm's recorded .3 commit.

# The graph ancestor: bun-base-wo-helm at its recorded .3 commit (parent.sha).
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ bun-base-wo-helm .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain bun-base-wo-helm .3 ${parent_sha}; the branch is not cut from bun-base-wo-helm" >&2
  exit 1
fi

echo "✅ branch-ancestry: HEAD contains bun-base-wo-helm .3 ${parent_sha}"
