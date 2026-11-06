#!/usr/bin/env bash
set -euo pipefail

# The problem type URI `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
# is assembled in exactly ONE src/ module (the URI builder): only that module
# carries a `docs` path segment in a string or template literal, and it names
# every segment. The conflict problem's id is `conflict`; the longer retired
# spelling appears nowhere in the tree.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }

failed=0
builders=()
for path in "${files[@]}"; do
  # Prints "DOCS" when a string/template piece holds a `docs` path segment,
  # then "SEG <name>" for each URI segment the code (strings blanked) names.
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | bun -e '
    const src = await Bun.stdin.text();
    const strings = [];
    let out = "", i = 0;
    const regexBefore = /[(,=:[!&|?{};+\-*%<>~^]$|\b(return|typeof|case|do|else|in|of|void|yield|await)$/;
    const put = s => { strings.push(s); out += ` "S${strings.length - 1}" `; };
    while (i < src.length) {
      const c = src[i], n = src[i + 1];
      if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
      if (c === "/" && n === "*") { i = src.indexOf("*/", i + 2); i = i < 0 ? src.length : i + 2; continue; }
      if (c === "\x27" || c === "\"") {
        let s = "";
        for (i++; i < src.length && src[i] !== c; i++) s += src[i] === "\\" ? src[++i] : src[i];
        i++; put(s); continue;
      }
      if (c === "`") {
        let s = "";
        for (i++; i < src.length && src[i] !== "`"; i++) {
          if (src[i] === "\\") { s += src[++i]; continue; }
          if (src[i] === "$" && src[i + 1] === "{") {
            put(s); s = "";
            let depth = 0;
            for (i++; i < src.length; i++) { if (src[i] === "{") depth++; if (src[i] === "}" && --depth === 0) break; if (depth > 0 && !(depth === 1 && src[i] === "{")) out += src[i]; }
            continue;
          }
          s += src[i];
        }
        i++; put(s); continue;
      }
      if (c === "/" && regexBefore.test(out.trimEnd())) {
        for (i++; i < src.length && src[i] !== "/"; i++) { if (src[i] === "\\") i++; else if (src[i] === "[") { while (i < src.length && src[i] !== "]") { if (src[i] === "\\") i++; i++; } } }
        for (i++; /[a-z]/.test(src[i] ?? ""); i++);
        out += " R ";
        continue;
      }
      out += c; i++;
    }
    if (strings.some(s => /(^|\/)docs(\/|$)/.test(s))) console.log("DOCS");
    for (const seg of ["scheme", "host", "landscape", "platform", "service", "module", "version", "id"])
      if (new RegExp(`(?<![\\w$])${seg}(?![\\w$])`).test(out)) console.log(`SEG ${seg}`);
  ')"
  if grep -qx DOCS <<<"${report}"; then
    builders+=("${path}")
    for seg in scheme host landscape platform service module version id; do
      grep -qx "SEG ${seg}" <<<"${report}" || {
        echo "❌ ${path}: assembles the type-URI template but never names the ${seg} segment" >&2
        failed=1
      }
    done
  fi
done

if [[ ${#builders[@]} -eq 0 ]]; then
  echo "❌ no src/ module assembles the type-URI template (no docs path segment in any literal)" >&2
  failed=1
elif [[ ${#builders[@]} -gt 1 ]]; then
  for path in "${builders[@]}"; do echo "❌ ${path} formats the type-URI template; it must live in one URI builder only" >&2; done
  failed=1
fi

retired="entity""_conflict"
hits="$(git grep --cached -l -F "${retired}" -- . || true)"
if [[ -n ${hits} ]]; then
  while read -r hit; do echo "❌ ${hit}: ${retired} appears; the conflict problem's id is conflict" >&2; done <<<"${hits}"
  failed=1
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ uri-single-source: the type-URI template is assembled only in ${builders[0]}, which names every segment; ${retired} appears nowhere"
