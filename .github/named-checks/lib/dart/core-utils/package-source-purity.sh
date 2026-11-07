#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_core_utils"
want_deps="diene_interfaces diene_problems diene_result unorm_dart"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

SHAPE_RE="^${pkg}/((lib|test|example|tool|doc|skills/diene-core-utils-usage)/.+|pubspec\.yaml|README\.md|CHANGELOG\.md|LICENSE|analysis_options\.yaml|\.pubignore)$"
ARTIFACT_RE='(^|/)(\.dart_tool|build|coverage|reports|\.pub-cache|\.pub)/|(^|/)(pubspec\.lock|pubspec_overrides\.yaml|package_config\.json|\.packages|lcov\.info)$|\.(g|freezed|mocks)\.dart$'

deps() { git show "${tree}:${pkg}/pubspec.yaml" | yq '.dependencies // {} | keys | .[]'; }

# Drops // and nested /* */ comments outside string literals (Dart source on stdin).
strip_comments() {
  awk 'BEGIN { RS = "^$" } {
    s = $0; n = length(s); out = ""; depth = 0; q = ""; raw = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); d = substr(s, i, 2)
      if (depth > 0) {
        if (d == "/*") { depth++; i++ } else if (d == "*/") { depth--; i++; if (depth == 0) out = out " " }
        continue
      }
      if (q != "") {
        out = out c
        if (c == "\\" && !raw) { out = out substr(s, i + 1, 1); i++ } else if (c == q) q = ""
        continue
      }
      if (d == "//") { while (i <= n && substr(s, i, 1) != "\n") i++; out = out "\n"; continue }
      if (d == "/*") { depth = 1; i++; continue }
      if (c == "\047" || c == "\"") { q = c; raw = (i > 1 && substr(s, i - 1, 1) == "r") }
      out = out c
    }
    printf "%s", out
  }'
}

# Prints the URIs of every import/export/part directive in one Dart source on stdin.
directive_uris() {
  strip_comments | tr '\n' ' ' | sed 's/;/;\n/g' |
    grep -E "(^|[[:space:])])(import|export|part)[[:space:]]+(of[[:space:]]+)?['\"]" |
    sed -E "s/^.*(^|[[:space:])])(import|export|part)[[:space:]]+(of[[:space:]]+)?(['\"])/\4/" |
    grep -oE "'[^']*'|\"[^\"]*\"" | tr -d "'\"" || true
}

# Prints why <uri> from lib file <file> breaks purity; prints nothing when it is allowed.
judge() {
  local file="$1" uri="$2" name target
  case "${uri}" in
  dart:ui) echo "imports dart:ui (Flutter)" ;;
  dart:io | dart:isolate | dart:ffi | dart:html | dart:mirrors) echo "imports ${uri} (I/O or process access)" ;;
  dart:*) ;;
  package:*/*)
    name="${uri#package:}"
    name="${name%%/*}"
    if [[ ${uri} == package:diene_interfaces/test_helper.dart ]]; then
      echo "imports the interfaces fakes (${uri}); port mocks stay in diene_interfaces"
    elif [[ ${name} == flutter* ]]; then
      echo "imports Flutter (${uri})"
    elif [[ ${name} =~ ^(http|process|io)$ ]]; then
      echo "imports ${uri} (I/O or process access)"
    elif [[ ${name} =~ (faro|opentelemetry|otel) ]]; then
      echo "imports ${uri} (a telemetry vendor; only the seams ship)"
    elif [[ ${name} != diene_core_utils && " ${dep_list} " != *" ${name} "* ]]; then
      echo "imports ${uri}, which is not a declared runtime dependency"
    fi
    ;;
  *:*) echo "imports a non-package URI ${uri}" ;;
  *)
    target="$(realpath -m -s "/${pkg}/$(dirname "${file#"${pkg}"/}")/${uri}")"
    [[ ${target} == "/${pkg}/lib/"* ]] || echo "reaches outside lib/ (${uri} -> ${target#/})"
    ;;
  esac
}

dep_list="$(deps | LC_ALL=C sort | paste -sd ' ')"
spec="$(git show "${tree}:${pkg}/pubspec.yaml")"
[[ ${dep_list} == "${want_deps}" ]] || fail "runtime dependencies are '${dep_list}', want exactly ${want_deps}"
ranges=""
for d in ${want_deps}; do
  range="$(yq ".dependencies.${d} | select(tag == \"!!str\")" <<<"${spec}")"
  [[ ${range} =~ ^\^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "${d} must be a hosted caret range (^x.y.z), got: $(yq -o=json -I=0 ".dependencies.${d}" <<<"${spec}")"
  ranges="${ranges} ${d} ${range}"
done
for m in "${pkg}/pubspec.yaml" pubspec.yaml; do
  [[ "$(git show "${tree}:${m}" | yq 'has("dependency_overrides")')" == false ]] || fail "${m} declares dependency_overrides"
done

# --- positive control: the scanners fire on canaries and see the real package ---
[[ -n "$(judge "${pkg}/lib/src/a.dart" ../../test/unit/x.dart)" ]] || fail "control: a lib -> test/ import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" package:flutter/material.dart)" ]] || fail "control: a Flutter import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" package:test/test.dart)" ]] || fail "control: a dev-dependency import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" dart:io)" ]] || fail "control: a dart:io import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" dart:isolate)" ]] || fail "control: a dart:isolate import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" package:http/http.dart)" ]] || fail "control: a package:http import is not caught"
dep_list="${dep_list} faro_dart opentelemetry"
[[ -n "$(judge "${pkg}/lib/a.dart" package:faro_dart/faro.dart)" ]] || fail "control: a declared Faro import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" package:opentelemetry/api.dart)" ]] || fail "control: a declared OpenTelemetry import is not caught"
dep_list="$(deps | LC_ALL=C sort | paste -sd ' ')"
[[ -z "$(judge "${pkg}/lib/a.dart" package:diene_problems/diene_problems.dart)" ]] || fail "control: the diene_problems import is flagged"
[[ -z "$(judge "${pkg}/lib/a.dart" package:diene_result/diene_result.dart)" ]] || fail "control: the diene_result import is flagged"
[[ -z "$(judge "${pkg}/lib/a.dart" package:unorm_dart/unorm_dart.dart)" ]] || fail "control: the unorm_dart import is flagged"
[[ -n "$(judge "${pkg}/lib/a.dart" package:diene_interfaces/test_helper.dart)" ]] || fail "control: an interfaces fake import is not caught"
[[ -z "$(judge "${pkg}/lib/src/a.dart" option.dart)" ]] || fail "control: an in-lib relative import is flagged"
[[ "$(printf "/// import 'package:x/y.dart';\nimport 'a.dart'\n    show A;\nexport \"b.dart\";\n" | directive_uris | tr '\n' ' ')" == "a.dart b.dart " ]] || fail "control: the directive parser misreads a canary"
[[ "$(printf "/* doc */ import 'package:test/test.dart';\n/* a /* nested */ still */import 'c.dart';\n/*\n import 'package:hidden/x.dart';\n*/\n@Tag('a//b /* c') import 'd.dart';\n" | directive_uris | tr '\n' ' ')" == "package:test/test.dart c.dart d.dart " ]] || fail "control: the directive parser misses an import after a block comment"
echo "${pkg}/.dart_tool/package_config.json" | grep -qE "${ARTIFACT_RE}" || fail "control: the artifact matcher misses a canary"

mapfile -t pkg_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/")
mapfile -t lib_files < <(printf '%s\n' "${pkg_files[@]}" | grep -E "^${pkg}/lib/.*\.dart$" || true)
[[ ${#pkg_files[@]} -gt 0 ]] || fail "control: ${pkg} has no tracked files"
[[ ${#lib_files[@]} -gt 0 ]] || fail "control: ${pkg}/lib has no Dart sources"
[[ " ${pkg_files[*]} " == *" ${pkg}/lib/diene_core_utils.dart "* ]] || fail "control: the public barrel ${pkg}/lib/diene_core_utils.dart is missing"

# --- package shape -------------------------------------------------------------
for f in "${pkg_files[@]}"; do
  [[ ${f} =~ ${SHAPE_RE} ]] || fail "outside the package shape: ${f}"
done

# --- no generated or build artifacts anywhere in the tree ----------------------
hits="$(git ls-tree -r --name-only "${tree}" | grep -E "${ARTIFACT_RE}" || true)"
[[ -z ${hits} ]] || fail "generated/build artifacts tracked:"$'\n'"${hits}"

# --- lib/** imports only dart:, itself and declared runtime dependencies ---------
directives=0
for f in "${lib_files[@]}"; do
  while read -r uri; do
    [[ -z ${uri} ]] && continue
    directives=$((directives + 1))
    why="$(judge "${f}" "${uri}")"
    [[ -z ${why} ]] || fail "${f} ${why}"
  done < <(git show "${tree}:${f}" | directive_uris)
done
[[ ${directives} -gt 0 ]] || fail "control: no import/export directive found in ${pkg}/lib"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-source-purity: ${#pkg_files[@]} files in the package shape, no tracked artifacts, ${directives} lib directives use only pure dart: and hosted${ranges}"
