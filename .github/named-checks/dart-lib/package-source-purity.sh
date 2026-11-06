#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_dart_lib"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

SHAPE_RE="^${pkg}/((lib|test|example|tool|doc|skills/diene-dart-lib-usage)/.+|pubspec\.yaml|README\.md|CHANGELOG\.md|LICENSE|analysis_options\.yaml|\.pubignore)$"
ARTIFACT_RE='(^|/)(\.dart_tool|build|coverage|reports|\.pub-cache|\.pub)/|(^|/)(pubspec\.lock|pubspec_overrides\.yaml|package_config\.json|\.packages|lcov\.info)$|\.(g|freezed|mocks)\.dart$'

deps() { git show "${tree}:${pkg}/pubspec.yaml" | yq '.dependencies // {} | keys | .[]'; }

# Prints the URIs of every import/export/part directive in one Dart source on stdin.
directive_uris() {
  sed -e 's#//.*$##' | tr '\n' ' ' | sed 's/;/;\n/g' |
    grep -E '^[[:space:]]*(import|export|part)([[:space:]]|$)' |
    grep -oE "'[^']*'|\"[^\"]*\"" | tr -d "'\"" || true
}

# Prints why <uri> from lib file <file> breaks purity; prints nothing when it is allowed.
judge() {
  local file="$1" uri="$2" name target
  case "${uri}" in
  dart:ui) echo "imports dart:ui (Flutter)" ;;
  dart:*) ;;
  package:*/*)
    name="${uri#package:}"
    name="${name%%/*}"
    if [[ ${name} == flutter* ]]; then
      echo "imports Flutter (${uri})"
    elif [[ ${name} != diene_dart_lib && " ${dep_list} " != *" ${name} "* ]]; then
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

dep_list="$(deps | paste -sd ' ')"

# --- positive control: the scanners fire on canaries and see the real package ---
[[ -n "$(judge "${pkg}/lib/src/a.dart" ../../test/unit/x.dart)" ]] || fail "control: a lib -> test/ import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" package:flutter/material.dart)" ]] || fail "control: a Flutter import is not caught"
[[ -n "$(judge "${pkg}/lib/a.dart" package:test/test.dart)" ]] || fail "control: a dev-dependency import is not caught"
[[ -z "$(judge "${pkg}/lib/src/a.dart" note.dart)" ]] || fail "control: an in-lib relative import is flagged"
[[ "$(printf "/// import 'package:x/y.dart';\nimport 'a.dart'\n    show A;\nexport \"b.dart\";\n" | directive_uris | tr '\n' ' ')" == "a.dart b.dart " ]] || fail "control: the directive parser misreads a canary"
echo "${pkg}/.dart_tool/package_config.json" | grep -qE "${ARTIFACT_RE}" || fail "control: the artifact matcher misses a canary"

mapfile -t pkg_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/")
mapfile -t lib_files < <(printf '%s\n' "${pkg_files[@]}" | grep -E "^${pkg}/lib/.*\.dart$" || true)
[[ ${#pkg_files[@]} -gt 0 ]] || fail "control: ${pkg} has no tracked files"
[[ ${#lib_files[@]} -gt 0 ]] || fail "control: ${pkg}/lib has no Dart sources"
[[ " ${pkg_files[*]} " == *" ${pkg}/lib/diene_dart_lib.dart "* ]] || fail "control: the public barrel ${pkg}/lib/diene_dart_lib.dart is missing"

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

echo "✅ package-source-purity: ${#pkg_files[@]} files in the package shape, no tracked artifacts, ${directives} lib directives use only dart:, diene_dart_lib and runtime deps (${dep_list:-none})"
