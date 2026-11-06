#!/usr/bin/env bash
set -euo pipefail

# The three published entry points are re-export-only: after comments, every
# statement is `export [type] { … } from '…'` or `export * [as name] from '…'`.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

for entry in src/index.ts src/build-time.ts src/test-helper/index.ts; do
  source="$(git show "${tree}:${entry}" 2>/dev/null)" || { echo "❌ ${entry} is not tracked" >&2 && failed=1 && continue; }
  # shellcheck disable=SC2016
  report="$(printf '%s' "${source}" | bun -e '
    const text = (await Bun.stdin.text()).replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
    const statements = text.split(";").map(s => s.replace(/\s+/g, " ").trim()).filter(Boolean);
    const reExport = /^export (type )?(\* (as [A-Za-z_$][\w$]* )?|\{[^{}]*\} )from (["\x27])[^"\x27]+\4$/;
    if (statements.length === 0) console.log("NONE");
    for (const s of statements.filter(s => !reExport.test(s))) console.log(s);
  ')"
  if [[ ${report} == "NONE" ]]; then
    echo "❌ ${entry} exports nothing" >&2
    failed=1
  elif [[ -n ${report} ]]; then
    echo "❌ ${entry} carries non-re-export statements:"$'\n'"${report}" >&2
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ re-export-only: src/index.ts, src/build-time.ts and src/test-helper/index.ts only re-export"
