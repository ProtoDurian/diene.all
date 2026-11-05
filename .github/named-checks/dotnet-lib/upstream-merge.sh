#!/usr/bin/env bash
set -euo pipefail

# dotnet-lib is cut from dotnet-base-wo-helm-docker: HEAD contains its recorded .3
# commit, and merging that commit into HEAD again is clean and changes nothing.

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ dotnet-base-wo-helm-docker .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then git fetch --quiet --no-tags --unshallow origin || true; fi

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain dotnet-base-wo-helm-docker .3 ${parent_sha}" >&2
  exit 1
fi

merged="$(git merge-tree --write-tree HEAD "${parent_sha}")" || { echo "❌ merging ${parent_sha} into HEAD conflicts" >&2 && exit 1; }
if [[ ${merged} != "$(git rev-parse 'HEAD^{tree}')" ]]; then
  echo "❌ merging ${parent_sha} into HEAD would change the tree" >&2
  exit 1
fi

echo "✅ upstream-merge: HEAD contains dotnet-base-wo-helm-docker .3 ${parent_sha} and re-merges cleanly"
