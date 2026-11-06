#!/usr/bin/env bash
set -euo pipefail

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ parent commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
root="$(pwd)"
failed=0
checked=0
tick=$'\x60'

exists() {
  local path
  path="$(realpath -m --relative-to="${root}" "${root}/$1")"
  [[ ${path} != ".." && ${path} != ../* ]] && git cat-file -e "${tree}:${path}" 2>/dev/null
}

# payload-purity limits added files to its added_pattern, so this is the payload's markdown
mapfile -t files < <(git -c core.quotePath=false diff --no-renames --name-only --diff-filter=A "${parent_sha}" "${tree}" | grep -E '\.md$' || true)
files+=("CLAUDE.md")

for file in "${files[@]}"; do
  content="$(git cat-file -p "${tree}:${file}")"
  if [[ ${file} == "CLAUDE.md" ]]; then
    content="$(awk '/^# Observability standards$/ { on = 1; print; next } on && /^# / { on = 0 } on' <<<"${content}")"
  fi
  dir="$(dirname "${file}")"
  while IFS= read -r target; do
    target="${target%%#*}"
    [[ -z ${target} ]] && continue
    checked=$((checked + 1))
    if exists "${target}"; then
      continue
    fi
    if [[ ${file} != .claude/skills/* ]] && exists "${dir}/${target}"; then
      continue
    fi
    echo "❌ ${file}: ${target}" >&2
    failed=1
  done < <(awk '/^[[:space:]]*(```|~~~)/ { fence = !fence; next } !fence' <<<"${content}" |
    sed -E "s/${tick}[^${tick}]*${tick}//g" |
    grep -oE '\]\([^)[:space:]]+\)' |
    sed -E 's/^\]\((.*)\)$/\1/' |
    grep -vE '^(https?:|mailto:|#|\{)' || true)
done

if [[ ${failed} -ne 0 ]]; then
  echo "❌ links-resolve: links above resolve neither from the repo root nor (outside .claude/skills/) from their file's folder" >&2
  exit 1
fi

echo "✅ links-resolve: ${checked} relative links in ${#files[@]} files resolve"
