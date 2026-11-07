#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat .github/named-checks/bun-base/parent.sha)}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

conditional='(^|[^[:alnum:]_])(if|elif|case)[[:space:]]|\[\[?[[:space:]]|(^|[;&|(][[:space:]]*)test[[:space:]]|&&|\|\||\{\{-?[[:space:]]*(if|else|with)[[:space:]}]'
failed=0

# Lines the parent already carries are reported, not failed: they are fixed in the parent.
judge() {
  local file="$1" line="$2" what="$3"
  if git show "${parent_sha}:${file}" 2>/dev/null | grep -Fq -- "${line}"; then
    echo "⚠️ inherited ${what} in ${file} (fix in the parent): ${line}"
  else
    echo "❌ ${what} in ${file}: ${line}" >&2
    failed=1
  fi
}

shopt -s nullglob
for file in tasks/*.yaml; do
  while IFS= read -r line; do
    if [[ ${line} =~ ${conditional} ]]; then
      judge "${file}" "${line}" "conditional in a task cmd"
    fi
  done < <(yq '.tasks[] | (.cmd, (.cmds // [])[]) | select(. != null) | (.cmd // .)' "${file}")
done

for file in Taskfile.yaml tasks/*.yaml; do
  while IFS= read -r line; do
    judge "${file}" "${line}" "scripts/ci call"
  done < <(rg -N 'scripts/ci/' "${file}" || true)
done

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ taskfile-no-logic: no task cmd conditional or scripts/ci call added over shared .3 ${parent_sha}"
