#!/usr/bin/env bash
set -euo pipefail

# The branch is cut from main and its diff is additive baseline only (R2):
# it contains main's tip and deletes no path tracked at main, except the
# sanctioned removals listed below.

main_ref="${NAMED_CHECKS_MAIN_REF:-origin/main}"

# <path> <reason> — every removal of a main-tracked path must be declared here.
sanctioned_removals=(
  "docs/developer/standard/nix.md|legacy docs path moved to docs/standards/nix/index.md (goals/workspace.md docs migration)"
  ".claude/skills/nix/reference.md|skills are thin triggers; the content lives in docs/standards/nix/index.md"
)

if ! git rev-parse --verify --quiet "${main_ref}^{commit}" >/dev/null; then
  echo "❌ ${main_ref} not found; fetch it first (git fetch origin main)" >&2
  exit 1
fi

if ! git merge-base --is-ancestor "${main_ref}" HEAD; then
  echo "❌ HEAD does not contain ${main_ref} ($(git rev-parse --short "${main_ref}")); the branch is not cut from main" >&2
  exit 1
fi

deleted="$(git diff --no-renames --diff-filter=D --name-only "${main_ref}" HEAD)"
unsanctioned=()
while IFS= read -r path; do
  [[ -z ${path} ]] && continue
  allowed=false
  for entry in "${sanctioned_removals[@]}"; do
    [[ ${entry%%|*} == "${path}" ]] && allowed=true
  done
  "${allowed}" || unsanctioned+=("${path}")
done <<<"${deleted}"

if [[ ${#unsanctioned[@]} -gt 0 ]]; then
  echo "❌ paths tracked at ${main_ref} are deleted at HEAD (diff must be additive):" >&2
  printf '   %s\n' "${unsanctioned[@]}" >&2
  exit 1
fi

echo "additive: HEAD contains ${main_ref}; no unsanctioned deletions"
