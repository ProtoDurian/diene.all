#!/usr/bin/env bash
set -euo pipefail

# The generic catalog (lib-contracts §2.2) is the one lib/ file whose `id:`
# literals include validation_error. Its `id:` literals are exactly the six
# baseline ids, each once, each with the table's status and recoverable flag;
# entity_not_found and conflict carry `{entityType, id}` data (OD-19).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_problems"
want="conflict:409:true entity_not_found:404:false invalid_json:400:true unauthenticated:401:true unauthorized:403:false validation_error:400:true"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib" | grep -E '\.dart$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no Dart sources under ${pkg}/lib" >&2 && exit 1; }

failed=0
sources=()
declare -A rows_of=()
for path in "${files[@]}"; do
  # Prints "<id> <status|-> <recoverable|-> <keyed|->" for every literal `id:` binding.
  # shellcheck disable=SC2016
  rows="$(git show "${tree}:${path}" | bun -e '
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
      let s = "", dynamic = false;
      for (i += q.length; i < src.length && !src.startsWith(q, i); ) {
        if (!raw && src[i] === "\\") { s += src[i + 1]; i += 2; continue; }
        if (!raw && src[i] === "$" && /[{A-Za-z_]/.test(src[i + 1])) { dynamic = true; if (src[i + 1] === "{") { i += 2; lex(true); } else { i++; while (/\w/.test(src[i] ?? "")) i++; } continue; }
        s += src[i++];
      }
      i += q.length;
      if (dynamic) return " T ";
      strings.push(s);
      return ` "S${strings.length - 1}" `;
    };
    const out = lex(false);
    const enclosing = at => {
      let d = 0, a = at;
      for (; a >= 0; a--) { const c = out[a]; if (")]}".includes(c)) d++; else if ("([{".includes(c) && d-- === 0) break; }
      let b = a + 1;
      for (d = 0; b < out.length; b++) { const c = out[b]; if ("([{".includes(c)) d++; else if (")]}".includes(c) && d-- === 0) break; }
      return a < 0 ? out : out.slice(a + 1, b);
    };
    const flat = g => { let d = 0, r = ""; for (const c of g) { if ("([{".includes(c)) d++; if (d === 0) r += c; if (")]}".includes(c)) d--; } return r; };
    const key = (k, v) => new RegExp(`(?:(?<![\\w$.])${k}|"S(\\d+)")\\s*:\\s*(${v})`, "g");
    const field = (g, k, v) => { for (const m of flat(g).matchAll(key(k, v))) if (m[1] === undefined || strings[+m[1]] === k) return m[2]; return "-"; };
    const groupFrom = p => { let d = 0, b = p; for (; b < out.length; b++) { if ("([{".includes(out[b])) d++; else if (")]}".includes(out[b]) && --d === 0) break; } return out.slice(p + 1, b); };
    const named = g => [...g.matchAll(/"S(\d+)"/g)].map(x => strings[+x[1]]);
    // an omitted recoverable takes the constructor default
    const fallback = out.match(/this\s*\.\s*recoverable\s*=\s*(true|false)/)?.[1] ?? "-";
    for (const m of out.matchAll(key("id", "\"S\\d+\""))) {
      if (m[1] !== undefined && strings[+m[1]] !== "id") continue;
      const g = enclosing(m.index);
      const names = new Set(named(g).filter(s => !named(flat(g)).includes(s)));
      // a schema passed by const name is read from that declaration in this file
      for (const r of flat(g).matchAll(/:\s*([A-Za-z_$][\w$]*)\s*(?=[,)}\]]|$)/g)) {
        const d = out.match(new RegExp(`(?<![\\w$.])${r[1].replace("$", "\\$")}\\s*=(?!=)`));
        const at = d ? out.slice(d.index + d[0].length).search(/[({[]/) : -1;
        if (at >= 0) for (const s of named(groupFrom(d.index + d[0].length + at))) names.add(s);
      }
      const keyed = names.has("entityType") && names.has("id") ? "keyed" : "-";
      const recoverable = field(g, "recoverable", "true|false");
      console.log([strings[+m[2].slice(2, -1)], field(g, "status", "\\d+"), recoverable === "-" ? fallback : recoverable, keyed].join(" "));
    }
  ')"
  if grep -q '^validation_error ' <<<"${rows}"; then
    sources+=("${path}")
    rows_of["${path}"]="${rows}"
  fi
done

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "❌ no ${pkg}/lib file declares id validation_error; the generic catalog source is missing" >&2
  exit 1
fi
if [[ ${#sources[@]} -gt 1 ]]; then
  for path in "${sources[@]}"; do echo "❌ ${path} declares id validation_error; the generic catalog must have one source" >&2; done
  exit 1
fi

catalog="${sources[0]}"
rows="${rows_of[${catalog}]}"
while read -r dup; do
  [[ -n ${dup} ]] && echo "❌ ${catalog}: duplicate id ${dup}" >&2 && failed=1
done <<<"$(cut -d' ' -f1 <<<"${rows}" | sort | uniq -d)"
for entry in ${want}; do
  IFS=: read -r id status recoverable <<<"${entry}"
  row="$(awk -v id="${id}" '$1 == id' <<<"${rows}" | head -1)"
  if [[ -z ${row} ]]; then
    echo "❌ ${catalog}: missing id ${id}" >&2 && failed=1 && continue
  fi
  read -r _ got_status got_recoverable keyed <<<"${row}"
  [[ ${got_status} == "${status}" ]] || { echo "❌ ${catalog}: ${id} status is ${got_status}, want ${status}" >&2 && failed=1; }
  [[ ${got_recoverable} == "${recoverable}" ]] || { echo "❌ ${catalog}: ${id} recoverable is ${got_recoverable}, want ${recoverable}" >&2 && failed=1; }
  if [[ ${id} == conflict || ${id} == entity_not_found ]] && [[ ${keyed} != keyed ]]; then
    echo "❌ ${catalog}: ${id} data schema does not name both entityType and id" >&2 && failed=1
  fi
done
while read -r id; do
  [[ " ${want} " == *" ${id}:"* ]] || { echo "❌ ${catalog}: extra id ${id}" >&2 && failed=1; }
done <<<"$(cut -d' ' -f1 <<<"${rows}" | sort -u)"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ generic-catalog: ${catalog} declares exactly the six generic ids with their status and recoverable flags; conflict and entity_not_found carry {entityType, id}"
