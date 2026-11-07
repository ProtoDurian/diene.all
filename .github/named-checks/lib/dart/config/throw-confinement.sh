#!/usr/bin/env bash
set -euo pipefail

# lib/ returns Result for expected failures. Allowed throws, as published in
# 1.0.0: programmer misuse (app_config, schema, config_problem) and the helper's
# plain-throw assertions. Each file's throws must match its list exactly.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_config"
declare -A allowed=(
  ["${pkg}/lib/config/app_config.dart"]="throws StateError,throws StateError"
  ["${pkg}/lib/src/config_problem.dart"]="throws ArgumentError.value"
  ["${pkg}/lib/src/schema.dart"]="throws ArgumentError.value,throws ArgumentError.value,throws StateError"
  ["${pkg}/lib/test_helper.dart"]="$(printf 'throws ConfigAssertionFailure,%.0s' 1 2 3 4 5 | sed 's/,$//')"
)
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib" | grep -E '\.dart$' || true)
[[ " ${files[*]} " == *" ${pkg}/lib/diene_config.dart "* ]] || { echo "❌ ${pkg}/lib lacks the barrel diene_config.dart" >&2 && exit 1; }
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
    if (t[k] == 'on' && k + 2 < t.length && t[k + 2] == 'catch') print('catches ${t[k + 1]}');
    if (t[k] == 'rethrow' || t[k] == 'throwWithStackTrace') print('bad uses ${t[k]}');
    if (t[k] != 'throw' || (k > 0 && t[k - 1] == '.')) continue;
    var j = k + (t[k + 1] == 'const' || t[k + 1] == 'new' ? 2 : 1);
    var type = t[j++];
    while (j + 1 < t.length && t[j] == '.' && RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(t[j + 1])) { type += '.${t[j + 1]}'; j += 2; }
    final call = j < t.length ? t[j] : '';
    print(call == '(' && !type.startsWith('"S') ? 'throws $type' : 'bad throws ${type.startsWith('"S') ? 'a string' : type}${call == '(' ? '' : ' (not a constructor call)'}');
  }
}
DART

failed=0
# control: the scanner reports a canary throw, named-constructor throw, rethrow and string throw
canary="$(printf "void a() => throw StateError('x');\n// throw Hidden();\nvoid b() { try {} catch (_) { rethrow; } }\nvoid c() => throw 'x';\nvoid d() => throw ArgumentError.value(1);\n" | dart "${scanner}" | sort | paste -sd ',')"
[[ ${canary} == "bad throws a string (not a constructor call),bad uses rethrow,throws ArgumentError.value,throws StateError" ]] || { echo "❌ control: the throw scanner misreads a canary (${canary})" >&2 && failed=1; }

total=0
for path in "${files[@]}"; do
  report="$(git show "${tree}:${path}" | dart "${scanner}")"
  report="$(sed "/^catches /d; /^$/d" <<<"${report}" | LC_ALL=C sort | paste -sd ",")"
  want="${allowed[${path}]:-}"
  [[ ${report} == "${want}" ]] || { echo "❌ ${path} throws [${report}], allowed exactly [${want}]" >&2 && failed=1; }
  [[ -n ${report} ]] && total=$((total + $(tr ',' '\n' <<<"${report}" | wc -l)))
done
for path in "${!allowed[@]}"; do
  [[ " ${files[*]} " == *" ${path} "* ]] || { echo "❌ allowance names ${path}, which is not in lib/" >&2 && failed=1; }
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ throw-confinement: ${#files[@]} lib files; only the ${total} allowed throws in app_config, schema, config_problem and test_helper"
