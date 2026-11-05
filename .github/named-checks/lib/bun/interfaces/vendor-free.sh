#!/usr/bin/env bash
set -euo pipefail

# The contract package carries no process, filesystem, terminal or telemetry
# implementation: every module specifier under src/ is a string literal that is
# relative or names the Result package (the helper may also name this package's
# root), and no source names a runtime global.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }

failed=0
for path in "${files[@]}"; do
  if [[ ! ${path} =~ \.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$ ]]; then
    echo "❌ ${path}: not a TypeScript/JavaScript source" >&2
    failed=1
    continue
  fi
  allowed='^(\.{1,2}/|@atomicloud/diene\.result$)'
  [[ ${path} == src/test-helper/* ]] && allowed='^(\.{1,2}/|@atomicloud/diene\.result$|@atomicloud/diene\.interfaces$)'
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | ALLOWED="${allowed}" bun -e '
    const src = await Bun.stdin.text();
    const strings = [];
    let out = "", i = 0, prev = "";
    const regexBefore = /[(,=:[!&|?{};+\-*%<>~^]$|\b(return|typeof|case|do|else|in|of|void|yield|await)$/;
    const readString = q => {
      let s = "";
      for (i++; i < src.length && src[i] !== q; i++) s += src[i] === "\\" ? src[i] + src[++i] : src[i];
      i++;
      return s;
    };
    while (i < src.length) {
      const c = src[i], n = src[i + 1];
      if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
      if (c === "/" && n === "*") { i = src.indexOf("*/", i + 2); i = i < 0 ? src.length : i + 2; continue; }
      if (c === "\x27" || c === "\"") { strings.push(readString(c)); out += `"S${strings.length - 1}"`; prev = "\""; continue; }
      if (c === "`") {
        let s = "", dynamic = false;
        for (i++; i < src.length && src[i] !== "`"; i++) {
          if (src[i] === "\\") { s += src[i] + src[++i]; continue; }
          if (src[i] === "$" && src[i + 1] === "{") { dynamic = true; let depth = 0; for (; i < src.length; i++) { if (src[i] === "{") depth++; if (src[i] === "}" && --depth === 0) break; out += src[i] === "$" ? " " : src[i] === "{" ? " " : src[i]; } continue; }
          s += src[i];
        }
        i++;
        if (dynamic) { out += " T "; } else { strings.push(s); out += `"S${strings.length - 1}"`; }
        prev = "\"";
        continue;
      }
      if (c === "/" && regexBefore.test(out.trimEnd())) {
        for (i++; i < src.length && src[i] !== "/"; i++) { if (src[i] === "\\") i++; else if (src[i] === "[") { while (i < src.length && src[i] !== "]") { if (src[i] === "\\") i++; i++; } } }
        for (i++; /[a-z]/.test(src[i] ?? ""); i++);
        out += " R ";
        continue;
      }
      out += c; i++;
    }
    const allowed = new RegExp(process.env.ALLOWED);
    const specifier = /(?:\bfrom|\bimport|\bimport\s*\(|\brequire\s*\()\s*"S(\d+)"/g;
    for (const m of out.matchAll(specifier)) if (!allowed.test(strings[+m[1]])) console.log(`import ${strings[+m[1]]}`);
    for (const m of out.matchAll(/\b(import|require)\s*\(\s*(?!"S\d+"\s*\))/g)) console.log(`non-literal ${m[1]}()`);
    const globals = /(?<![.\w$])(process|Bun|Deno|globalThis|global|window|self|console|Buffer|fetch|require|module|exports|__dirname|__filename|setTimeout|setInterval|setImmediate|queueMicrotask|performance|navigator|crypto|XMLHttpRequest|WebSocket)\b(?!\s*:)/g;
    for (const m of out.matchAll(globals)) console.log(`global ${m[1]}`);
  ')"
  if [[ -n ${report} ]]; then
    while read -r line; do echo "❌ ${path}: ${line}" >&2; done <<<"$(sort -u <<<"${report}")"
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ vendor-free: ${#files[@]} src/ modules import only literal relative paths and @atomicloud/diene.result, and name no runtime global"
