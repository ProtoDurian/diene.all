#!/usr/bin/env bash
set -euo pipefail

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

topics='datetime|domain-driven-design|functional-practices|solid-principles|stateless-oop-di|testing|utilities|validation|wire-format'
projects='(App|Lib|UnitTest|IntTest)[A-Za-z0-9]*/[^/]+\.(cs|csproj)|(App|Lib|UnitTest|IntTest)[A-Za-z0-9]*/.+/[^/]+\.cs'
config='dotnet-base\.slnx|global\.json|Directory\.(Build|Packages)\.props|\.config/dotnet-(base\.test\.yaml|tools\.json)'
scripts='scripts/ci/(build|test|dead-code)\.sh|scripts/local/(build|dotnet-dead-code|dotnet-test|test)\.sh|scripts/release/bump\.sh'
probes='probes/(dotnet-[a-z-]+|hook-dotnetlint)\.ts|probes/lib/dotnet\.ts'
docs="docs/developer/dotnet-baseline\\.md|docs/domain/note\\.md|docs/standards/authorization/index\\.md|docs/standards/(${topics})/languages/csharp\\.md"
added_pattern="^((${projects})|(${config})|(${scripts})|(${probes})|(${docs})|tasks/Taskfile\\.test\\.yaml|\\.github/workflows/⚡reusable-(build|test|dead-code)\\.yaml|\\.claude/skills/(authorization|dotnet-base)/SKILL\\.md|\\.github/named-checks/dotnet-base/[^/]+)$"
insert_only_pattern='^(\.dockerignore|\.gitignore|\.github/dependabot\.yml|\.github/workflows/ci\.yaml|CLAUDE\.md|README\.md|Taskfile\.yaml|nix/(env|packages|pre-commit)\.nix|probes/features\.json|scripts/ci/pre-commit\.sh|scripts/local/setup\.sh)$'
# Parent files with a line-local rewrite, and how many parent lines each may drop.
declare -A rewrite_max=(['docs/standards/taskfile/index.md']=2 ['release.yaml']=3)

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

while IFS=$'\t' read -r status path; do
  case "${status}" in
  A)
    if [[ ! ${path} =~ ${added_pattern} ]]; then
      echo "❌ added outside the .NET toolchain: ${path}" >&2
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

echo "✅ merge-down-exactness: .NET additions and anchored edits against shared .3 ${parent_sha}"
