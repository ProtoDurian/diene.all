#!/usr/bin/env bash
set -euo pipefail

# The request path stays one host: the rescue's URL lists and documents are
# named only in lib/src/rescue/, config.dart, the barrel and the TestHelper;
# no breaker, ladder, failover or URL-list name exists in lib/; and the engine
# builds a RescueRouter only behind RescueConfig.enabled.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_api_engine"
engine="${pkg}/lib/src/engine.dart"
OFF_PATH_RE="^${pkg}/lib/(src/rescue/.+|src/config\.dart|diene_api_engine\.dart|test_helper\.dart|src/test_helper/.+)$"
RESCUE_RE='^(doca|docc|cataloghosts|endpointsuffixallowlist)$'
BANNED_RE='breaker|circuit|ladder|failover|^(base|fallback|backup|candidate)?(urls|hosts|urllist|hostlist)$'
GATE_RE='\.enabled ?\? ?RescueRouter ?\('
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

# Prints how many times ERE <re> matches stdin (0 when none).
count() {
  grep -oE -- "$1" | wc -l || true
}

# Prints the identifiers of one comment-free Dart source on stdin, one per line.
identifiers() {
  grep -oE '[A-Za-z_$][A-Za-z0-9_$]*' || true
}

# Prints why comment-free Dart source <code> in lib file <file> breaks the rule.
judge() {
  local file="$1" code="$2" ids hits
  ids="$(identifiers <<<"${code}" | LC_ALL=C sort -u)"
  hits="$(grep -iE "${BANNED_RE}" <<<"${ids}" | paste -sd ' ' || true)"
  [[ -z ${hits} ]] || echo "names a breaker/ladder/URL list: ${hits}"
  if [[ ! ${file} =~ ${OFF_PATH_RE} ]]; then
    hits="$(grep -iE "${RESCUE_RE}" <<<"${ids}" | paste -sd ' ' || true)"
    [[ -z ${hits} ]] || echo "reads rescue URL lists/documents on the request path: ${hits}"
    local flat built gated
    flat="$(tr -s '[:space:]' ' ' <<<"${code}")"
    built="$(count 'RescueRouter ?\(' <<<"${flat}")"
    gated="$(count "${GATE_RE}" <<<"${flat}")"
    [[ ${built} -eq ${gated} ]] || echo "builds a RescueRouter outside a RescueConfig.enabled gate"
  fi
  return 0
}

# --- positive control -----------------------------------------------------------
[[ -n "$(judge "${engine}" 'final a = config.rescue.catalogHosts;')" ]] || fail "control: an engine read of catalogHosts is not caught"
[[ -n "$(judge "${pkg}/lib/src/transport.dart" 'DocC? c;')" ]] || fail "control: a transport DocC reference is not caught"
[[ -n "$(judge "${pkg}/lib/src/rescue/router.dart" 'final b = CircuitBreaker();')" ]] || fail "control: a breaker is not caught"
[[ -n "$(judge "${pkg}/lib/src/config.dart" 'final List<Uri> baseUrls;')" ]] || fail "control: a URL list is not caught"
[[ -n "$(judge "${engine}" 'final r = RescueRouter(config: c);')" ]] || fail "control: an ungated RescueRouter is not caught"
[[ -z "$(judge "${engine}" "final r = c.rescue.enabled
    ? RescueRouter(config: c)
    : null;")" ]] || fail "control: a gated RescueRouter is flagged"
[[ -z "$(judge "${pkg}/lib/src/rescue/router.dart" 'final DocA docA; final c = x.catalogHosts;')" ]] || fail "control: the rescue layer's own names are flagged"
[[ -z "$(judge "${engine}" "$(printf '// catalogHosts DocA\nfinal x = 1;\n' | strip_comments)")" ]] || fail "control: a comment is read as code"

mapfile -t lib_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib/" | grep -E '\.dart$' || true)
[[ " ${lib_files[*]} " == *" ${engine} "* ]] || fail "control: ${engine} is missing; the request path moved?"

gates=0
for f in "${lib_files[@]}"; do
  code="$(git show "${tree}:${f}" | strip_comments)"
  why="$(judge "${f}" "${code}")"
  [[ -z ${why} ]] || fail "${f} ${why//$'\n'/; }"
  [[ ${f} == "${engine}" ]] && gates="$(tr -s '[:space:]' ' ' <<<"${code}" | count "${GATE_RE}")"
done
[[ ${gates} -ge 1 ]] || fail "control: ${engine} builds no RescueRouter behind RescueConfig.enabled"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ rescue-off-hot-path: ${#lib_files[@]} lib files; rescue URL lists stay off the request path, no breaker/ladder/URL list, ${gates} RescueRouter build(s) all behind RescueConfig.enabled"
