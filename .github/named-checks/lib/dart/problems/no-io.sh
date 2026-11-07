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

# Reads a Dart source on stdin; prints "uri <u>" per directive, then
# "bad <reason>" per violation.
parser="$(mktemp -d)/parse.dart"
cat >"${parser}" <<'DART'
import 'dart:convert';
import 'dart:io';

late String src;
final strings = <String?>[];
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
  final s = StringBuffer(), code = StringBuffer();
  var dyn = false;
  for (i += q.length; i < src.length && !src.startsWith(q, i); ) {
    if (!raw && src[i] == r'\') { s.write(js(i + 1)); i += 2; continue; }
    if (!raw && src[i] == r'$' && at(i + 1) == '{') { dyn = true; i += 2; code.write(' (${lex(true)}) '); continue; }
    if (!raw && src[i] == r'$' && has(r'[A-Za-z_]', js(i + 1))) { dyn = true; var j = i + 1; while (has(r'\w', at(j))) j++; code.write(' (${src.substring(i + 1, j)}) '); i = j; continue; }
    s.write(src[i++]);
  }
  i += q.length;
  strings.add(dyn ? null : s.toString());
  return ' "S${strings.length - 1}" $code';
}

void main() async {
  src = await stdin.transform(const Utf8Decoder(allowMalformed: true)).join();
  if (src.startsWith('﻿')) src = src.substring(1);
  final out = lex(false);
  final allowed = RegExp(r'^(dart:(core|convert|collection|math|typed_data)|package:diene_problems\/.+|(?![a-z]+:)[^:]+)$');
  for (final m in RegExp(r'(?<![\w$.])(import|export|part)\s+(?:of\s+)?"S(\d+)"').allMatches(out)) {
    final uri = strings[int.parse(m[2]!)];
    print('uri $uri');
    if (uri == null || !allowed.hasMatch(uri)) print('bad ${m[1]}s ${uri ?? 'an interpolated uri'}');
  }
  if (RegExp(r'(?<![\w$])dart\s*\.\s*library\s*\.').hasMatch(out)) print('bad has a conditional import (dart.library.*)');
  for (final m in RegExp(r'(?<![\w$.])(print|stdout|stderr|stdin|exit|Process|File|Directory|HttpClient|Socket|Platform)(?![\w$])(?!\s*:)').allMatches(out)) {
    print('bad names the effect ${m[1]}');
  }
}
DART

failed=0
directives=0
for path in "${files[@]}"; do
  report="$(git show "${tree}:${path}" | dart "${parser}")"
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
