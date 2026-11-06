#!/usr/bin/env bash
set -euo pipefail

# The type URI `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
# is assembled in ONE shipped Dart file (lib/, example/): only it has a string
# (adjacent literals joined) with a `docs` segment, and that string interpolates
# every segment. A whole constant URI is data, not a formatter. The retired
# conflict id appears nowhere.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_problems"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib" "${pkg}/example" | grep -E '\.dart$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no Dart sources under ${pkg}/lib or ${pkg}/example" >&2 && exit 1; }

failed=0
builders=()
for path in "${files[@]}"; do
  # Prints "DOCS" when a string (adjacent literals joined) builds a URI with a
  # `docs` path segment, then "SEG <name>" for each segment its interpolations name.
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | bun -e '
    const src = await Bun.stdin.text();
    const runs = [];
    let i = 0;
    const lex = inner => {
      let out = "", depth = 0, after = -1;
      while (i < src.length) {
        const c = src[i], n = src[i + 1];
        if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
        if (c === "/" && n === "*") { let d = 0; do { if (src.startsWith("/*", i)) { d++; i += 2; } else if (src.startsWith("*/", i)) { d--; i += 2; } else i++; } while (d > 0 && i < src.length); out += " "; continue; }
        if (inner && c === "{") depth++;
        if (inner && c === "}" && depth-- === 0) { i++; return out; }
        const raw = (c === "r" || c === "R") && (n === "\x27" || n === "\"") && !/[\w$]/.test(src[i - 1] ?? "");
        if (c === "\x27" || c === "\"" || raw) {
          const adjacent = after >= 0 && /^\s*$/.test(src.slice(after, i));
          if (raw) i++;
          const run = adjacent ? runs[runs.length - 1] : { pieces: [], code: "" };
          if (!adjacent) runs.push(run);
          str(raw, run);
          after = i; out += " S "; continue;
        }
        out += c; i++;
      }
      return out;
    };
    const str = (raw, run) => {
      const q = src.startsWith(src[i].repeat(3), i) ? src[i].repeat(3) : src[i];
      let s = "";
      const put = () => { run.pieces.push(s); s = ""; };
      for (i += q.length; i < src.length && !src.startsWith(q, i); ) {
        if (!raw && src[i] === "\\") { s += src[i + 1]; i += 2; continue; }
        if (!raw && src[i] === "$" && src[i + 1] === "{") { put(); i += 2; run.code += ` (${lex(true)}) `; continue; }
        if (!raw && src[i] === "$" && /[A-Za-z_]/.test(src[i + 1])) { put(); let j = i + 1; while (/\w/.test(src[j] ?? "")) j++; run.code += ` (${src.slice(i + 1, j)}) `; i = j; continue; }
        s += src[i++];
      }
      i += q.length; put();
    };
    lex(false);
    const constant = /^[a-z][a-z0-9+.-]*:\/\/[^/\s]+\/docs\//;
    const builds = runs.filter(r => r.pieces.some(p => /(^|\/)docs(\/|$)/.test(p)) && (r.code !== "" || !constant.test(r.pieces.join(""))));
    if (builds.length > 0) console.log("DOCS");
    const code = builds.map(r => r.code).join(" ");
    for (const seg of ["scheme", "host", "landscape", "platform", "service", "module", "version", "id"])
      if (new RegExp(`(?<![\\w$])${seg}(?![\\w$])`).test(code)) console.log(`SEG ${seg}`);
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
  echo "❌ no shipped Dart file assembles the type-URI template (no docs path segment in any literal)" >&2
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
