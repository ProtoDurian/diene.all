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

# Reads a Dart source on stdin; prints "DOCS" when a string (adjacent literals
# joined) builds a URI with a `docs` path segment, then "SEG <name>" for each
# segment its interpolations name.
parser="$(mktemp -d)/parse.dart"
cat >"${parser}" <<'DART'
import 'dart:convert';
import 'dart:io';

class Run { final pieces = <String>[]; var code = ''; }

late String src;
final runs = <Run>[];
var i = 0;
String at(int k) => k >= 0 && k < src.length ? src[k] : '';
String js(int k) => k < src.length ? src[k] : 'undefined';
bool has(String p, String s) => RegExp(p).hasMatch(s);

String lex(bool inner) {
  final out = StringBuffer();
  var depth = 0, after = -1;
  while (i < src.length) {
    final c = src[i], n = at(i + 1);
    if (c == '/' && n == '/') { while (i < src.length && src[i] != '\n') i++; continue; }
    if (c == '/' && n == '*') { var d = 0; do { if (src.startsWith('/*', i)) { d++; i += 2; } else if (src.startsWith('*/', i)) { d--; i += 2; } else i++; } while (d > 0 && i < src.length); out.write(' '); continue; }
    if (inner && c == '{') depth++;
    if (inner && c == '}' && depth-- == 0) { i++; return out.toString(); }
    final raw = (c == 'r' || c == 'R') && (n == "'" || n == '"') && !has(r'[\w$]', at(i - 1));
    if (c == "'" || c == '"' || raw) {
      final adjacent = after >= 0 && has(r'^\s*$', src.substring(after, i));
      if (raw) i++;
      final run = adjacent ? runs.last : Run();
      if (!adjacent) runs.add(run);
      str(raw, run);
      after = i; out.write(' S '); continue;
    }
    out.write(c); i++;
  }
  return out.toString();
}

void str(bool raw, Run run) {
  final q = src.startsWith(src[i] * 3, i) ? src[i] * 3 : src[i];
  final s = StringBuffer();
  void put() { run.pieces.add(s.toString()); s.clear(); }
  for (i += q.length; i < src.length && !src.startsWith(q, i); ) {
    if (!raw && src[i] == r'\') { s.write(js(i + 1)); i += 2; continue; }
    if (!raw && src[i] == r'$' && at(i + 1) == '{') { put(); i += 2; run.code += ' (${lex(true)}) '; continue; }
    if (!raw && src[i] == r'$' && has(r'[A-Za-z_]', js(i + 1))) { put(); var j = i + 1; while (has(r'\w', at(j))) j++; run.code += ' (${src.substring(i + 1, j)}) '; i = j; continue; }
    s.write(src[i++]);
  }
  i += q.length; put();
}

void main() async {
  src = await stdin.transform(const Utf8Decoder(allowMalformed: true)).join();
  if (src.startsWith('﻿')) src = src.substring(1);
  lex(false);
  final constant = RegExp(r'^[a-z][a-z0-9+.-]*:\/\/[^/\s]+\/docs\/');
  final builds = runs.where((r) => r.pieces.any((p) => has(r'(^|\/)docs(\/|$)', p)) && (r.code != '' || !constant.hasMatch(r.pieces.join()))).toList();
  if (builds.isNotEmpty) print('DOCS');
  final code = builds.map((r) => r.code).join(' ');
  for (final seg in ['scheme', 'host', 'landscape', 'platform', 'service', 'module', 'version', 'id']) {
    if (has('(?<![\\w\$])$seg(?![\\w\$])', code)) print('SEG $seg');
  }
}
DART

failed=0
builders=()
for path in "${files[@]}"; do
  report="$(git show "${tree}:${path}" | dart "${parser}")"
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
