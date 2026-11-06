#!/usr/bin/env bash
set -euo pipefail

# The published shape the goal fixes: runtime deps = the published Result and
# interfaces packages plus the Temporal polyfill, the root export only, the usage
# skill in the files allowlist, no filesystem module, and the parent's empty
# integration tier kept (A121).

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

[[ "$(q .name)" == "@atomicloud/diene.core-utils" ]] || fail "package name is $(q .name), not @atomicloud/diene.core-utils"
deps_want="@atomicloud/diene.interfaces,@atomicloud/diene.result,@js-temporal/polyfill"
[[ "$(q '(.dependencies // {}) | keys | join(",")')" == "${deps_want}" ]] || fail "runtime dependencies must be exactly ${deps_want}, got: $(q '(.dependencies // {}) | keys | join(",")')"
for dep in @atomicloud/diene.interfaces @atomicloud/diene.result; do
  [[ "$(q ".dependencies[\"${dep}\"]")" =~ ^\^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "${dep} must use a caret range, got $(q ".dependencies[\"${dep}\"]")"
done
for field in peerDependencies optionalDependencies bundleDependencies bundledDependencies; do
  [[ "$(q "(.${field} // []) | length")" == 0 ]] || fail "${field} declared"
done
exports_want='{".":{"import":{"types":"./dist/index.d.ts","default":"./dist/index.js"},"require":{"types":"./dist/index.d.cts","default":"./dist/index.cjs"}}}'
[[ "$(q '.exports' | jq -cS .)" == "$(jq -cS . <<<"${exports_want}")" ]] || fail "exports is not exactly the root entry, each condition on its own dist file"
[[ "$(q '.files' | jq -c .)" == '["dist","skills"]' ]] || fail "files allowlist is not exactly [\"dist\",\"skills\"]: $(q '.files' | jq -c .)"
[[ -n "$(git ls-tree --name-only "${tree}" -- skills/diene-core-utils-usage/SKILL.md)" ]] || fail "skills/diene-core-utils-usage/SKILL.md is not tracked"
[[ -z "$(git ls-tree -r --name-only "${tree}" -- skills | grep -v '^skills/diene-core-utils-usage/' || true)" ]] || fail "skills/ ships a skill other than diene-core-utils-usage"
for p in src/adapters src/lib/sample src/test-helper src/fs.ts src/lib/fs.ts; do
  [[ -z "$(git ls-tree --name-only "${tree}" -- "${p}")" ]] || fail "path must not be tracked: ${p}"
done
[[ -z "$(git ls-tree --name-only "${tree}" -- src/ | grep -v -e '^src/index.ts$' -e '^src/lib$' || true)" ]] || fail "src/ holds more than index.ts and lib/"
[[ "$(git show "${tree}:.github/workflows/ci.yaml" | yq '.jobs | has("int")')" == true ]] || fail "ci.yaml dropped the integration tier (A121 keeps it, empty)"
[[ -n "$(git ls-tree --name-only "${tree}" -- bunfig.int.toml)" ]] || fail "bunfig.int.toml is not tracked (A121 keeps it)"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-surface: deps = interfaces + result + Temporal polyfill, root export only, usage skill shipped, no fs module, empty int tier kept"
