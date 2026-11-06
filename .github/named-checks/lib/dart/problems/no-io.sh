#!/usr/bin/env bash
set -euo pipefail

# A pure-value package: lib/ imports only dart:core/convert/collection/math/
# typed_data, relative paths and the package itself (no dart:io, dart:html,
# dart:ffi, http or process packages, no conditional imports), and calls no
# console or process effect.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_problems"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib" | grep -E '\.dart$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no Dart sources under ${pkg}/lib" >&2 && exit 1; }

failed=0
directives=0
for path in "${files[@]}"; do
  # Prints "uri <u>" per directive, then "bad <reason>" per violation.
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | bun -e '
    const src = await Bun.stdin.text();
    const strings = [];
    let i = 0;
    const lex = inner => {
      let out = "", depth = 0;
      while (i < src.length) {
        const c = src[i], n = src[i + 1];
        if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
        if (c === "/" && n === "*") { let d = 0; do { if (src.startsWith("/*", i)) { d++; i += 2; } else if (src.startsWith("*/", i)) { d--; i += 2; } else i++; } while (d > 0 && i < src.length); out += " "; continue; }
        if (inner && c === "{") depth++;
        if (inner && c === "}" && depth-- === 0) { i++; return out; }
        const raw = (c === "r" || c === "R") && (n === "\x27" || n === "\"") && !/[\w$]/.test(src[i - 1] ?? "");
        if (c === "\x27" || c === "\"" || raw) { if (raw) i++; out += str(raw); continue; }
        out += c; i++;
      }
      return out;
    };
    const str = raw => {
      const q = src.startsWith(src[i].repeat(3), i) ? src[i].repeat(3) : src[i];
      let s = "", code = "", dynamic = false;
      for (i += q.length; i < src.length && !src.startsWith(q, i); ) {
        if (!raw && src[i] === "\\") { s += src[i + 1]; i += 2; continue; }
        if (!raw && src[i] === "$" && src[i + 1] === "{") { dynamic = true; i += 2; code += ` (${lex(true)}) `; continue; }
        if (!raw && src[i] === "$" && /[A-Za-z_]/.test(src[i + 1])) { dynamic = true; let j = i + 1; while (/\w/.test(src[j] ?? "")) j++; code += ` (${src.slice(i + 1, j)}) `; i = j; continue; }
        s += src[i++];
      }
      i += q.length;
      strings.push(dynamic ? null : s);
      return ` "S${strings.length - 1}" ${code}`;
    };
    const out = lex(false);
    const allowed = /^(dart:(core|convert|collection|math|typed_data)|package:diene_problems\/.+|(?![a-z]+:)[^:]+)$/;
    for (const m of out.matchAll(/(?<![\w$.])(import|export|part)\s+(?:of\s+)?"S(\d+)"/g)) {
      const uri = strings[+m[2]];
      console.log(`uri ${uri}`);
      if (uri === null || !allowed.test(uri)) console.log(`bad ${m[1]}s ${uri ?? "an interpolated uri"}`);
    }
    if (/(?<![\w$])dart\s*\.\s*library\s*\./.test(out)) console.log("bad has a conditional import (dart.library.*)");
    for (const m of out.matchAll(/(?<![\w$.])(print|stdout|stderr|stdin|exit|Process|File|Directory|HttpClient|Socket|Platform)(?![\w$])(?!\s*:)/g))
      console.log(`bad names the effect ${m[1]}`);
  ')"
  directives=$((directives + $(grep -c '^uri ' <<<"${report}" || true)))
  while read -r line; do
    [[ -n ${line} ]] && echo "❌ ${path} ${line#bad }" >&2 && failed=1
  done <<<"$(grep '^bad ' <<<"${report}" | sort -u || true)"
done
[[ ${directives} -gt 0 ]] || { echo "❌ control: no directive found in ${pkg}/lib" >&2 && failed=1; }

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ no-io: ${#files[@]} lib files, ${directives} directives use only pure dart: libraries, relative paths and diene_problems; no console or process effect"
