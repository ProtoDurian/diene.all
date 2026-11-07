#!/usr/bin/env bash
set -euo pipefail

# The ports' errors are typed by the published errors-problems module, never by
# an in-repository copy of it:
#   absence  - no tracked Go file declares `package problem`; no lib/problem/ dir,
#              no Go vendor tree (a vendor/ dir holding .go files or modules.txt),
#              and no tracked path names diene.go-errors-problems (vendored source);
#              no root-module Go file declares the errors-problems core types
#              Problem / ErrorPortal or a top-level TypeURI func (a renamed copy).
#   usage    - non-test testhelper/** sources never build a plain error: no
#              errors.New / fmt.Errorf reference (call, value or func alias) and
#              no dot-import of errors or fmt, and no custom error type (an
#              Error method); at least one of them references
#              github.com/AtomiCloud/diene.go-errors-problems/lib/problem.NewError.
# Sources are parsed by go-source.go (stdlib go/parser; no build). The sealed
# tests/fixtures/api-baseline module, probes/lib and the named checks are not read.

src="$(cd "$(dirname "$0")" && pwd)/go-source.go"
cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg=github.com/AtomiCloud/diene.go-errors-problems/lib/problem
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

all="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

# --- absence ---------------------------------------------------------------------------
if grep -qE '^lib/problem/' <<<"${all}"; then fail "lib/problem/ is tracked; errors-problems is consumed from ${pkg%/lib/problem}, never copied"; fi
vendored="$(grep -E '(^|/)vendor/(.*\.go|modules\.txt)$' <<<"${all}" || true)"
[[ -z ${vendored} ]] || fail "a Go vendor tree is tracked:"$'\n'"${vendored}"
copied="$(grep -F 'diene.go-errors-problems' <<<"${all}" || true)"
[[ -z ${copied} ]] || fail "tracked paths carry errors-problems source:"$'\n'"${copied}"

mapfile -t modules < <(grep -E '(^|/)go\.mod$' <<<"${all}" | grep -vx go.mod | sed 's#/go\.mod$##')
mapfile -t gofiles < <(grep -E '\.go$' <<<"${all}" | grep -vE '^(probes/lib|\.github/named-checks)/' || true)
[[ ${#gofiles[@]} -gt 0 ]] || { echo "❌ no Go sources" >&2 && exit 1; }
work="$(mktemp -d)"
git archive "${tree}" -- "${gofiles[@]}" | tar -x -C "${work}"
facts="$(go run "${src}" "${work}" "${gofiles[@]}")" || { echo "❌ go-source.go cannot parse the Go sources (see above)" >&2 && exit 1; }

nested() {
  local m
  for m in "${modules[@]}"; do [[ $1 == "${m}/"* ]] && return 0; done
  return 1
}

while IFS=$'\t' read -r path fact; do
  if [[ ${fact} == "PACKAGE problem" || ${fact} == "PACKAGE problem_test" ]]; then
    fail "${path} declares package ${fact#PACKAGE }; there is no in-repository problem package"
  fi
  nested "${path}" && continue
  case "${fact}" in
  "TYPE Problem" | "TYPE ErrorPortal" | "FUNC TypeURI")
    fail "${path} declares ${fact#* }, an errors-problems core identifier; use ${pkg}"
    ;;
  esac
done <<<"${facts}"

# --- usage -----------------------------------------------------------------------------
uses=0
while IFS=$'\t' read -r path fact; do
  [[ ${path} == testhelper/* && ${path} != *_test.go ]] || continue
  case "${fact}" in
  "REF errors New" | "REF fmt Errorf")
    read -r _ imp name <<<"${fact}"
    fail "${path} builds a plain error with ${imp}.${name}; testhelper failures are problem-typed (${pkg})"
    ;;
  "IMPORT errors ." | "IMPORT fmt .")
    fail "${path} dot-imports ${fact#IMPORT }; testhelper failures are problem-typed (${pkg})"
    ;;
  "METHOD "*" Error")
    fail "${path} declares a custom error type (${fact#METHOD }); testhelper failures are problem-typed (${pkg})"
    ;;
  "REF ${pkg} NewError") uses=1 ;;
  esac
done <<<"${facts}"
[[ ${uses} -eq 1 ]] || fail "no non-test testhelper/** source builds its failures with ${pkg}.NewError"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ problem-typed-errors: no in-repository problem package or vendored errors-problems; testhelper builds its failures with ${pkg}.NewError only"
