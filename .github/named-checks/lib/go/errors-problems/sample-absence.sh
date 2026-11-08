#!/usr/bin/env bash
set -euo pipefail

# The parent's illustrative sample is gone: no note domain, KV adapters, Redis
# integration tests or in-memory store; go.mod requires nothing (the library has
# no non-stdlib runtime dependency); the module's packages are exactly
# lib/problem and testhelper, plus any internal/ package. A package is a
# directory with a non-test .go file that belongs to the root module (nested
# modules such as the API baseline fixture are their own).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

fail() {
  echo "❌ $*" >&2
  failed=1
}

for p in lib/note adapters tests/int/kv testhelper/memory_store.go; do
  if grep -qE "^${p}(/|$)" <<<"${files}"; then fail "parent sample still tracked: ${p}"; fi
done

gomod="$(git show "${tree}:go.mod" | sed -e 's#//.*##')"
if grep -qE '^[[:space:]]*require([[:space:](]|$)' <<<"${gomod}"; then
  fail "go.mod declares a require; the library has no non-stdlib dependency:"$'\n'"$(grep -nE 'require|^[[:space:]]+[a-z]' <<<"${gomod}")"
fi
for f in go.mod go.sum; do
  grep -qx "${f}" <<<"${files}" || continue
  if git show "${tree}:${f}" | grep -nEi 'redis|testcontainers'; then fail "${f} still names redis/testcontainers"; fi
done

mapfile -t modules < <(grep -E '(^|/)go\.mod$' <<<"${files}" | grep -vx go.mod | sed 's#/go\.mod$##')
pkgs="$(grep -E '\.go$' <<<"${files}" | grep -vE '_test\.go$' | while read -r f; do
  d="$(dirname "${f}")"
  nested=0
  for m in "${modules[@]}"; do [[ ${d} == "${m}" || ${d} == "${m}/"* ]] && nested=1; done
  [[ ${nested} -eq 1 ]] && continue
  [[ ${d} != . ]] && grep -qE '(^|/)(testdata|[._][^/]*)(/|$)' <<<"${d}" && continue
  echo "${d}"
done | sort -u)"
for d in ${pkgs}; do
  case "${d}" in
  lib/problem | testhelper | internal | internal/* | */internal | */internal/*) ;;
  *) fail "unexpected package ${d}; the module's packages are lib/problem and testhelper (plus internal/)" ;;
  esac
done
for d in lib/problem testhelper; do
  grep -qx "${d}" <<<"${pkgs}" || fail "package ${d} is missing"
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ sample-absence: no parent sample, go.mod requires nothing, packages are $(paste -sd, <<<"${pkgs}")"
