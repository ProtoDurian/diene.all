#!/usr/bin/env bash
set -euo pipefail

# Language is not an axis: no docs/standards/*/languages/typescript.md path
# appears in the diff from bun-base's .3 commit.

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ bun-base .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t touched < <(git -c core.quotePath=false diff --no-renames --name-only "${parent_sha}" "${tree}" |
  grep -E '^docs/standards/[^/]+/languages/typescript\.md$' || true)

if [[ ${#touched[@]} -gt 0 ]]; then
  echo "❌ the strip touches a protected language variant:" >&2
  printf '   %s\n' "${touched[@]}" >&2
  exit 1
fi

echo "✅ language-path-guard: no docs/standards/*/languages/typescript.md path in the diff from ${parent_sha}"
