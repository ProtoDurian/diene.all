#!/usr/bin/env bash
set -euo pipefail

# The published shape the goal fixes: one runtime dep (the published Result
# package), the /test-helper subpath with both conditions, the usage skill in
# the files allowlist, and no sample adapter or integration tier from the parent.

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

[[ "$(q .name)" == "@atomicloud/diene.interfaces" ]] || fail "package name is $(q .name), not @atomicloud/diene.interfaces"
[[ "$(q '(.dependencies // {}) | keys | join(",")')" == "@atomicloud/diene.result" ]] || fail "runtime dependencies must be exactly @atomicloud/diene.result, got: $(q '(.dependencies // {}) | keys | join(", ")')"
# shellcheck disable=SC2016
non_optional="$(q '. as $m | (($m.peerDependencies // {}) | keys) - (($m.peerDependenciesMeta // {}) | to_entries | map(select(.value.optional == true) | .key)) | join(", ")')"
[[ -z ${non_optional} ]] || fail "non-optional peerDependencies: ${non_optional}"
for field in optionalDependencies bundleDependencies bundledDependencies; do
  [[ "$(q "(.${field} // []) | length")" == 0 ]] || fail "${field} declared: $(q ".${field} | if type == \"object\" then keys else . end | join(\", \")")"
done
exports_want='{".":{"import":{"types":"./dist/index.d.ts","default":"./dist/index.js"},"require":{"types":"./dist/index.d.cts","default":"./dist/index.cjs"}},"./test-helper":{"import":{"types":"./dist/test-helper.d.ts","default":"./dist/test-helper.js"},"require":{"types":"./dist/test-helper.d.cts","default":"./dist/test-helper.cjs"}}}'
[[ "$(q '.exports' | jq -cS .)" == "$(jq -cS . <<<"${exports_want}")" ]] || fail "exports is not exactly the root and ./test-helper entries, each condition on its own dist file"
[[ "$(q '.files' | jq -c .)" == '["dist","skills"]' ]] || fail "files allowlist is not exactly [\"dist\",\"skills\"]: $(q '.files' | jq -c .)"
[[ "$(q '.typesVersions["*"]["test-helper"] // [] | join(",")')" == ./dist/test-helper.d.ts ]] || fail "typesVersions does not map test-helper to ./dist/test-helper.d.ts (node10 resolution)"
[[ -n "$(git ls-tree --name-only "${tree}" -- skills/diene-interfaces-usage/SKILL.md)" ]] || fail "skills/diene-interfaces-usage/SKILL.md is not tracked"
[[ -z "$(git ls-tree -r --name-only "${tree}" -- skills | grep -v '^skills/diene-interfaces-usage/' || true)" ]] || fail "skills/ ships a skill other than diene-interfaces-usage"
for p in src/adapters src/lib/sample tests/integration; do
  [[ -z "$(git ls-tree --name-only "${tree}" -- "${p}")" ]] || fail "parent sample path still tracked: ${p}"
done
[[ "$(git show "${tree}:.github/workflows/ci.yaml" | yq '.jobs | has("int")')" == false ]] || fail "ci.yaml still runs the integration tier"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-surface: runtime deps = @atomicloud/diene.result only, exact exports/files/typesVersions, usage skill shipped, no sample or integration tier"
