#!/usr/bin/env bash
set -euo pipefail

# Platform and HTTP-stack imports stay in the layers that need them (homes());
# the pure core (bridge, client tree, config, rescue docs and router, TestHelper)
# imports none of them, and only lib/src/generated/ imports the generated SDK.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_api_engine"
src="${pkg}/lib/src/"
generated="${src}generated/"
core=(bridge.dart client_tree.dart config.dart rescue/docs.dart rescue/router.dart)
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

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

# Prints the lib/src/ paths allowed to import <uri> (a trailing / is a subtree,
# "nowhere" is no file); fails for a URI that is not confined.
homes() {
  case "$1" in
  dart:io) echo "transport.dart rescue/store.dart" ;;
  package:dio/*) echo "engine.dart oa3/sdk_adapter.dart generated/" ;;
  package:retrofit/* | package:json_annotation/*) echo "generated/" ;;
  dart:ui | dart:ffi | dart:isolate | package:flutter/*) echo "nowhere" ;;
  *) return 1 ;;
  esac
}

# Prints why <uri> in lib file <file> breaks confinement; nothing when allowed.
judge() {
  local file="$1" uri="$2" rel="${1#"${src}"}" allowed home target
  if allowed="$(homes "${uri}")"; then
    for home in ${allowed}; do
      [[ ${file} == "${src}"* && (${rel} == "${home}" || (${home} == */ && ${rel} == "${home}"*)) ]] && return 0
    done
    echo "imports ${uri} outside its layer (${allowed})"
    return 0
  fi
  case "${uri}" in
  package:diene_api_engine/*) target="/${pkg}/lib/${uri#package:diene_api_engine/}" ;;
  *:*) return 0 ;;
  *) target="$(realpath -m -s "/$(dirname "${file}")/${uri}")" ;;
  esac
  [[ ${file} != "${generated}"* && ${target} == "/${generated}"* ]] && echo "reaches into the generated SDK (${uri})"
  return 0
}

# --- positive control -----------------------------------------------------------
[[ -n "$(judge "${src}bridge.dart" dart:io)" ]] || fail "control: a core dart:io import is not caught"
[[ -n "$(judge "${src}rescue/router.dart" dart:io)" ]] || fail "control: the store's dart:io home widens to the router"
[[ -n "$(judge "${src}client_tree.dart" package:dio/dio.dart)" ]] || fail "control: a core dio import is not caught"
[[ -n "$(judge "${src}engine.dart" package:retrofit/retrofit.dart)" ]] || fail "control: a retrofit import outside generated/ is not caught"
[[ -n "$(judge "${src}transport.dart" package:flutter/foundation.dart)" ]] || fail "control: a flutter import is not caught"
[[ -n "$(judge "${pkg}/lib/test_helper.dart" dart:io)" ]] || fail "control: a TestHelper dart:io import is not caught"
[[ -n "$(judge "${src}test_helper/fakes.dart" package:dio/dio.dart)" ]] || fail "control: a TestHelper dio import is not caught"
[[ -n "$(judge "${src}engine.dart" generated/service_sdk.dart)" ]] || fail "control: a core -> generated SDK import is not caught"
[[ -n "$(judge "${pkg}/lib/diene_api_engine.dart" package:diene_api_engine/src/generated/export.dart)" ]] || fail "control: a barrel -> generated SDK export is not caught"
[[ -z "$(judge "${src}generated/clients/a.dart" package:retrofit/retrofit.dart)" ]] || fail "control: a generated retrofit import is flagged"
[[ -z "$(judge "${src}rescue/store.dart" dart:io)" ]] || fail "control: the store's dart:io import is flagged"
[[ -z "$(judge "${src}generated/a.dart" clients/b.dart)" ]] || fail "control: an import inside generated/ is flagged"
[[ -z "$(judge "${src}config.dart" package:collection/collection.dart)" ]] || fail "control: a collection import is flagged"

mapfile -t lib_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib/" | grep -E '\.dart$' || true)
[[ ${#lib_files[@]} -gt 0 ]] || fail "control: ${pkg}/lib has no Dart sources"
for f in "${core[@]}"; do
  [[ " ${lib_files[*]} " == *" ${src}${f} "* ]] || fail "control: core file ${src}${f} is missing; the layout moved?"
done

directives=0
seen=""
for f in "${lib_files[@]}"; do
  while read -r uri; do
    [[ -z ${uri} ]] && continue
    directives=$((directives + 1))
    homes "${uri}" >/dev/null && seen+=" ${f#"${src}"}=${uri%%/*}"
    why="$(judge "${f}" "${uri}")"
    [[ -z ${why} ]] || fail "${f} ${why}"
  done < <(git show "${tree}:${f}" | directive_uris)
done
for want in transport.dart=dart:io rescue/store.dart=dart:io engine.dart=package:dio oa3/sdk_adapter.dart=package:dio; do
  [[ " ${seen} " == *" ${want} "* ]] || fail "control: no ${want#*=} import found in ${src}${want%=*}; the layer moved?"
done
[[ " ${seen} " == *" generated/"*"=package:retrofit "* ]] || fail "control: no package:retrofit import found in ${generated}"
[[ ${directives} -gt 0 ]] || fail "control: no directive found in ${pkg}/lib"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ adapter-confinement: ${directives} lib directives; dart:io, dio, retrofit, json_annotation stay in their layers, no flutter import, the core (${core[*]}) and TestHelper are platform-free, only generated/ imports the SDK"
