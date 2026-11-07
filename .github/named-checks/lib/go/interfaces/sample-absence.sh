#!/usr/bin/env bash
set -euo pipefail

# The parent's illustrative sample is gone: no note domain, KV adapters, Redis
# integration tests or in-memory store; go.mod requires exactly one module, the
# published github.com/AtomiCloud/diene.go-errors-problems, and replaces nothing;
# the module's packages are exactly lib/interfaces and testhelper, plus any
# internal/ package. A package is a directory with a non-test .go file that
# belongs to the root module (nested modules such as the API baseline fixture are
# their own). go.mod is parsed by `go mod edit -json` (offline, no build).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
work="$(mktemp -d)"
failed=0
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"
dep=github.com/AtomiCloud/diene.go-errors-problems

fail() {
  echo "❌ $*" >&2
  failed=1
}

for p in lib/note adapters tests/int/kv testhelper/memory_store.go; do
  if grep -qE "^${p}(/|$)" <<<"${files}"; then fail "parent sample still tracked: ${p}"; fi
done

git show "${tree}:go.mod" >"${work}/go.mod"
if ! go mod edit -json "${work}/go.mod" >"${work}/go.mod.json" 2>"${work}/go.mod.err"; then
  fail "go.mod does not parse: $(head -3 "${work}/go.mod.err")"
else
  requires="$(jq -r '[.Require // [] | .[].Path] | join(",")' "${work}/go.mod.json")"
  [[ ${requires} == "${dep}" ]] || fail "go.mod must require exactly ${dep}; it requires [${requires}]"
  replaces="$(jq -r '[.Replace // [] | .[] | .Old.Path + " => " + .New.Path] | join(", ")' "${work}/go.mod.json")"
  [[ -z ${replaces} ]] || fail "go.mod carries a replace directive: ${replaces}"
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
  lib/interfaces | testhelper | internal | internal/* | */internal | */internal/*) ;;
  *) fail "unexpected package ${d}; the module's packages are lib/interfaces and testhelper (plus internal/)" ;;
  esac
done
for d in lib/interfaces testhelper; do
  grep -qx "${d}" <<<"${pkgs}" || fail "package ${d} is missing"
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ sample-absence: no parent sample, go.mod requires only ${dep} and replaces nothing, packages are $(paste -sd, <<<"${pkgs}")"
