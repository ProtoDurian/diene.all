#!/usr/bin/env bash
set -euo pipefail

# Platform imports (dart:io/ui/ffi/isolate, package:http, package:flutter/,
# package:logto_dart_sdk) live only in the adapter layer lib/src/logto/; the
# rest of lib/ neither imports them nor reaches into the adapter layer.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_auth_engine"
adapter="${pkg}/lib/src/logto/"
# SessionController extends ChangeNotifier in the published 1.0.2 surface.
allowed=("${pkg}/lib/src/auth/session_controller.dart package:flutter/foundation.dart")
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

platform() {
  case "$1" in
  dart:io | dart:ui | dart:ffi | dart:isolate | package:http/* | package:flutter/* | package:logto_dart_sdk/*) return 0 ;;
  esac
  return 1
}

# Prints why <uri> in non-adapter lib file <file> breaks confinement; nothing when allowed.
judge() {
  local file="$1" uri="$2" target
  if platform "${uri}"; then
    [[ " ${allowed[*]} " == *" ${file} ${uri} "* ]] || echo "imports the platform ${uri} outside ${adapter}"
    return
  fi
  case "${uri}" in
  package:diene_auth_engine/*) target="/${pkg}/lib/${uri#package:diene_auth_engine/}" ;;
  *:*) return ;;
  *) target="$(realpath -m -s "/$(dirname "${file}")/${uri}")" ;;
  esac
  [[ ${file} == "${pkg}/lib/src/"* && ${target} == "/${adapter}"* ]] && echo "reaches into the adapter layer (${uri})"
  return 0
}

# --- positive control -----------------------------------------------------------
[[ -n "$(judge "${pkg}/lib/src/tokens/a.dart" dart:io)" ]] || fail "control: a core dart:io import is not caught"
[[ -n "$(judge "${pkg}/lib/src/auth/a.dart" package:http/http.dart)" ]] || fail "control: a core package:http import is not caught"
[[ -n "$(judge "${pkg}/lib/src/home/a.dart" package:flutter/services.dart)" ]] || fail "control: a core flutter import is not caught"
[[ -n "$(judge "${pkg}/lib/src/auth/session_controller.dart" package:flutter/services.dart)" ]] || fail "control: the foundation allowance widens to other flutter libraries"
[[ -n "$(judge "${pkg}/lib/src/auth/claims.dart" package:flutter/foundation.dart)" ]] || fail "control: the foundation allowance widens to other files"
[[ -n "$(judge "${pkg}/lib/src/deferred/a.dart" ../logto/http_app_handoff_api.dart)" ]] || fail "control: a core -> adapter import is not caught"
[[ -n "$(judge "${pkg}/lib/src/a.dart" package:diene_auth_engine/src/logto/x.dart)" ]] || fail "control: a core -> adapter package import is not caught"
[[ -z "$(judge "${pkg}/lib/src/onboarding/a.dart" package:diene_result/diene_result.dart)" ]] || fail "control: a diene_result import is flagged"

mapfile -t lib_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib/" | grep -E '\.dart$' || true)
[[ ${#lib_files[@]} -gt 0 ]] || fail "control: ${pkg}/lib has no Dart sources"

core=0
seen=""
for f in "${lib_files[@]}"; do
  while read -r uri; do
    [[ -z ${uri} ]] && continue
    if [[ ${f} == "${adapter}"* ]]; then
      platform "${uri}" && seen+=" ${uri%%/*}"
      continue
    fi
    core=$((core + 1))
    why="$(judge "${f}" "${uri}")"
    [[ -z ${why} ]] || fail "${f} ${why}"
  done < <(git show "${tree}:${f}" | directive_uris)
done
for want in package:http package:logto_dart_sdk package:flutter; do
  [[ " ${seen} " == *" ${want} "* ]] || fail "control: no ${want} import found in ${adapter}; the adapter layer moved?"
done
[[ ${core} -gt 0 ]] || fail "control: no directive found outside ${adapter}"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ adapter-confinement: platform imports only in ${adapter}; ${core} directives elsewhere in lib/ stay platform-free (allowed: ${allowed[*]})"
