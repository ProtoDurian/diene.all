#!/usr/bin/env bash
set -euo pipefail

# The `app-handoff` path segment appears in lib/ code only as the config
# default (AppHandoffConstants.defaultMount), and only the config (and the
# TestHelper redeem stub, by that constant) reads that default, so no client
# hardcodes it or appends it to a configured mount.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_auth_engine"
config="${pkg}/lib/src/config/auth_engine_config.dart"
helper="${pkg}/lib/test_helper.dart"
default_line="static const String defaultMount = '/app-handoff';"
SEGMENT_RE='(^|[^A-Za-z0-9_.:-])app-handoff([^A-Za-z0-9_:-]|$)'
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

# Drops // and nested /* */ comments outside string literals, keeping line numbers.
strip_comments() {
  awk 'BEGIN { RS = "^$" } {
    s = $0; n = length(s); out = ""; depth = 0; q = ""; raw = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); d = substr(s, i, 2)
      if (depth > 0) {
        if (c == "\n") out = out c
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

trim() { sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }

# --- positive control -----------------------------------------------------------
for canary in "'\$mount/app-handoff/redeem'" "'app-handoff/redeem'" "base + '/app-handoff'"; do
  grep -qE "${SEGMENT_RE}" <<<"${canary}" || fail "control: the segment matcher misses ${canary}"
done
for benign in "'atomi-app-handoff:v1:'" "'urn:diene:problem:app-handoff-expired'"; do
  ! grep -qE "${SEGMENT_RE}" <<<"${benign}" || fail "control: the segment matcher flags ${benign}"
done
[[ -z "$(printf "/// POST /app-handoff/redeem\nint a = 1; // '/app-handoff'\n/* '/app-handoff' */\n" | strip_comments | grep -E "${SEGMENT_RE}" || true)" ]] || fail "control: comments are not stripped"

mapfile -t lib_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib/" | grep -E '\.dart$' || true)
[[ ${#lib_files[@]} -gt 0 ]] || fail "control: ${pkg}/lib has no Dart sources"

segments=0
refs=0
for f in "${lib_files[@]}"; do
  code="$(git show "${tree}:${f}" | strip_comments)"
  while IFS=: read -r line text; do
    [[ -z ${line} ]] && continue
    segments=$((segments + 1))
    text="$(trim <<<"${text}")"
    [[ ${f} == "${config}" && ${text} == "${default_line}" ]] || fail "${f}:${line} hardcodes the app-handoff segment: ${text}"
  done < <(grep -nE "${SEGMENT_RE}" <<<"${code}" || true)
  while IFS=: read -r line text; do
    [[ -z ${line} ]] && continue
    refs=$((refs + 1))
    [[ ${f} == "${config}" || (${f} == "${helper}" && ${text} == *AppHandoffConstants.defaultMount*) ]] || fail "${f}:${line} reads the default mount outside the config: $(trim <<<"${text}")"
  done < <(grep -nwE 'defaultMount' <<<"${code}" || true)
done
[[ ${segments} -eq 1 ]] || fail "the app-handoff segment appears ${segments} times in lib/ code, want once (the config default)"
[[ ${refs} -ge 2 ]] || fail "control: the config no longer defaults appHandoffMount to defaultMount (${refs} references)"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ no-default-mount-hardcode: app-handoff appears once in lib/ code (the config default); defaultMount is read only by the config and the TestHelper stub (${refs} references)"
