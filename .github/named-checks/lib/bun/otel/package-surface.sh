#!/usr/bin/env bash
set -euo pipefail

# The published shape: runtime deps = the published Result, interfaces and
# core-utils packages (caret ranges, resolved from the registry), zod, pino and
# @opentelemetry/* with OTLP http/protobuf exporters only; exactly the root and
# /test-helper exports; the usage skill shipped; the int, meta and SIT tiers kept.

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

[[ "$(q .name)" == "@atomicloud/diene.otel" ]] || fail "package name is $(q .name), not @atomicloud/diene.otel"

diene="@atomicloud/diene.core-utils @atomicloud/diene.interfaces @atomicloud/diene.result"
for dep in ${diene} @opentelemetry/exporter-metrics-otlp-proto @opentelemetry/exporter-trace-otlp-proto pino zod; do
  [[ "$(q "(.dependencies // {}) | has(\"${dep}\")")" == true ]] || fail "runtime dependency ${dep} is missing"
done
extra="$(q '(.dependencies // {}) | keys[] | select(test("^(@atomicloud/diene\\.(core-utils|interfaces|result)|@opentelemetry/[a-z0-9-]+|pino|zod)$") | not)' | paste -sd, -)"
[[ -z ${extra} ]] || fail "runtime dependencies outside result, interfaces, core-utils, zod, pino and @opentelemetry/*: ${extra}"
foreign="$(q '(.dependencies // {}) | keys[] | select(test("^@opentelemetry/(exporter-|sdk-logs$)") and (test("^@opentelemetry/exporter-(metrics|trace)-otlp-proto$") | not))' | paste -sd, -)"
[[ -z ${foreign} ]] || fail "only the OTLP http/protobuf metrics and trace exporters may ship (no gRPC, JSON or OTLP logs): ${foreign}"
lock="$(git show "${tree}:bun.lock" 2>/dev/null)" || fail "bun.lock is not tracked"
for dep in ${diene}; do
  [[ "$(q ".dependencies[\"${dep}\"]")" =~ ^\^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "${dep} must use a caret range on a published version, got $(q ".dependencies[\"${dep}\"]")"
  grep -qE "^    \"${dep}\": \[\"${dep}@[0-9]+\.[0-9]+\.[0-9]+\", \"\", .*\"sha512-[^\"]+\"\],\$" <<<"${lock:-}" || fail "bun.lock does not resolve ${dep} to a registry release"
done
for field in optionalDependencies bundleDependencies bundledDependencies; do
  [[ "$(q "(.${field} // []) | length")" == 0 ]] || fail "${field} declared"
done
# shellcheck disable=SC2016
required="$(q '(.peerDependencies // {}) as $p | (.peerDependenciesMeta // {}) as $m | $p | keys[] | select($m[.].optional != true)' | paste -sd, -)"
[[ -z ${required} ]] || fail "peer dependencies must be optional (helper-only): ${required}"

entry() { printf '{"import":{"types":"./dist/%s.d.ts","default":"./dist/%s.js"},"require":{"types":"./dist/%s.d.cts","default":"./dist/%s.cjs"}}' "$1" "$1" "$1" "$1"; }
exports_want="{\".\":$(entry index),\"./test-helper\":$(entry test-helper)}"
[[ "$(q '.exports' | jq -cS .)" == "$(jq -cS . <<<"${exports_want}")" ]] || fail "exports is not exactly . and ./test-helper, each condition on its own dist file"
[[ "$(q '.files' | jq -c .)" == '["dist","skills"]' ]] || fail "files allowlist is not exactly [\"dist\",\"skills\"]: $(q '.files' | jq -c .)"
[[ -n "$(git ls-tree --name-only "${tree}" -- skills/diene-otel-usage/SKILL.md)" ]] || fail "skills/diene-otel-usage/SKILL.md is not tracked"
[[ -z "$(git ls-tree -r --name-only "${tree}" -- skills | grep -v '^skills/diene-otel-usage/' || true)" ]] || fail "skills/ ships a skill other than diene-otel-usage"
[[ -z "$(git ls-tree --name-only "${tree}" -- src/lib/sample)" ]] || fail "the parent sample src/lib/sample is still tracked"
[[ -z "$(git ls-tree --name-only "${tree}" -- src/ | grep -v -E '^src/(index\.ts|lib|adapters|test-helper)$' || true)" ]] || fail "src/ holds more than index.ts, lib/, adapters/ and test-helper/"

ci="$(git show "${tree}:.github/workflows/ci.yaml")"
for tier in int:tests/integration meta:tests/meta sit:tests/sit; do
  job="${tier%%:*}"
  dir="${tier#*:}"
  [[ "$(yq ".jobs | has(\"${job}\")" <<<"${ci}")" == true ]] || fail "ci.yaml has no ${job} job"
  [[ -n "$(git ls-tree -r --name-only "${tree}" -- "${dir}" | grep -E '\.test\.ts$' || true)" ]] || fail "no ${dir} test runs"
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-surface: deps = result + interfaces + core-utils (caret, registry) + zod + pino + @opentelemetry/* (OTLP http/protobuf), exports . and /test-helper, usage skill shipped, int/meta/sit tiers kept"
