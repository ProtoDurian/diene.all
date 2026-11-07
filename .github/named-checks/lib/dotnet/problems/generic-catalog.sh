#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

builder=Lib/ProblemCatalogBuilder.cs
[[ -f ${builder} ]] || { echo "❌ ${builder} is missing" >&2 && exit 1; }

# id status recoverable; the extras are dotnet-only and optional
want="conflict 409 true
entity_not_found 404 false
invalid_json 400 true
unauthenticated 401 true
unauthorized 403 false
validation_error 400 true"
extras="entity_conflict 409 true
multiple_entity_not_found 404 false"

baseline="$(awk '/AddBaseline\(\) =>/ { on = 1 } on { print } on && /;[[:space:]]*$/ { exit }' "${builder}")"
[[ -n ${baseline} ]] || { echo "❌ ${builder} declares no AddBaseline() expression" >&2 && exit 1; }

rows=""
while read -r type status recoverable; do
  file="Lib/Catalog/${type}.cs"
  [[ -f ${file} ]] || { fail "AddBaseline registers ${type}, but ${file} is missing" && continue; }
  id="$(sed -nE 's/.*string Id => "([^"]+)";.*/\1/p' "${file}" | head -n 1)"
  [[ -n ${id} ]] || { fail "${file} declares no literal Id" && continue; }
  rows+="${id} ${status} ${recoverable}"$'\n'
  if [[ ${id} == entity_not_found || ${id} == conflict ]]; then
    grep -q 'public string EntityType' "${file}" || fail "${id}: data has no entityType"
    grep -q '\[JsonPropertyName("id")\]' "${file}" || fail "${id}: data has no id"
  fi
done < <(grep -oE 'Add<[A-Za-z]+>\([0-9]+, (true|false)' <<<"${baseline}" | sed -E 's/Add<([A-Za-z]+)>\(([0-9]+), (true|false)/\1 \2 \3/')

rows="$(sed '/^$/d' <<<"${rows}" | LC_ALL=C sort)"
generic="$(grep -vxF -f <(printf '%s\n' "${extras}") <<<"${rows}" || true)"
[[ ${generic} == "${want}" ]] || fail "AddBaseline generics differ from the contract:"$'\n'"$(diff <(printf '%s\n' "${want}") <(printf '%s\n' "${generic}") || true)"
[[ "$(cut -d' ' -f1 <<<"${rows}" | uniq -d)" == "" ]] || fail "AddBaseline registers an id twice"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ generic-catalog: AddBaseline registers the six generic ids with their status and recoverable flags; conflict and entity_not_found carry {entityType, id}"
