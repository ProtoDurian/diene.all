#!/usr/bin/env bash
set -euo pipefail

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared-wo-docker-helm .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then git fetch --quiet --no-tags --unshallow origin || true; fi

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain shared-wo-docker-helm .3 ${parent_sha}; the branch is not cut from shared-wo-docker-helm" >&2
  exit 1
fi

echo "✅ branch-ancestry: HEAD contains shared-wo-docker-helm .3 ${parent_sha}"
