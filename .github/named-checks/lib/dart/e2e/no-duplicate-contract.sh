#!/usr/bin/env bash
set -euo pipefail

# The app-handoff vectors live only in the vendored upstream fixture: lib/
# ships Dart sources only, and no lib string literal carries a nonce-sized
# token (every vendored nonce, carrier and referrer vector has one).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_e2e"
upstream="${pkg}/test/fixtures/c0/upstream"
token='[A-Za-z0-9_-]{32,}'
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

# Prints the contents of every string literal outside comments, one per line (Dart source on stdin).
string_literals() {
  awk 'BEGIN { RS = "^$" } {
    s = $0; n = length(s); out = ""; depth = 0; q = ""; raw = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); d = substr(s, i, 2)
      if (depth > 0) {
        if (d == "/*") { depth++; i++ } else if (d == "*/") { depth--; i++ }
        continue
      }
      if (q != "") {
        if (c == "\\" && !raw) { out = out c substr(s, i + 1, 1); i++ } else if (c == q) { q = ""; out = out "\n" } else out = out c
        continue
      }
      if (d == "//") { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
      if (d == "/*") { depth = 1; i++; continue }
      if (c == "\047" || c == "\"") { q = c; raw = (i > 1 && substr(s, i - 1, 1) == "r") }
    }
    printf "%s", out
  }'
}

# --- control: the vendored vectors exist and carry nonce-sized tokens -----------
mapfile -t vector_files < <(git ls-tree -r --name-only "${tree}" -- "${upstream}/" | grep -E '\.json$' | grep -v '/manifest\.json$' || true)
[[ ${#vector_files[@]} -gt 0 ]] || fail "control: no vendored vector JSON under ${upstream}/"
vectors=0
for f in "${vector_files[@]}"; do
  vectors=$((vectors + $(git show "${tree}:${f}" | jq --arg t "${token}" '[.. | strings | select(test($t))] | length')))
done
[[ ${vectors} -gt 0 ]] || fail "control: no app-handoff carrier or nonce vector in ${upstream}/"
canary="$(printf "// 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'\nconst c = r'atomi-app-handoff:v1:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';\nconst appHandoffTokenExpiresInSecondsAndMore = 1;\n" | string_literals | grep -cE "${token}" || true)"
[[ ${canary} == 1 ]] || fail "control: the literal scanner misreads a canary (${canary} hits, want 1)"

# --- lib/ carries no second copy -----------------------------------------------
mapfile -t lib_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/lib/")
[[ ${#lib_files[@]} -gt 0 ]] || fail "control: ${pkg}/lib has no tracked files"
for f in "${lib_files[@]}"; do
  if [[ ${f} != *.dart ]]; then
    fail "${f}: lib/ ships only Dart sources; contract data belongs in ${upstream}/"
    continue
  fi
  hits="$(git show "${tree}:${f}" | string_literals | grep -oE "${token}" | paste -sd ' ' || true)"
  [[ -z ${hits} ]] || fail "${f} inlines app-handoff vector data (${hits}); read it from ${upstream}/"
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ no-duplicate-contract: ${vectors} app-handoff vectors only in ${upstream}/; ${#lib_files[@]} lib files inline none"
