#!/usr/bin/env bash
set -euo pipefail

# The published shape the goal fixes: runtime deps = the published Result and
# core-utils packages plus zod and yaml, exactly the root, /build-time and
# /test-helper exports, the usage skill in the files allowlist, the int tier kept.

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

[[ "$(q .name)" == "@atomicloud/diene.config" ]] || fail "package name is $(q .name), not @atomicloud/diene.config"
deps_want="@atomicloud/diene.core-utils,@atomicloud/diene.result,yaml,zod"
[[ "$(q '(.dependencies // {}) | keys | join(",")')" == "${deps_want}" ]] || fail "runtime dependencies must be exactly ${deps_want}, got: $(q '(.dependencies // {}) | keys | join(",")')"
for dep in @atomicloud/diene.core-utils @atomicloud/diene.result; do
  [[ "$(q ".dependencies[\"${dep}\"]")" =~ ^\^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "${dep} must use a caret range on a published version, got $(q ".dependencies[\"${dep}\"]")"
done
for field in peerDependencies optionalDependencies bundleDependencies bundledDependencies; do
  [[ "$(q "(.${field} // []) | length")" == 0 ]] || fail "${field} declared"
done
entry() { printf '{"import":{"types":"./dist/%s.d.ts","default":"./dist/%s.js"},"require":{"types":"./dist/%s.d.cts","default":"./dist/%s.cjs"}}' "$1" "$1" "$1" "$1"; }
exports_want="{\".\":$(entry index),\"./build-time\":$(entry build-time),\"./test-helper\":$(entry test-helper)}"
[[ "$(q '.exports' | jq -cS .)" == "$(jq -cS . <<<"${exports_want}")" ]] || fail "exports is not exactly ., ./build-time and ./test-helper, each condition on its own dist file"
[[ "$(q '.files' | jq -c .)" == '["dist","skills"]' ]] || fail "files allowlist is not exactly [\"dist\",\"skills\"]: $(q '.files' | jq -c .)"
[[ -n "$(git ls-tree --name-only "${tree}" -- skills/diene-config-usage/SKILL.md)" ]] || fail "skills/diene-config-usage/SKILL.md is not tracked"
[[ -z "$(git ls-tree -r --name-only "${tree}" -- skills | grep -v '^skills/diene-config-usage/' || true)" ]] || fail "skills/ ships a skill other than diene-config-usage"
[[ -z "$(git ls-tree --name-only "${tree}" -- src/lib/sample)" ]] || fail "the parent sample src/lib/sample is still tracked"
[[ -z "$(git ls-tree --name-only "${tree}" -- src/ | grep -v -E '^src/(index\.ts|build-time\.ts|lib|adapters|test-helper)$' || true)" ]] || fail "src/ holds more than index.ts, build-time.ts, lib/, adapters/ and test-helper/"
[[ "$(git show "${tree}:.github/workflows/ci.yaml" | yq '.jobs | has("int")')" == true ]] || fail "ci.yaml dropped the integration tier"
[[ -n "$(git ls-tree -r --name-only "${tree}" -- tests/integration | grep -E '\.test\.ts$' || true)" ]] || fail "no integration test runs the YAML adapter"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-surface: deps = core-utils + result + yaml + zod, exports ., /build-time and /test-helper, usage skill shipped, int tier kept"
