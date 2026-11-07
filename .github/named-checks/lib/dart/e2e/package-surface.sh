#!/usr/bin/env bash
set -euo pipefail

# The public names of the barrel and test_helper.dart must equal
# package-surface.txt (the published 1.0.0 surface): one line per library, kind
# and name, members qualified by their type, re-exports as the directive itself.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_e2e"
want="$(dirname "$0")/package-surface.txt"
work="$(mktemp -d)"
git archive "${tree}" "${pkg}/lib" | tar -x -C "${work}"
[[ -f "${work}/${pkg}/lib/diene_e2e.dart" ]] || { echo "❌ ${pkg}/lib/diene_e2e.dart is missing" >&2 && exit 1; }

cat >"${work}/surface.dart" <<'DART'
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

late List<String> t;
var out = <String>[];
const open = {'(': ')', '[': ']', '{': '}'};
const typeMods = {'abstract', 'base', 'final', 'interface', 'sealed', 'mixin'};
bool ident(String s) => has(r'^[A-Za-z_$][\w$]*$', s);

int skipGroup(int k) {
  final stack = <String>[];
  for (; k < t.length; k++) {
    if (open.containsKey(t[k])) {
      stack.add(open[t[k]]!);
    } else if (stack.isNotEmpty && t[k] == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) return k + 1;
    }
  }
  return k;
}

int skipAngle(int k) {
  for (var d = 0; k < t.length; k++) {
    if (t[k] == '<') d++;
    if (t[k] == '>' && --d == 0) return k + 1;
    if (open.containsKey(t[k])) k = skipGroup(k) - 1;
  }
  return k;
}

int skipTo(int k, Set<String> stops) {
  while (k < t.length && !stops.contains(t[k])) k = open.containsKey(t[k]) ? skipGroup(k) : k + 1;
  return k;
}

int skipBody(int k) {
  while (k < t.length) {
    if (t[k] == ';') return k + 1;
    if (t[k] == '=>') return skipTo(k, {';'}) + 1;
    if (t[k] == '{') return skipGroup(k);
    k = open.containsKey(t[k]) ? skipGroup(k) : k + 1;
  }
  return k;
}

void add(String kind, String? owner, String name) {
  if (!name.startsWith('_') && !(owner?.startsWith('_') ?? false)) out.add('$kind ${owner == null ? name : '$owner.$name'}');
}

int member(int k, int end, String? owner) {
  String? last, prev;
  var getter = false, setter = false;
  while (k < end) {
    final s = t[k];
    if (s == '<') { k = skipAngle(k); continue; }
    if (s == 'operator') {
      final name = StringBuffer();
      for (k++; t[k] != '('; k++) name.write(t[k]);
      add('operator', owner, name.toString());
      return skipBody(skipGroup(k));
    }
    if (s == '(') {
      if (last == null || last == 'Function') { k = skipGroup(k); last = 'T'; continue; }
      final ctor = owner != null && (last == owner && prev != '.' || prev == '.' && t[k - 3] == owner);
      add(ctor ? 'ctor' : setter ? 'setter' : owner == null ? 'function' : 'method', owner, ctor && last == owner ? 'new' : last);
      return skipBody(skipGroup(k));
    }
    if (s == '=>' || s == '{') {
      if (getter && last != null) add('getter', owner, last);
      return skipBody(k);
    }
    if (s == '=' || s == ';' || s == ',') {
      if (last != null) add(owner == null ? 'variable' : 'field', owner, last);
      if (s == '=') k = skipTo(t[k + 1] == '<' ? skipAngle(k + 1) : k, {',', ';'});
      if (t[k] == ';') return k + 1;
      last = null;
      k++;
      continue;
    }
    if (s == 'get') getter = true;
    if (s == 'set') setter = true;
    if (ident(s)) { prev = k > 0 ? t[k - 1] : null; last = s; }
    k++;
  }
  return k;
}

void body(int k, int end, String? owner, {bool isEnum = false}) {
  for (; isEnum && k < end && t[k] != ';'; k++) {
    while (t[k] == '@') { k += 2; if (t[k] == '(') k = skipGroup(k); }
    if (ident(t[k])) add('value', owner, t[k]);
    k = skipTo(k, {',', ';', '}'});
    if (t[k] != ',') k--;
  }
  if (isEnum) k++;
  while (k < end) {
    final s = t[k];
    if (s == '@') {
      for (k += 2; t[k] == '.'; k += 2) {}
      if (t[k] == '(') k = skipGroup(k);
      continue;
    }
    if ({'import', 'export', 'part', 'library'}.contains(s)) { k = skipTo(k, {';'}) + 1; continue; }
    var j = k;
    while (typeMods.contains(t[j]) && ident(t[j + 1])) j++;
    final kw = t[j];
    String? kind;
    var nameAt = j + 1;
    if (kw == 'class' || kw == 'enum') {
      kind = kw;
    } else if (kw == 'extension') {
      kind = t[j + 1] == 'type' ? 'extension-type' : 'extension';
      if (kind == 'extension-type') nameAt++;
    } else if (j > k && t[j - 1] == 'mixin') {
      kind = 'mixin';
      nameAt = j;
    }
    if (kind != null) {
      final name = t[nameAt];
      add(kind, null, name);
      final brace = skipTo(nameAt + 1, {'{', ';'});
      if (t[brace] == ';') { k = brace + 1; continue; }
      final close = skipGroup(brace);
      body(brace + 1, close - 1, name, isEnum: kind == 'enum');
      k = close;
    } else if (kw == 'typedef') {
      add('typedef', null, t[j + 1]);
      k = skipTo(j, {';'}) + 1;
    } else {
      k = member(k, end, owner);
    }
  }
}

List<String> library(String path, Set<String>? show, Set<String> hide, Set<String> seen) {
  if (!seen.add('$path $show $hide')) return [];
  src = File(path).readAsStringSync();
  strings = [];
  i = 0;
  final code = lex(false);
  final lits = strings;
  t = RegExp(r'"S\d+"|[A-Za-z_$][\w$]*|\d[\w.]*|=>|\S').allMatches(code).map((m) => m[0]!).toList();
  final tokens = t;
  out = [];
  body(0, tokens.length, null);
  final found = [
    for (final line in out)
      if ((show?.contains(line.split(' ')[1].split('.')[0]) ?? true) && !hide.contains(line.split(' ')[1].split('.')[0])) line,
  ];
  for (var k = 0; k < tokens.length; k++) {
    if (tokens[k] == 'part' && tokens[k + 1] != 'of') { stderr.writeln('bad $path uses part files'); exitCode = 1; }
    if (tokens[k] != 'export' || !tokens[k + 1].startsWith('"S')) continue;
    final uri = lits[int.parse(tokens[k + 1].substring(2, tokens[k + 1].length - 1))] ?? ':';
    Set<String>? s;
    final h = <String>{};
    for (var m = k + 2; tokens[m] != ';';) {
      final target = tokens[m] == 'show' ? (s = {}) : tokens[m] == 'hide' ? h : null;
      for (m++; target != null && !{';', 'show', 'hide'}.contains(tokens[m]); m++) {
        if (ident(tokens[m])) target.add(tokens[m]);
      }
    }
    if (uri.startsWith('package:') && !uri.startsWith('package:diene_e2e/')) {
      final names = show == null ? s : (s ?? show).intersection(show);
      final hidden = {...hide, ...h}, kept = names?.where((n) => !hidden.contains(n)).toList();
      found.add('reexport $uri${kept != null ? ' show ${(kept..sort()).join(',')}' : hidden.isEmpty ? '' : ' hide ${(hidden.toList()..sort()).join(',')}'}');
      continue;
    }
    if (uri.contains(':')) { stderr.writeln('bad $path exports $uri'); exitCode = 1; continue; }
    final narrowed = show == null ? s : (s ?? show).intersection(show);
    found.addAll(library(File(path).parent.uri.resolve(uri).toFilePath(), narrowed, {...hide, ...h}, seen));
  }
  return found;
}

void main(List<String> args) {
  for (final entry in args.skip(1)) {
    for (final line in library('${args[0]}/$entry', null, {}, {}).toSet().toList()..sort()) print('$entry $line');
  }
}
DART

got="$(dart "${work}/surface.dart" "${work}/${pkg}/lib" diene_e2e.dart test_helper.dart | LC_ALL=C sort)"
if [[ ${got} != "$(cat "${want}")" ]]; then
  echo "❌ public surface differs from package-surface.txt (< published, > tree):" >&2
  diff <(cat "${want}") <(echo "${got}") | grep '^[<>]' >&2 || true
  exit 1
fi

echo "✅ package-surface: barrel and test_helper.dart expose exactly the $(wc -l <"${want}") accepted names"
