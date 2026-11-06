#!/usr/bin/env bash
set -euo pipefail

parent_sha="$(tr -d '[:space:]' <"$(dirname "$0")/parent.sha")"
[[ ${parent_sha} =~ ^[0-9a-f]{40}$ ]] || { echo "❌ parent.sha '${parent_sha}' is not a full 40-hex commit sha" >&2 && exit 1; }
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ helm-wrapper .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain helm-wrapper .3 ${parent_sha}" >&2
  exit 1
fi

echo "✅ branch-ancestry: HEAD contains helm-wrapper .3 ${parent_sha}"
