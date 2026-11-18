#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${root}"

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  git config --global --add safe.directory "${root}"
fi

ul check

# Every word and alias must appear in the docs of its own standard
# (the template-wide file: anywhere under docs/standards).
bad=0
while IFS=$'\t' read -r file name; do
  dir="$(dirname "${file}")"
  if grep -rIiqF --exclude=UL.yaml --exclude=UL.md -- "${name}" "${dir}"; then
    continue
  fi
  echo "❌ UL word '${name}' in ${file} is not in the docs under ${dir}" >&2
  bad=1
done < <(ul all --format json | jq -r '.words[] | .file as $f | ([.word] + .aliases)[] | [$f, .] | @tsv')
if [ "${bad}" -ne 0 ]; then
  exit 1
fi

ul gen --check

echo "✅ UL gates passed"
