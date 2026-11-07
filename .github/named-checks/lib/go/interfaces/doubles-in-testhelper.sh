#!/usr/bin/env bash
set -euo pipefail

# Every in-memory double / mock of the effect ports lives under testhelper/**
# only, and lib/** stays implementation-free:
#   - The port method set is read from the interface types that non-test lib/**
#     sources declare (plus Environment, ReadBytes, Run and Emit, so a renamed or
#     deleted port cannot empty the set).
#   - No Go file of the root module outside testhelper/** declares a method of
#     that set, on any receiver: not a non-test file anywhere, not a test in
#     lib/** or tests/unit/**. Only tests/meta/** *_test.go may: the meta tier's
#     contract-parity suite runs real OS-backed adapters and known-bad doubles
#     against the testhelper contract (lead ruling, fix round 1).
#   - Non-test lib/** sources import only the standard library (no dot in the
#     import path's first element) and never testhelper. lib/** *_test.go
#     (external package examples) may import testhelper.
# Sources are parsed by go-source.go (stdlib go/parser; no build). Nested modules
# (the sealed tests/fixtures/api-baseline stubs), probes/lib and the named checks
# are not the module's code and are not read.

src="$(cd "$(dirname "$0")" && pwd)/go-source.go"
cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

all="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"
mapfile -t modules < <(grep -E '(^|/)go\.mod$' <<<"${all}" | grep -vx go.mod | sed 's#/go\.mod$##')
mapfile -t files < <(grep -E '\.go$' <<<"${all}" | grep -vE '^(probes/lib|\.github/named-checks)/' | while read -r f; do
  nested=0
  for m in "${modules[@]}"; do [[ ${f} == "${m}/"* ]] && nested=1; done
  [[ ${nested} -eq 0 ]] && echo "${f}"
done)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no Go sources in the root module" >&2 && exit 1; }
work="$(mktemp -d)"
git archive "${tree}" -- "${files[@]}" | tar -x -C "${work}"
facts="$(go run "${src}" "${work}" "${files[@]}")" || { echo "❌ go-source.go cannot parse the Go sources (see above)" >&2 && exit 1; }

is_test() { [[ $1 == *_test.go ]]; }

mapfile -t ports < <({
  awk -F '\t' '$1 ~ /^lib\// && $1 !~ /_test\.go$/ && $2 ~ /^IFACE / { split($2, a, " "); print a[3] }' <<<"${facts}"
  printf '%s\n' Environment ReadBytes Run Emit
} | LC_ALL=C sort -u)
[[ $(awk -F '\t' '$1 ~ /^lib\// && $2 ~ /^IFACE /' <<<"${facts}" | wc -l) -gt 0 ]] || fail "no lib/** source declares a port interface"

declare -A port=()
for m in "${ports[@]}"; do port[${m}]=1; done

while IFS=$'\t' read -r path fact; do
  [[ ${fact} == METHOD\ * ]] || continue
  read -r _ recv name <<<"${fact}"
  [[ -n ${port[${name}]:-} ]] || continue
  [[ ${path} == testhelper/* ]] && continue
  [[ ${path} == tests/meta/* ]] && is_test "${path}" && continue
  fail "${path}: (${recv}).${name} implements a port method outside testhelper/**; doubles live in testhelper only"
done <<<"${facts}"

while IFS=$'\t' read -r path fact; do
  [[ ${fact} == IMPORT\ * && ${path} == lib/* ]] || continue
  is_test "${path}" && continue
  read -r _ imp _ <<<"${fact}"
  if [[ ${imp} == */testhelper || ${imp} == */testhelper/* ]]; then
    fail "${path} imports ${imp}; non-test lib/** never imports testhelper"
  elif [[ ${imp%%/*} == *.* ]]; then
    fail "${path} imports ${imp}; non-test lib/** sources import the standard library only"
  fi
done <<<"${facts}"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ doubles-in-testhelper: port methods ($(paste -sd, < <(printf '%s\n' "${ports[@]}"))) are implemented only under testhelper/** (and tests/meta contract tests); non-test lib/** imports the standard library only"
