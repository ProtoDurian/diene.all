#!/usr/bin/env bash
set -euo pipefail

# src/index.ts is a re-export-only surface: after comments, every statement is
# `export [type] { … } from '…'` or `export * [as name] from '…'`. No import,
# declaration, expression or local export.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
entry="src/index.ts"

source="$(git show "${tree}:${entry}" 2>/dev/null)" || { echo "❌ ${entry} is not tracked" >&2 && exit 1; }

# shellcheck disable=SC2016
report="$(printf '%s' "${source}" | bun -e '
  const text = (await Bun.stdin.text()).replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  const statements = text.split(";").map(s => s.replace(/\s+/g, " ").trim()).filter(Boolean);
  const reExport = /^export (type )?(\* (as [A-Za-z_$][\w$]* )?|\{[^{}]*\} )from (["\x27])[^"\x27]+\4$/;
  const bad = statements.filter(s => !reExport.test(s));
  if (statements.length === 0) console.log("NONE");
  for (const s of bad) console.log(s);
')"

if [[ ${report} == "NONE" ]]; then
  echo "❌ ${entry} exports nothing" >&2
  exit 1
fi
if [[ -n ${report} ]]; then
  echo "❌ ${entry} carries non-re-export statements:"$'\n'"${report}" >&2
  exit 1
fi

echo "✅ re-export-only: ${entry} is $(printf '%s' "${source}" | grep -c '^export ') re-export statements and comments"
