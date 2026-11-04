#!/usr/bin/env bash
set -euo pipefail

# The published shape the goal fixes: zero runtime deps, the /test-helper
# subpath with both conditions, the usage skill in the files allowlist, and no
# sample adapter or integration tier left from the parent.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
manifest="$(git show "${tree}:package.json")"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

q() { jq -r "$1" <<<"${manifest}"; }

[[ "$(q .name)" == "@atomicloud/diene.result" ]] || fail "package name is $(q .name), not @atomicloud/diene.result"
[[ "$(q '(.dependencies // {}) | length')" == 0 ]] || fail "runtime dependencies declared: $(q '.dependencies | keys | join(", ")')"
# shellcheck disable=SC2016
non_optional="$(q '. as $m | (($m.peerDependencies // {}) | keys) - (($m.peerDependenciesMeta // {}) | to_entries | map(select(.value.optional == true) | .key)) | join(", ")')"
[[ -z ${non_optional} ]] || fail "non-optional peerDependencies: ${non_optional}"
for condition in import require; do
  for kind in types default; do
    [[ "$(q ".exports[\"./test-helper\"].${condition}.${kind} // empty")" == ./dist/test-helper.* ]] || fail "exports ./test-helper ${condition}.${kind} missing"
  done
done
[[ "$(q '.files | index("skills") != null')" == true ]] || fail "files allowlist does not ship skills/"
[[ -n "$(git ls-tree --name-only "${tree}" -- skills/diene-result-usage/SKILL.md)" ]] || fail "skills/diene-result-usage/SKILL.md is not tracked"
[[ -z "$(git ls-tree -r --name-only "${tree}" -- skills | grep -v '^skills/diene-result-usage/' || true)" ]] || fail "skills/ ships a skill other than diene-result-usage"
for p in src/adapters src/lib/sample tests/integration; do
  [[ -z "$(git ls-tree --name-only "${tree}" -- "${p}")" ]] || fail "parent sample path still tracked: ${p}"
done
[[ "$(git show "${tree}:.github/workflows/ci.yaml" | yq '.jobs | has("int")')" == false ]] || fail "ci.yaml still runs the integration tier"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-surface: zero runtime deps, /test-helper exported for import and require, usage skill shipped, no sample or integration tier"
