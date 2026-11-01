#!/usr/bin/env bash
set -euo pipefail

# The diff from shared's .3 commit is the bun toolchain only (R2): new files on
# this node's paths, insertion-only registrations in parent files, and three
# line-local rewrites (the Dockerfile stub, the pre-commit source, the release
# prepare hook). Nothing tracked by shared is deleted or renamed.

# The graph ancestor: shared at its recorded .3 commit (parent.sha).
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

# The TypeScript variants of the shared standards this node owns.
topics='datetime|domain-driven-design|functional-practices|solid-principles|stateless-oop-di|testing|utilities|validation'
config='package\.json|bun\.lock|tsconfig\.json|biome\.json|bunfig\.(unit|int)\.toml|knip(\.production)?(\.llm)?\.json|codecov\.yml'
scripts='scripts/ci/(build|test)\.sh|scripts/local/(build|deadcode)\.sh|scripts/release/bump\.sh'
probes='probes/bun-[a-z-]+\.ts|probes/lib/(bun-command|lcov)\.ts'
added_pattern="^((${config})|src/.+\.ts|tests/.+\.(ts|toml)|tasks/Taskfile\.test\.yaml|${scripts}|${probes}|\.github/workflows/⚡reusable-(build|test)\.yaml|docs/developer/bun-baseline\.md|docs/standards/(${topics})/languages/typescript\.md|\.github/named-checks/bun-base/[^/]+)$"
# Parent files that may only gain lines.
insert_only_pattern='^(\.dockerignore|\.gitignore|\.github/workflows/ci\.yaml|CLAUDE\.md|README\.md|Taskfile\.yaml|nix/env\.nix|nix/packages\.nix|probes/features\.json|scripts/local/setup\.sh)$'
# Parent files with a line-local rewrite, and how many parent lines each may drop.
declare -A rewrite_max=(['infra/Dockerfile']=11 ['nix/pre-commit.nix']=1 ['release.yaml']=3)

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

while IFS=$'\t' read -r status path; do
  case "${status}" in
  A)
    if [[ ! ${path} =~ ${added_pattern} ]]; then
      echo "❌ added outside the bun toolchain: ${path}" >&2
      failed=1
    fi
    ;;
  M)
    if [[ ! ${path} =~ ${insert_only_pattern} && -z ${rewrite_max[${path}]:-} ]]; then
      echo "❌ parent-owned file modified: ${path}" >&2
      failed=1
    fi
    ;;
  *)
    echo "❌ ${status} of a shared path: ${path}" >&2
    failed=1
    ;;
  esac
done < <(git -c core.quotePath=false diff --no-renames --name-status "${parent_sha}" "${tree}")

while IFS=$'\t' read -r added deleted path; do
  if [[ ${path} =~ ${insert_only_pattern} && ${deleted} != 0 ]]; then
    echo "❌ ${path} must only gain lines; ${deleted} removed (+${added})" >&2
    failed=1
  fi
  limit="${rewrite_max[${path}]:-}"
  if [[ -n ${limit} && ${deleted} -gt ${limit} ]]; then
    echo "❌ ${path} may drop at most ${limit} parent lines; ${deleted} removed (+${added})" >&2
    failed=1
  fi
done < <(git -c core.quotePath=false diff --no-renames --numstat "${parent_sha}" "${tree}")

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ exact-diff: bun toolchain additions and anchored edits against shared .3 ${parent_sha}"
