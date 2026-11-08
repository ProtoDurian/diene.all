#!/usr/bin/env bash
set -euo pipefail

# The problem type URI `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
# is assembled in exactly ONE non-test Go file, lib/problem/type_uri.go: only
# that file carries a `docs` path segment in a string literal, and its code
# names every segment. Discovery tokenizes every non-test Go source (the sealed
# v1.0.0 API baseline fixture and the named checks excepted), not a list of
# file names.

lex="$(cd "$(dirname "$0")" && pwd)/go-source.go"
cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
want=lib/problem/type_uri.go
mapfile -t files < <(git -c core.quotePath=false ls-tree -r --name-only "${tree}" | grep -E '\.go$' | grep -vE '_test\.go$|^tests/fixtures/api-baseline/|^\.github/named-checks/' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no non-test Go sources" >&2 && exit 1; }
work="$(mktemp -d)"
git archive "${tree}" -- "${files[@]}" | tar -x -C "${work}"
facts="$(go run "${lex}" uri "${work}" "${files[@]}")"

failed=0
mapfile -t builders < <(awk -F '\t' '$2 == "DOCS" { print $1 }' <<<"${facts}")
for path in "${builders[@]}"; do
  for seg in scheme host landscape platform service module version id; do
    grep -qxF "${path}"$'\t'"SEG ${seg}" <<<"${facts}" || {
      echo "❌ ${path}: assembles the type-URI template but never names the ${seg} segment" >&2
      failed=1
    }
  done
  [[ ${path} == "${want}" ]] || { echo "❌ ${path} formats the type-URI template; only ${want} may" >&2 && failed=1; }
done
if [[ ${#builders[@]} -eq 0 ]]; then
  echo "❌ no Go source assembles the type-URI template (no docs path segment in any literal); ${want} must" >&2
  failed=1
elif [[ " ${builders[*]} " != *" ${want} "* ]]; then
  echo "❌ ${want} does not assemble the type-URI template" >&2
  failed=1
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ uri-single-source: the type-URI template is assembled only in ${want}, which names every segment"
