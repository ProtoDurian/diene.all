#!/usr/bin/env bash
set -euo pipefail

# test_helper.dart re-exports exactly the six member TestHelpers; none for
# core_utils, and no OpenTelemetry or standard-config member anywhere in lib/.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_e2e"
helper="${pkg}/lib/test_helper.dart"
want="api_engine auth_engine config interfaces problems result"
banned='otel|opentelemetry|telemetry|standard[_-]?config'
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

# Prints "<keyword> <uri>" for every import/export/part directive in one Dart source on stdin.
directives() {
  strip_comments | tr '\n' ' ' | sed 's/;/;\n/g' |
    sed -nE "s/^(.*[[:space:])])?(import|export|part)[[:space:]]+(of[[:space:]]+)?(['\"])([^'\"]*)\4.*$/\2 \5/p" || true
}

# --- positive control: the parser reads a canary ------------------------------
canary="$(printf "// export 'package:diene_core_utils/test_helper.dart';\n/* export 'package:x/test_helper.dart'; */\nexport 'package:diene_result/test_helper.dart'\n    hide expectOk;\nimport \"dart:io\";\n" | directives | paste -sd ',')"
[[ ${canary} == "export package:diene_result/test_helper.dart,import dart:io" ]] || fail "control: the directive parser misreads a canary (${canary})"

mapfile -t lib_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib/" | grep -E '\.dart$' || true)
[[ " ${lib_files[*]} " == *" ${helper} "* ]] || fail "control: ${helper} is missing"

got=()
for f in "${lib_files[@]}"; do
  [[ ${f#"${pkg}"/lib/} =~ ${banned} ]] && fail "${f}: an OpenTelemetry/standard-config member file in lib/"
  while read -r kw uri; do
    [[ -z ${uri} ]] && continue
    if [[ ${uri} =~ ${banned} ]]; then
      fail "${f} ${kw}s ${uri} (no OpenTelemetry/standard-config member exists in Dart)"
    fi
    if [[ ${uri} =~ ^package:diene_([a-z_]+)/test_helper\.dart$ ]]; then
      member="${BASH_REMATCH[1]}"
      if [[ ${f} != "${helper}" || ${kw} != export ]]; then
        fail "${f} ${kw}s ${uri}; member TestHelpers are re-exported only by ${helper}"
      elif [[ ${member} == core_utils ]]; then
        fail "${helper} re-exports diene_core_utils' TestHelper; core_utils has none to pass through"
      else
        got+=("${member}")
      fi
    fi
  done < <(git show "${tree}:${f}" | directives)
done

got_list="$(printf '%s\n' "${got[@]}" | grep . | LC_ALL=C sort | paste -sd ' ' || true)"
[[ ${got_list} == "${want}" ]] || fail "${helper} re-exports member TestHelpers '${got_list}', want exactly '${want}'"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ helper-passthroughs: ${helper} re-exports exactly '${want}' member TestHelpers; none for core_utils, no OpenTelemetry/standard-config in lib/"
