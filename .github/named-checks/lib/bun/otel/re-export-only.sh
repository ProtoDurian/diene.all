#!/usr/bin/env bash
set -euo pipefail

# The two published entry points are re-export-only: every statement is
# `export [type] { … } from '…'` or `export * [as name] from '…'` (parsed with TypeScript).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
[[ -d node_modules/typescript ]] || bun install --frozen-lockfile --ignore-scripts >/dev/null 2>&1 || { echo "❌ cannot install the TypeScript parser" >&2 && exit 1; }
failed=0

for entry in src/index.ts src/test-helper/index.ts; do
  source="$(git show "${tree}:${entry}" 2>/dev/null)" || { echo "❌ ${entry} is not tracked" >&2 && failed=1 && continue; }
  # shellcheck disable=SC2016
  report="$(printf '%s' "${source}" | FILE="${entry}" bun -e '
    const ts = require(`${process.cwd()}/node_modules/typescript`);
    const sf = ts.createSourceFile(process.env.FILE, await Bun.stdin.text(), ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
    if (sf.parseDiagnostics.length > 0) console.log(`does not parse: ${sf.parseDiagnostics[0].messageText}`);
    else if (sf.statements.length === 0) console.log("NONE");
    for (const s of sf.statements) {
      if (ts.isExportDeclaration(s) && s.moduleSpecifier && ts.isStringLiteral(s.moduleSpecifier) && !s.modifiers?.length) continue;
      console.log(`${sf.getLineAndCharacterOfPosition(s.getStart(sf)).line + 1}: ${s.getText(sf).replace(/\s+/g, " ").slice(0, 100)}`);
    }
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

echo "✅ re-export-only: src/index.ts and src/test-helper/index.ts only re-export"
