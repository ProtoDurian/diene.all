#!/usr/bin/env bash
set -euo pipefail

# dotnet-base-wo-helm-docker is cut from dotnet-base-wo-helm: HEAD contains dotnet-base-wo-helm's recorded .3 commit.

# The graph ancestor: dotnet-base-wo-helm at its recorded .3 commit (parent.sha).
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ dotnet-base-wo-helm .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain dotnet-base-wo-helm .3 ${parent_sha}; the branch is not cut from dotnet-base-wo-helm" >&2
  exit 1
fi

echo "✅ branch-ancestry: HEAD contains dotnet-base-wo-helm .3 ${parent_sha}"
