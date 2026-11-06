#!/usr/bin/env bash
set -euo pipefail

# The generic catalog is exactly the six-entry baseline: validation_error,
# entity_not_found, conflict, unauthenticated, unauthorized, invalid_json.
# Read from source (no build): the generic catalog source is the one src/
# module whose `id:` literals include validation_error; its `id:` literals
# must be exactly the six, each once. Quote style, key quoting and line breaks
# do not matter; comments are ignored.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
want="conflict entity_not_found invalid_json unauthenticated unauthorized validation_error"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }

failed=0
sources=()
declare -A ids_of=()
for path in "${files[@]}"; do
  # Prints every literal value bound to an `id` key, one per line, in source order.
  # shellcheck disable=SC2016
  ids="$(git show "${tree}:${path}" | bun -e '
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
        let s = "", dynamic = false;
        for (i++; i < src.length && src[i] !== "`"; i++) {
          if (src[i] === "\\") { s += src[++i]; continue; }
          if (src[i] === "$" && src[i + 1] === "{") { dynamic = true; let depth = 0; for (i++; i < src.length; i++) { if (src[i] === "{") depth++; if (src[i] === "}" && --depth === 0) break; } continue; }
          s += src[i];
        }
        i++;
        if (dynamic) out += " T "; else put(s);
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
    const key = /(?:(?<![\w$.])id|"S(\d+)")\s*:\s*"S(\d+)"/g;
    for (const m of out.matchAll(key)) if (m[1] === undefined || strings[+m[1]] === "id") console.log(strings[+m[2]]);
  ')"
  if grep -qx validation_error <<<"${ids}"; then
    sources+=("${path}")
    ids_of["${path}"]="${ids}"
  fi
done

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "❌ no src/ module declares id validation_error; the generic catalog source is missing" >&2
  exit 1
fi
if [[ ${#sources[@]} -gt 1 ]]; then
  for path in "${sources[@]}"; do echo "❌ ${path} declares id validation_error; the generic catalog must have one source" >&2; done
  exit 1
fi

catalog="${sources[0]}"
ids="${ids_of[${catalog}]}"
while read -r dup; do
  [[ -n ${dup} ]] && echo "❌ ${catalog}: duplicate id ${dup}" >&2 && failed=1
done <<<"$(sort <<<"${ids}" | uniq -d)"
have="$(sort -u <<<"${ids}" | tr '\n' ' ' | sed 's/ $//')"
for id in ${want}; do
  [[ " ${have} " == *" ${id} "* ]] || { echo "❌ ${catalog}: missing id ${id}" >&2 && failed=1; }
done
for id in ${have}; do
  [[ " ${want} " == *" ${id} "* ]] || { echo "❌ ${catalog}: extra id ${id}" >&2 && failed=1; }
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ generic-catalog: ${catalog} declares exactly the six generic ids (${want})"
