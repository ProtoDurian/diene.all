#!/usr/bin/env bash
set -euo pipefail

# src/ is stateless OOP + DI: outside class bodies, interfaces and type aliases
# no arrow or function expression appears anywhere at module level.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }

failed=0
for path in "${files[@]}"; do
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | bun -e '
    const src = await Bun.stdin.text();
    // Blank comments, strings, templates and regexes in place so offsets and lines survive.
    const code = src.split("");
    const blank = (from, to) => { for (let k = from; k < to; k++) if (code[k] !== "\n") code[k] = " "; };
    const regexBefore = /[(,=:[!&|?{};+\-*%<>~^]$|\b(return|typeof|case|do|else|in|of|void|yield|await)$/;
    let i = 0;
    while (i < src.length) {
      const c = src[i], n = src[i + 1], start = i;
      if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; blank(start, i); continue; }
      if (c === "/" && n === "*") { i = src.indexOf("*/", i + 2); i = i < 0 ? src.length : i + 2; blank(start, i); continue; }
      if (c === "\x27" || c === "\"" || c === "`") {
        for (i++; i < src.length && src[i] !== c; i++) if (src[i] === "\\") i++;
        i++; blank(start + 1, i - 1); continue;
      }
      if (c === "/" && regexBefore.test(code.slice(Math.max(0, i - 200), i).join("").trimEnd())) {
        for (i++; i < src.length && src[i] !== "/" && src[i] !== "\n"; i++) {
          if (src[i] === "\\") i++;
          else if (src[i] === "[") { while (i < src.length && src[i] !== "]") { if (src[i] === "\\") i++; i++; } }
        }
        i++; blank(start + 1, i - 1); continue;
      }
      i++;
    }
    const text = code.join("");
    const out = text.split("");
    const lineOf = at => text.slice(0, at).split("\n").length;
    const matchBrace = at => {
      let depth = 0;
      for (let k = at; k < text.length; k++) {
        if (text[k] === "{") depth++;
        else if (text[k] === "}" && --depth === 0) return k;
      }
      return text.length - 1;
    };
    const wipe = (from, to) => { for (let k = from; k <= to; k++) if (out[k] !== "\n") out[k] = " "; };
    // Class bodies hold the methods; interfaces and type aliases hold only types.
    for (const m of text.matchAll(/\b(class|interface)\b[^{;]*\{/g)) {
      const open = m.index + m[0].length - 1;
      if (out[open] === "{") wipe(open, matchBrace(open));
    }
    for (const m of text.matchAll(/(^|[\s;}])(?:export\s+)?(?:declare\s+)?type\s+[A-Za-z_$][\w$]*(?=\s*[<=])/g)) {
      let depth = 0, k = m.index + m[0].length;
      for (; k < text.length; k++) {
        const c = text[k];
        if ("([{<".includes(c)) depth++;
        else if (")]}".includes(c) || (c === ">" && text[k - 1] !== "=")) depth--;
        else if (c === ";" && depth <= 0) break;
      }
      wipe(m.index + m[0].length, k);
    }
    const rest = out.join("");
    for (const m of rest.matchAll(/=>|\bfunction\b/g)) console.log(`${lineOf(m.index)}:${m[0] === "=>" ? "arrow" : "function"}`);
    const method = /[{,]\s*(?:async\s+|get\s+|set\s+|\*\s*)?(?:[A-Za-z_$][\w$]*|\[[^\]]*\])\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?::[^{;]*)?\{/g;
    for (const m of rest.matchAll(method)) console.log(`${lineOf(m.index + m[0].search(/[^\s{,]/))}:method`);
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
