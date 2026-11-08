#!/usr/bin/env bash
set -euo pipefail

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
scope=(-- . ':(exclude).github/named-checks/shared-wo-docker/')
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

numstat="$(git -c core.quotePath=false diff --no-renames --numstat "${parent_sha}" "${tree}" "${scope[@]}")"
deleted_paths="$(git -c core.quotePath=false diff --no-renames --diff-filter=D --name-only "${parent_sha}" "${tree}" "${scope[@]}")"

removed=0
while IFS=$'\t' read -r added dels path; do
  [[ -n ${path} ]] || continue
  if [[ ${added} == - ]]; then
    grep -qxF -- "${path}" <<<"${deleted_paths}" || fail "binary change on a path that is not deleted: ${path}"
    removed=$((removed + 1))
    continue
  fi
  [[ ${added} -eq 0 ]] || fail "${path} adds ${added} line(s) over shared .3"
  removed=$((removed + dels))
done <<<"${numstat}"

[[ ${removed} -gt 0 ]] || fail "no line removed from shared .3 ${parent_sha}: the strip is empty"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ removal-only: HEAD only deletes lines from shared .3 ${parent_sha} (${removed} removed, 0 added)"
