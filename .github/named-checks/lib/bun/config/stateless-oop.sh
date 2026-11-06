#!/usr/bin/env bash
set -euo pipefail

# src/ is stateless OOP + DI: every function, arrow and method body lives inside
# a class body (parsed with TypeScript, so types never count).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }
[[ -d node_modules/typescript ]] || bun install --frozen-lockfile --ignore-scripts >/dev/null 2>&1 || { echo "❌ cannot install the TypeScript parser" >&2 && exit 1; }

failed=0
for path in "${files[@]}"; do
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | FILE="${path}" bun -e '
    const ts = require(`${process.cwd()}/node_modules/typescript`);
    const file = process.env.FILE;
    const sf = ts.createSourceFile(file, await Bun.stdin.text(), ts.ScriptTarget.Latest, true, /x$/.test(file) ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
    const kind = n => ts.isArrowFunction(n) ? "arrow" : ts.isFunctionExpression(n) || (ts.isFunctionDeclaration(n) && n.body) ? "function"
      : ts.isMethodDeclaration(n) || ts.isGetAccessorDeclaration(n) || ts.isSetAccessorDeclaration(n) ? "method" : undefined;
    const visit = n => {
      if (ts.isClassLike(n)) { ts.forEachChild(n, child => ts.isClassElement(child) ? undefined : visit(child)); return; }
      const k = kind(n);
      if (k) console.log(`${sf.getLineAndCharacterOfPosition(n.getStart(sf)).line + 1}:${k}`);
      ts.forEachChild(n, visit);
    };
    visit(sf);
  ')"
  if [[ -n ${report} ]]; then
    while IFS=: read -r line name; do echo "❌ ${path}:${line}: free ${name} outside a class body" >&2; done <<<"${report}"
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ stateless-oop: ${#files[@]} src/ modules hold functions only inside class bodies"
