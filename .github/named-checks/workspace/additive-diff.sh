#!/usr/bin/env bash
set -euo pipefail

main_ref="${NAMED_CHECKS_MAIN_REF:-origin/main}"

if ! git rev-parse --verify --quiet "${main_ref}^{commit}" >/dev/null; then
  echo "❌ ${main_ref} not found; fetch it first (git fetch origin main)" >&2
  exit 1
fi

if ! git merge-base --is-ancestor "${main_ref}" HEAD; then
  echo "❌ HEAD does not contain ${main_ref} ($(git rev-parse --short "${main_ref}")); the branch is not cut from main" >&2
  exit 1
fi

deleted="$(git -c core.quotePath=false diff --no-renames --diff-filter=D --name-only "${main_ref}" "$(git write-tree)")"
if [[ -n ${deleted} ]]; then
  echo "❌ paths tracked at ${main_ref} are deleted at HEAD (diff must be additive):" >&2
  while IFS= read -r path; do echo "   ${path}" >&2; done <<<"${deleted}"
  exit 1
fi

echo "additive: HEAD contains ${main_ref}; no deletions"
