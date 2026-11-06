#!/usr/bin/env bash
set -euo pipefail

# src/ (TestHelper included) is stateless OOP + DI, so no module declares a top-level
# function or binds a function to a top-level const/let/var.

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
    const close = { "(": ")", "[": "]", "{": "}", "<": ">" };
    const skipBalanced = at => {
      const open = text[at], end = close[open];
      let depth = 0;
      for (let k = at; k < text.length; k++) {
        if (text[k] === open) depth++;
        else if (text[k] === end && --depth === 0) return k + 1;
      }
      return -1;
    };
    const lineOf = at => text.slice(0, at).split("\n").length;
    const declared = /(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:async\s+)?function\b\s*\*?\s*([A-Za-z_$][\w$]*)?/y;
    const binding = /(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::(?:[^=;]|=>)*?)?=(?!>)\s*/y;
    const isFunction = at => {
      const rest = text.slice(at);
      const head = /^(?:async\s+)?/.exec(rest)[0].length;
      let k = at + head;
      if (/^function\b/.test(text.slice(k)) || /^[A-Za-z_$][\w$]*\s*=>/.test(text.slice(k))) return true;
      if (text[k] === "<") { k = skipBalanced(k); if (k < 0) return false; }
      if (text[k] !== "(") return false;
      k = skipBalanced(k);
      return k >= 0 && /^\s*(?::[^;]*?)?=>/.test(text.slice(k));
    };
    let depth = 0;
    for (let k = 0; k < text.length; k++) {
      const c = text[k];
      if (c === "(" || c === "[" || c === "{") { depth++; continue; }
      if (c === ")" || c === "]" || c === "}") { depth--; continue; }
      if (depth !== 0 || !/[A-Za-z_$]/.test(c) || /[\w$.]/.test(text[k - 1] ?? "")) continue;
      declared.lastIndex = k;
      let m = declared.exec(text);
      if (m && !/=\s*(?:async\s+)?$/.test(text.slice(Math.max(0, k - 200), k))) { console.log(`${lineOf(k)}:${m[1] ?? "default"}`); k = declared.lastIndex - 1; continue; }
      binding.lastIndex = k;
      m = binding.exec(text);
      if (m) { if (isFunction(binding.lastIndex)) console.log(`${lineOf(k)}:${m[1]}`); k = binding.lastIndex - 1; continue; }
      while (/[\w$]/.test(text[k + 1] ?? "")) k++;
    }
  ')"
  if [[ -n ${report} ]]; then
    while IFS=: read -r line name; do echo "❌ ${path}:${line}: free function ${name}" >&2; done <<<"${report}"
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ stateless-oop: ${#files[@]} src/ modules declare no top-level function or function-valued binding"
