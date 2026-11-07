#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_auth_engine"
want_deps="diene_problems diene_result flutter http logto_dart_sdk meta"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

SHAPE_RE="^${pkg}/((lib|test|example|tool|doc|skills/diene-auth-engine-usage)/.+|pubspec\.yaml|README\.md|CHANGELOG\.md|LICENSE|analysis_options\.yaml|\.pubignore)$"
ARTIFACT_RE='(^|/)(\.dart_tool|build|coverage|reports|\.pub-cache|\.pub)/|(^|/)(pubspec\.lock|pubspec_overrides\.yaml|package_config\.json|\.packages|lcov\.info)$|\.(g|freezed|mocks)\.dart$'

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
  dart:html | dart:mirrors | dart:js | dart:js_util) echo "imports ${uri} (not a mobile Flutter library)" ;;
  dart:*) ;;
  package:*/*)
    name="${uri#package:}"
    name="${name%%/*}"
    if [[ ${name} != diene_auth_engine && " ${dep_list} " != *" ${name} "* ]]; then
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

# --- runtime dependencies: exactly the published set, hosted caret ranges + flutter sdk ---
spec="$(git show "${tree}:${pkg}/pubspec.yaml")"
dep_list="$(yq '.dependencies // {} | keys | .[]' <<<"${spec}" | LC_ALL=C sort | paste -sd ' ')"
[[ ${dep_list} == "${want_deps}" ]] || fail "runtime dependencies are '${dep_list}', want exactly '${want_deps}'"
for dep in ${dep_list}; do
  value="$(yq -o=json -I=0 ".dependencies.\"${dep}\"" <<<"${spec}")"
  if [[ ${dep} == flutter ]]; then
    [[ ${value} == '{"sdk":"flutter"}' ]] || fail "flutter must be exactly the sdk dependency, got: ${value}"
  else
    [[ ${value} =~ ^\"\^[0-9]+\.[0-9]+\.[0-9]+\"$ ]] || fail "${dep} must be a hosted caret range (^x.y.z), got: ${value}"
  fi
done
sourced="$(yq '.dev_dependencies // {} | to_entries | .[] | select(.value | tag == "!!map") | select(.value | has("path") or has("git") or has("hosted")) | .key' <<<"${spec}")"
[[ -z ${sourced} ]] || fail "dev_dependencies resolve from path/git/custom hosts: ${sourced//$'\n'/ }"
for m in "${pkg}/pubspec.yaml" pubspec.yaml; do
  [[ "$(git show "${tree}:${m}" | yq 'has("dependency_overrides")')" == false ]] || fail "${m} declares dependency_overrides"
done

# --- positive control: the scanners fire on canaries and see the real package ---
[[ -n "$(judge "${pkg}/lib/src/a.dart" ../../test/unit/x.dart)" ]] || fail "control: a lib -> test/ import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" package:flutter_test/flutter_test.dart)" ]] || fail "control: a dev-dependency import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" dart:mirrors)" ]] || fail "control: a dart:mirrors import is not caught"
[[ -z "$(judge "${pkg}/lib/a.dart" package:logto_dart_sdk/logto_dart_sdk.dart)" ]] || fail "control: the logto_dart_sdk import is flagged"
[[ -z "$(judge "${pkg}/lib/src/a/b.dart" ../c/d.dart)" ]] || fail "control: an in-lib relative import is flagged"
[[ "$(printf "/// import 'package:x/y.dart';\nimport 'a.dart'\n    show A;\nexport \"b.dart\";\n" | directive_uris | tr '\n' ' ')" == "a.dart b.dart " ]] || fail "control: the directive parser misreads a canary"
[[ "$(printf "/* doc */ import 'package:test/test.dart';\n/* a /* nested */ still */import 'c.dart';\n/*\n import 'package:hidden/x.dart';\n*/\n@Tag('a//b /* c') import 'd.dart';\n" | directive_uris | tr '\n' ' ')" == "package:test/test.dart c.dart d.dart " ]] || fail "control: the directive parser misses an import after a block comment"
echo "${pkg}/.dart_tool/package_config.json" | grep -qE "${ARTIFACT_RE}" || fail "control: the artifact matcher misses a canary"

mapfile -t pkg_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/")
mapfile -t lib_files < <(printf '%s\n' "${pkg_files[@]}" | grep -E "^${pkg}/lib/.*\.dart$" || true)
[[ ${#pkg_files[@]} -gt 0 ]] || fail "control: ${pkg} has no tracked files"
[[ ${#lib_files[@]} -gt 0 ]] || fail "control: ${pkg}/lib has no Dart sources"
[[ " ${pkg_files[*]} " == *" ${pkg}/lib/diene_auth_engine.dart "* ]] || fail "control: the public barrel ${pkg}/lib/diene_auth_engine.dart is missing"

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

echo "✅ package-source-purity: ${#pkg_files[@]} files in the package shape, no tracked artifacts, runtime deps exactly '${want_deps}' (hosted carets + flutter sdk), ${directives} lib directives use only dart:, itself and those deps"
