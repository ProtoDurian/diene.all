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

# Reads a Dart source on stdin; prints "<id> <status|-> <recoverable|-> <keyed|->"
# for every literal `id:` binding.
parser="$(mktemp -d)/parse.dart"
cat >"${parser}" <<'DART'
import 'dart:convert';
import 'dart:io';

late String src;
final strings = <String>[];
var i = 0;
String at(int k) => k >= 0 && k < src.length ? src[k] : '';
String js(int k) => k < src.length ? src[k] : 'undefined';
bool has(String p, String s) => RegExp(p).hasMatch(s);

String lex(bool inner) {
  final out = StringBuffer();
  var depth = 0;
  while (i < src.length) {
    final c = src[i], n = at(i + 1);
    if (c == '/' && n == '/') { while (i < src.length && src[i] != '\n') i++; continue; }
    if (c == '/' && n == '*') { var d = 0; do { if (src.startsWith('/*', i)) { d++; i += 2; } else if (src.startsWith('*/', i)) { d--; i += 2; } else i++; } while (d > 0 && i < src.length); out.write(' '); continue; }
    if (inner && c == '{') depth++;
    if (inner && c == '}' && depth-- == 0) { i++; return out.toString(); }
    final raw = (c == 'r' || c == 'R') && (n == "'" || n == '"') && !has(r'[\w$]', at(i - 1));
    if (c == "'" || c == '"' || raw) { if (raw) i++; out.write(str(raw)); continue; }
    out.write(c); i++;
  }
  return out.toString();
}

String str(bool raw) {
  final q = src.startsWith(src[i] * 3, i) ? src[i] * 3 : src[i];
  final s = StringBuffer();
  var dyn = false;
  for (i += q.length; i < src.length && !src.startsWith(q, i); ) {
    if (!raw && src[i] == r'\') { s.write(js(i + 1)); i += 2; continue; }
    if (!raw && src[i] == r'$' && has(r'[{A-Za-z_]', js(i + 1))) { dyn = true; if (at(i + 1) == '{') { i += 2; lex(true); } else { i++; while (has(r'\w', at(i))) i++; } continue; }
    s.write(src[i++]);
  }
  i += q.length;
  if (dyn) return ' T ';
  strings.add(s.toString());
  return ' "S${strings.length - 1}" ';
}

void main() async {
  src = await stdin.transform(const Utf8Decoder(allowMalformed: true)).join();
  if (src.startsWith('﻿')) src = src.substring(1);
  final out = lex(false);
  bool open(String c) => '([{'.contains(c);
  bool close(String c) => ')]}'.contains(c);
  String enclosing(int p) {
    var d = 0, a = p;
    for (; a >= 0; a--) { final c = out[a]; if (close(c)) d++; else if (open(c) && d-- == 0) break; }
    var b = a + 1;
    for (d = 0; b < out.length; b++) { final c = out[b]; if (open(c)) d++; else if (close(c) && d-- == 0) break; }
    return a < 0 ? out : out.substring(a + 1, b);
  }
  String flat(String g) { var d = 0; final r = StringBuffer(); for (var k = 0; k < g.length; k++) { final c = g[k]; if (open(c)) d++; if (d == 0) r.write(c); if (close(c)) d--; } return r.toString(); }
  RegExp key(String k, String v) => RegExp('(?:(?<![\\w\$.])$k|"S(\\d+)")\\s*:\\s*($v)');
  String field(String g, String k, String v) { for (final m in key(k, v).allMatches(flat(g))) { if (m[1] == null || strings[int.parse(m[1]!)] == k) return m[2]!; } return '-'; }
  String groupFrom(int p) { var d = 0, b = p; for (; b < out.length; b++) { if (open(out[b])) d++; else if (close(out[b]) && --d == 0) break; } return out.substring(p + 1, b); }
  List<String> named(String g) => [for (final x in RegExp(r'"S(\d+)"').allMatches(g)) strings[int.parse(x[1]!)]];
  // an omitted recoverable takes the constructor default
  final fallback = RegExp(r'this\s*\.\s*recoverable\s*=\s*(true|false)').firstMatch(out)?[1] ?? '-';
  for (final m in key('id', r'"S\d+"').allMatches(out)) {
    if (m[1] != null && strings[int.parse(m[1]!)] != 'id') continue;
    final g = enclosing(m.start);
    final inner = named(flat(g));
    final names = named(g).where((s) => !inner.contains(s)).toSet();
    // a schema passed by const name is read from that declaration in this file
    for (final r in RegExp(r':\s*([A-Za-z_$][\w$]*)\s*(?=[,)}\]]|$)').allMatches(flat(g))) {
      final d = RegExp('(?<![\\w\$.])${r[1]!.replaceFirst(r'$', r'\$')}\\s*=(?!=)').firstMatch(out);
      final pos = d != null ? out.substring(d.end).indexOf(RegExp(r'[({[]')) : -1;
      if (pos >= 0) names.addAll(named(groupFrom(d!.end + pos)));
    }
    final keyed = names.contains('entityType') && names.contains('id') ? 'keyed' : '-';
    final recoverable = field(g, 'recoverable', 'true|false');
    print([strings[int.parse(m[2]!.substring(2, m[2]!.length - 1))], field(g, 'status', r'\d+'), recoverable == '-' ? fallback : recoverable, keyed].join(' '));
  }
}
DART

failed=0
sources=()
declare -A rows_of=()
for path in "${files[@]}"; do
  rows="$(git show "${tree}:${path}" | dart "${parser}")"
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
