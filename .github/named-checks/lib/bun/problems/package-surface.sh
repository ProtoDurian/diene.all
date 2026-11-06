#!/usr/bin/env bash
set -euo pipefail

# The published shape the goal fixes: runtime deps = the published Result and
# core-utils packages plus zod, the root and ./test-helper exports, the usage
# skill in the files allowlist, src/ = index.ts + lib/ + test-helper/ with no
# parent sample, and the parent's empty integration tier kept.

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

[[ "$(q .name)" == "@atomicloud/diene.problems" ]] || fail "package name is $(q .name), not @atomicloud/diene.problems"
deps_want="@atomicloud/diene.core-utils,@atomicloud/diene.result,zod"
[[ "$(q '(.dependencies // {}) | keys | join(",")')" == "${deps_want}" ]] || fail "runtime dependencies must be exactly ${deps_want}, got: $(q '(.dependencies // {}) | keys | join(",")')"
for dep in @atomicloud/diene.core-utils @atomicloud/diene.result; do
  [[ "$(q ".dependencies[\"${dep}\"]")" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "${dep} must pin an exact published version, got $(q ".dependencies[\"${dep}\"]")"
done
# helper-only deps may exist, but only as optional peers
# shellcheck disable=SC2016
non_optional="$(q '. as $m | (($m.peerDependencies // {}) | keys) - (($m.peerDependenciesMeta // {}) | to_entries | map(select(.value.optional == true) | .key)) | join(", ")')"
[[ -z ${non_optional} ]] || fail "non-optional peerDependencies: ${non_optional}"
for field in optionalDependencies bundleDependencies bundledDependencies; do
  [[ "$(q "(.${field} // []) | length")" == 0 ]] || fail "${field} declared"
done
exports_want='{".":{"import":{"types":"./dist/index.d.ts","default":"./dist/index.js"},"require":{"types":"./dist/index.d.cts","default":"./dist/index.cjs"}},"./test-helper":{"import":{"types":"./dist/test-helper.d.ts","default":"./dist/test-helper.js"},"require":{"types":"./dist/test-helper.d.cts","default":"./dist/test-helper.cjs"}}}'
[[ "$(q '.exports' | jq -cS .)" == "$(jq -cS . <<<"${exports_want}")" ]] || fail "exports is not exactly the root and ./test-helper entries, each condition on its own dist file"
[[ "$(q '.typesVersions["*"]["test-helper"] // [] | join(",")')" == ./dist/test-helper.d.ts ]] || fail "typesVersions does not map test-helper to ./dist/test-helper.d.ts (node10 resolution)"
[[ "$(q '.files' | jq -c .)" == '["dist","skills"]' ]] || fail "files allowlist is not exactly [\"dist\",\"skills\"]: $(q '.files' | jq -c .)"
[[ -n "$(git ls-tree --name-only "${tree}" -- skills/diene-problems-usage/SKILL.md)" ]] || fail "skills/diene-problems-usage/SKILL.md is not tracked"
[[ -z "$(git ls-tree -r --name-only "${tree}" -- skills | grep -v '^skills/diene-problems-usage/' || true)" ]] || fail "skills/ ships a skill other than diene-problems-usage"
for p in src/adapters src/lib/sample; do
  [[ -z "$(git ls-tree --name-only "${tree}" -- "${p}")" ]] || fail "path must not be tracked: ${p}"
done
top="$(git ls-tree --name-only "${tree}" -- src/ | LC_ALL=C sort | tr '\n' ' ')"
[[ ${top} == "src/index.ts src/lib src/test-helper " ]] || fail "src/ must hold exactly index.ts, lib/ and test-helper/, got: ${top}"
[[ "$(git show "${tree}:.github/workflows/ci.yaml" | yq '.jobs | has("int")')" == true ]] || fail "ci.yaml dropped the integration tier (kept, empty)"
[[ -n "$(git ls-tree --name-only "${tree}" -- bunfig.int.toml)" ]] || fail "bunfig.int.toml is not tracked (the empty int tier keeps it)"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-surface: deps = result + core-utils (exact) + zod, root + ./test-helper exports, typesVersions, usage skill shipped, src/ = index.ts + lib/ + test-helper/, empty int tier kept"
