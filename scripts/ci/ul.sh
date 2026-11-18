#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${root}"

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  git config --global --add safe.directory "${root}"
fi

ul check

# Each entry's word, or one of its aliases, must appear in the docs of its own
# standard (the template-wide file: anywhere under docs/standards).
bad=0
while IFS=$'\t' read -r file word names; do
  dir="$(dirname "${file}")"
  found=0
  IFS=$'\t' read -r -a list <<<"${names}"
  for name in "${list[@]}"; do
    if grep -rIiqF --exclude=UL.yaml --exclude=UL.md -- "${name}" "${dir}"; then
      found=1
      break
    fi
  done
  if [ "${found}" -eq 0 ]; then
    echo "❌ UL word '${word}' in ${file} is not in the docs under ${dir}" >&2
    bad=1
  fi
done < <(ul all --format json | jq -r '.words[] | [.file, .word, ([.word] + .aliases | join("\t"))] | join("\t")')
if [ "${bad}" -ne 0 ]; then
  exit 1
fi

ul gen --check

echo "✅ UL gates passed"
