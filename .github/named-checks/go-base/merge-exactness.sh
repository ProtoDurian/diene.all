#!/usr/bin/env bash
set -euo pipefail

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

topics='datetime|domain-driven-design|functional-practices|solid-principles|stateless-oop-di|testing|utilities|validation'
source='(adapters|cmd|lib|tests/(unit|int|sit))/.+\.go|go\.(mod|sum)|\.golangci\.yaml|\.config/go-base\.coverage\.yaml|tests/fixtures/(govulncheck-double\.sh|vulnerable/govulncheck\.json)'
scripts='scripts/ci/(build|deadcode|sit|test|vuln)\.sh|scripts/local/(build|deadcode|deadcode-(lax|production|strict|whole)|down|staticcheck-(production|whole)|test|typecheck|up|vuln)\.sh|scripts/validate/(go-[a-z-]+|sample-journey)\.(sh|awk)'
probes='probes/[a-z-]+\.ts|probes/lib/go\.ts'
docs="docs/developer/go-baseline\\.md|docs/standards/(${topics})/languages/go\\.md"
added_pattern="^((${source})|(${scripts})|(${probes})|(${docs})|tasks/Taskfile\\.test\\.yaml|\\.github/workflows/⚡reusable-(build|dead-code|test|vuln)\\.yaml|\\.claude/skills/go-baseline/SKILL\\.md|\\.github/named-checks/go-base/[^/]+)$"
insert_only_pattern='^(\.dockerignore|\.gitignore|\.github/dependabot\.yml|\.github/workflows/ci\.yaml|CLAUDE\.md|README\.md|Taskfile\.yaml|nix/(env|fmt|packages|pre-commit)\.nix|probes/features\.json|scripts/ci/pre-commit\.sh|scripts/local/setup\.sh)$'
declare -A rewrite_max=()
# Owner-signed whole-file exception: the Go runtime image replaces the parent's stub.
whole_file='^infra/Dockerfile$'

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

while IFS=$'\t' read -r status path; do
  case "${status}" in
  A)
    if [[ ! ${path} =~ ${added_pattern} ]]; then
      echo "❌ added outside the Go toolchain: ${path}" >&2
      failed=1
    fi
    ;;
  M)
    if [[ ! ${path} =~ ${insert_only_pattern} && ! ${path} =~ ${whole_file} && -z ${rewrite_max[${path}]:-} ]]; then
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

echo "✅ merge-exactness: Go additions and anchored edits against shared .3 ${parent_sha}"
