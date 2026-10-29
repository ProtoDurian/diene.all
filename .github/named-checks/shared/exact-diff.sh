#!/usr/bin/env bash
set -euo pipefail

# The diff from workspace's .3 commit is the shared payload only (R2): new files
# under this node's paths, plus insertion-only edits to the few parent files
# that register them. Nothing tracked by workspace is deleted, renamed or
# rewritten.

# The graph ancestor: workspace at its recorded .3 commit (parent.sha).
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ workspace .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

# The ten agnostic standards this node owns (owner rulings S1/S3 removed
# authorization and contributor-docs).
topics='datetime|domain-driven-design|functional-practices|software-design-philosophy|solid-principles|stateless-oop-di|testing|three-layer-architecture|utilities|validation'
added_pattern="^(docs/standards/(${topics})/index\.md|\.claude/skills/(${topics})/SKILL\.md|probes/(docs-markdownlint|docs-prettier|standards-inventory|thin-skills)\.ts|\.github/named-checks/shared/[^/]+|\.markdownlint-cli2\.jsonc)$"
# Parent files that may only gain lines: the markdownlint hook and the feature rows.
insert_only_pattern='^(nix/pre-commit\.nix|probes/features\.json)$'

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

while IFS=$'\t' read -r status path; do
  case "${status}" in
  A)
    if [[ ! ${path} =~ ${added_pattern} ]]; then
      echo "❌ added outside the shared payload: ${path}" >&2
      failed=1
    fi
    ;;
  M)
    if [[ ! ${path} =~ ${insert_only_pattern} ]]; then
      echo "❌ parent-owned file modified: ${path}" >&2
      failed=1
    fi
    ;;
  *)
    echo "❌ ${status} of a workspace path: ${path}" >&2
    failed=1
    ;;
  esac
done < <(git -c core.quotePath=false diff --no-renames --name-status "${parent_sha}" "${tree}")

while IFS=$'\t' read -r added deleted path; do
  if [[ ${path} =~ ${insert_only_pattern} && ${deleted} != 0 ]]; then
    echo "❌ ${path} must only gain lines; ${deleted} removed (+${added})" >&2
    failed=1
  fi
done < <(git -c core.quotePath=false diff --no-renames --numstat "${parent_sha}" "${tree}")

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ exact-diff: payload additions and insertion-only registrations against workspace .3 ${parent_sha}"
