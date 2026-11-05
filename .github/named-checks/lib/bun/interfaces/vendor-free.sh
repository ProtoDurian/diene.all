#!/usr/bin/env bash
set -euo pipefail

# The contract package carries no process, filesystem, terminal or telemetry
# implementation: every module specifier under src/ is relative or names the
# Result package (the helper may also name this package's root), and no source
# touches a runtime global.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t sources < <(git ls-tree -r --name-only "${tree}" -- src | grep -E '\.(ts|mts|cts|js)$' || true)
[[ ${#sources[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }

failed=0
for path in "${sources[@]}"; do
  allowed='^(\.{1,2}/|@atomicloud/diene\.result$)'
  [[ ${path} == src/test-helper/* ]] && allowed='^(\.{1,2}/|@atomicloud/diene\.result$|@atomicloud/diene\.interfaces$)'
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | ALLOWED="${allowed}" bun -e '
    const text = (await Bun.stdin.text()).replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
    const allowed = new RegExp(process.env.ALLOWED);
    const specifiers = [...text.matchAll(/(?:\bfrom\s*|\bimport\s*\(?\s*|\brequire\s*\(\s*)(["\x27])([^"\x27]+)\1/g)].map(m => m[2]);
    for (const s of specifiers) if (!allowed.test(s)) console.log(`import ${s}`);
    for (const g of text.match(/\b(process|Bun|Deno|globalThis|console)\s*\./g) ?? []) console.log(`global ${g.replace(/\s*\.$/, "")}`);
  ')"
  if [[ -n ${report} ]]; then
    while read -r line; do echo "❌ ${path}: ${line}" >&2; done <<<"${report}"
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ vendor-free: ${#sources[@]} src/ modules import only relative paths and @atomicloud/diene.result, and touch no runtime global"
