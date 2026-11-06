#!/usr/bin/env bash
set -euo pipefail

# Under lib/ (minus test_helper.dart) a throw raises only UnwrapError (explicit
# unwrap misuse) or FormatException (malformed wire input to fromSerial).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_result"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib" | grep -E '\.dart$' | grep -vx "${pkg}/lib/test_helper.dart" || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no Dart sources under ${pkg}/lib" >&2 && exit 1; }

scanner="$(mktemp -d)/throws.dart"
cat >"${scanner}" <<'DART'
import 'dart:convert';
import 'dart:io';

late String src;
var strings = <String?>[];
var i = 0;
String at(int k) => k >= 0 && k < src.length ? src[k] : '';
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
    if (!raw && src[i] == r'\') { s.write(at(i + 1)); i += 2; continue; }
    if (!raw && src[i] == r'$' && at(i + 1) == '{') { dyn = true; i += 2; code.write(' (${lex(true)}) '); continue; }
    if (!raw && src[i] == r'$' && has(r'[A-Za-z_]', at(i + 1))) { dyn = true; var j = i + 1; while (has(r'\w', at(j))) j++; code.write(' (${src.substring(i + 1, j)}) '); i = j; continue; }
    s.write(src[i++]);
  }
  i += q.length;
  strings.add(dyn ? null : s.toString());
  return ' "S${strings.length - 1}" $code';
}

void main() async {
  src = await stdin.transform(const Utf8Decoder(allowMalformed: true)).join();
  final code = lex(false);
  final t = RegExp(r'"S\d+"|[A-Za-z_$][\w$]*|\S').allMatches(code).map((m) => m[0]!).toList();
  for (var k = 0; k < t.length; k++) {
    if (t[k] == 'rethrow' || t[k] == 'throwWithStackTrace') print('bad uses ${t[k]}');
    if (t[k] != 'throw' || (k > 0 && t[k - 1] == '.')) continue;
    final type = t[k + 1] == 'const' || t[k + 1] == 'new' ? t[k + 2] : t[k + 1];
    final call = t[k + (t[k + 1] == type ? 2 : 3)];
    print(call == '(' && (type == 'UnwrapError' || type == 'FormatException') ? 'ok $type' : 'bad throws ${type.startsWith('"S') ? 'a string' : type}${call == '(' ? '' : ' (not a constructor call)'}');
  }
}
DART

failed=0
unwraps=0
formats=0
for path in "${files[@]}"; do
  report="$(git show "${tree}:${path}" | dart "${scanner}")"
  unwraps=$((unwraps + $(grep -c '^ok UnwrapError$' <<<"${report}" || true)))
  formats=$((formats + $(grep -c '^ok FormatException$' <<<"${report}" || true)))
  while read -r line; do
    [[ -n ${line} ]] && echo "❌ ${path} ${line#bad }; only UnwrapError and FormatException may be thrown" >&2 && failed=1
  done <<<"$(grep '^bad ' <<<"${report}" | sort -u || true)"
done
[[ ${unwraps} -gt 0 ]] || { echo "❌ control: no throw UnwrapError found in ${pkg}/lib" >&2 && failed=1; }

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ throw-confinement: ${#files[@]} lib files throw only UnwrapError (${unwraps}) and FormatException (${formats})"
