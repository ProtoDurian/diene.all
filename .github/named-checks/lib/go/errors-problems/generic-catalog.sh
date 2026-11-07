#!/usr/bin/env bash
set -euo pipefail

# The generic catalog's wire ids are snake_case: one non-test lib/ Go file
# declares all six (validation_error, entity_not_found, conflict,
# unauthenticated, unauthorized, invalid_json) as string literals, and its
# `ID:` / `"id":` literals are exactly those six, each once. Status, recoverable
# flag and data schema per id are proven by the unit tier, which runs the real
# values. The retired and kebab spellings appear in no tracked file outside the
# sealed v1.0.0 API baseline fixture, and no Go source declares or uses an
# exported DomainException identifier: services declare their own problems.

lex="$(cd "$(dirname "$0")" && pwd)/go-source.go"
cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
want="conflict entity_not_found invalid_json unauthenticated unauthorized validation_error"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

all="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"
mapfile -t libs < <(grep -E '^lib/.*\.go$' <<<"${all}" | grep -vE '_test\.go$' || true)
mapfile -t gos < <(grep -E '\.go(\.txt)?$' <<<"${all}" | grep -v '^\.github/named-checks/' || true)
[[ ${#libs[@]} -gt 0 ]] || { echo "❌ no non-test Go sources under lib/" >&2 && exit 1; }
work="$(mktemp -d)"
git archive "${tree}" -- "${gos[@]}" | tar -x -C "${work}"
facts="$(go run "${lex}" ids "${work}" "${libs[@]}")"

sources=()
for path in "${libs[@]}"; do
  has=1
  for id in ${want}; do grep -qxF "${path}"$'\t'"STR ${id}" <<<"${facts}" || has=0; done
  [[ ${has} -eq 1 ]] && sources+=("${path}")
done

if [[ ${#sources[@]} -eq 0 ]]; then
  for id in ${want}; do
    grep -qE $'\t'"STR ${id}\$" <<<"${facts}" || fail "no lib/ Go source declares wire id ${id}"
  done
  fail "no single lib/ Go source declares all six generic wire ids (${want})"
elif [[ ${#sources[@]} -gt 1 ]]; then
  for path in "${sources[@]}"; do fail "${path} declares all six generic wire ids; the generic catalog must have one source"; done
else
  catalog="${sources[0]}"
  ids="$(awk -F '\t' -v p="${catalog}" '$1 == p && $2 ~ /^ID / { print substr($2, 4) }' <<<"${facts}")"
  if [[ -n ${ids} ]]; then
    while read -r dup; do [[ -n ${dup} ]] && fail "${catalog}: duplicate id ${dup}"; done <<<"$(sort <<<"${ids}" | uniq -d)"
    have="$(sort -u <<<"${ids}" | tr '\n' ' ')"
    for id in ${want}; do [[ " ${have} " == *" ${id} "* ]] || fail "${catalog}: missing id ${id}"; done
    for id in ${have}; do [[ " ${want} " == *" ${id} "* ]] || fail "${catalog}: extra id ${id}"; done
  fi
fi

# spelled split so this file never matches itself
retired=("entity""_conflict" "entity""-not-found" "validation""-error" "invalid""-json")
args=()
for t in "${retired[@]}"; do args+=(-e "${t}"); done
rc=0
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . ':!tests/fixtures/api-baseline/**')" || rc=$?
[[ ${rc} -le 1 ]] || fail "git grep failed (exit ${rc})"
[[ -z ${hits} ]] || fail "retired or kebab wire ids appear (${retired[*]}):"$'\n'"${hits//${tree}:/}"

while read -r path; do
  [[ -n ${path} ]] && fail "${path}: declares or uses an exported DomainException identifier; there is no catch-all domain exception"
done < <(go run "${lex}" idents "${work}" "${gos[@]}" | awk -F '\t' '$2 ~ /^IDENT .*DomainException/ { print $1 }' | sort -u)

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ generic-catalog: ${catalog} declares exactly the six generic wire ids (${want}); no retired/kebab id or DomainException"
