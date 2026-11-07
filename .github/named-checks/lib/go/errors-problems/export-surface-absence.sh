#!/usr/bin/env bash
set -euo pipefail

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

fail() {
  echo "❌ $*" >&2
  failed=1
}

show() { git show "${tree}:$1"; }

for p in cmd tests/sit scripts/ci/sit.sh; do
  if grep -qE "^${p}(/|$)" <<<"${files}"; then fail "binary surface still tracked: ${p}"; fi
done

mains="$(git -c core.quotePath=false grep -l -E '^package main([[:space:]]|$)' "${tree}" -- '*.go' ':!*_test.go' ':!probes/lib/**' ':!.github/named-checks/**' || true)"
[[ -z ${mains} ]] || fail "non-test Go sources declare package main:"$'\n'"${mains//${tree}:/}"

if ! grep -qx scripts/local/build.sh <<<"${files}"; then
  fail "scripts/local/build.sh is missing"
else
  build="$(show scripts/local/build.sh | grep -v '^ *#')"
  grep -Eq '(^|[[:space:]])go build([[:space:]].*)?[[:space:]]\./\.\.\.([[:space:]]|$)' <<<"${build}" || fail "scripts/local/build.sh does not build ./..."
  if grep -Eq '(^|[[:space:]])-o([[:space:]=]|$)' <<<"${build}"; then fail "scripts/local/build.sh writes a binary (-o)"; fi
fi

for key in run preview test:sit; do
  [[ "$(show Taskfile.yaml | yq "(.tasks // {} | has(\"${key}\")) or (.includes // {} | has(\"${key}\"))")" == false ]] || fail "Taskfile.yaml still declares ${key}"
done

[[ "$(show .config/go-base.coverage.yaml | yq '.tiers | has("sit")')" == false ]] || fail ".config/go-base.coverage.yaml still declares a sit tier"
[[ "$(show .github/workflows/ci.yaml | yq '[.jobs | to_entries[] | select(.key == "sit" or .value.with.mode == "sit")] | length')" == 0 ]] || fail "ci.yaml still runs a sit tier"
if git grep -q -F scripts/ci/sit.sh "${tree}" -- .github/workflows; then fail "a workflow still runs scripts/ci/sit.sh"; fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ export-surface-absence: no cmd/, package main, -o binary, run/preview task or sit tier"
