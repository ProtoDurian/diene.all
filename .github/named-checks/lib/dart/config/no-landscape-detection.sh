#!/usr/bin/env bash
set -euo pipefail

# The landscape is injected, never detected: nothing under lib/ reads the
# process environment or a compile-time define, except the one published 1.0.0
# default in landscape.dart that reads the DIENE_LANDSCAPE --dart-define.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_config"
landscape="${pkg}/lib/src/landscape.dart"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib" | grep -E '\.dart$' || true)
[[ " ${files[*]} " == *" ${landscape} "* ]] || { echo "❌ ${landscape} is missing" >&2 && exit 1; }

scanner="$(mktemp -d)/env.dart"
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
  String tk(int k) => k >= 0 && k < t.length ? t[k] : '';
  for (var k = 0; k < t.length; k++) {
    if ({'fromEnvironment', 'hasEnvironment'}.contains(t[k])) print('reads ${tk(k - 2)}.${t[k]}(${tk(k + 2)})');
    if (t[k] == 'Platform') print('reads Platform${tk(k + 1) == '.' ? '.${tk(k + 2)}' : ''}');
    if (t[k] == 'environment' && tk(k - 1) == '.') print('reads ${tk(k - 2)}.environment');
    if (t[k] == 'landscapeDefineKey' && tk(k - 1) == 'String' && tk(k + 1) == '=') print('key ${strings[int.parse(tk(k + 2).replaceAll(RegExp(r'\D'), ''))]}');
  }
}
DART

failed=0
# control: the scanner reports every environment read in a canary, and no comment or string
canary="$(printf "const a = bool.fromEnvironment('X');\nfinal b = Platform.environment['Y'];\n// int.fromEnvironment('Z')\nconst c = 'String.fromEnvironment';\nfinal d = const bool.hasEnvironment('W');\n" | dart "${scanner}" | sort | paste -sd ',')"
[[ ${canary} == 'reads Platform.environment,reads Platform.environment,reads bool.fromEnvironment("S0"),reads bool.hasEnvironment("S3")' ]] || { echo "❌ control: the environment scanner misreads a canary (${canary})" >&2 && failed=1; }

for path in "${files[@]}"; do
  report="$(git show "${tree}:${path}" | dart "${scanner}")"
  want=""
  [[ ${path} == "${landscape}" ]] && want="key DIENE_LANDSCAPE,reads String.fromEnvironment(landscapeDefineKey)"
  got="$(sed '/^$/d' <<<"${report}" | LC_ALL=C sort | paste -sd ',')"
  [[ ${got} == "${want}" ]] || { echo "❌ ${path} reads the environment [${got}], allowed exactly [${want}]" >&2 && failed=1; }
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ no-landscape-detection: ${#files[@]} lib files read no environment; landscape.dart reads only the DIENE_LANDSCAPE define"
