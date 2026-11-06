#!/usr/bin/env bash
set -euo pipefail

tier="${1:-}"

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

tiers=".config/bun-base.coverage.yaml"
[[ -n ${tier} && "$(yq ".tiers | has(\"${tier}\")" "${tiers}")" == "true" ]] || {
  echo "❌ usage: $0 <$(yq '.tiers | keys | join("|")' "${tiers}")>" >&2
  exit 2
}
tests="$(yq ".tiers.${tier}.tests // \"\"" "${tiers}")"
scope="$(yq ".tiers.${tier}.scope // \"\"" "${tiers}")"
[[ -z ${tests} ]] && echo "❌ ${tiers} gives tier ${tier} no tests folder" >&2 && exit 2

config="bunfig.${tier}.toml"
report_dir="reports/${tier}"
[[ ${tier} == "int" ]] && report_dir="reports/integration"
coverage_file="${report_dir}/lcov.info"
rm -rf "${report_dir}"

# Same file names bun test discovers.
if [[ -z "$(rg --files -g '*{.test,_test,.spec,_spec}.{ts,tsx,js,jsx}' "${tests}" 2>/dev/null || true)" ]]; then
  echo "✅ ${tier} tier has no test files under ${tests}; nothing to run"
  exit 0
fi
[[ -f ${config} ]] || { echo "❌ ${tier} tier has tests but no ${config}" >&2 && exit 1; }

bun install --frozen-lockfile

if [[ -z ${scope} ]]; then
  echo "🧪 Running ${tier} tests..."
  bun test --config="${config}"
  echo "✅ ${tier} tests passed"
  exit 0
fi

echo "🧪 Running ${tier} tests with coverage..."

bun test --config="${config}" --coverage

# rg exits 2 on a missing file, so absence needs its own refusal.
[[ -f ${coverage_file} ]] || {
  echo "❌ no coverage artifact at ${coverage_file}" >&2
  exit 1
}
sources="$(rg -N --replace '' '^SF:' "${coverage_file}" || true)"
[[ -z ${sources} ]] && echo "❌ coverage ledger at ${coverage_file} names no source file" >&2 && exit 1
outside="$(printf '%s\n' "${sources}" | rg -v "(^|/)${scope}" || true)"
[[ -n ${outside} ]] && echo "❌ coverage path outside ${scope}: ${outside}" >&2 && exit 1

echo "✅ ${tier} tests passed; coverage is complete and scoped to ${scope}: ${coverage_file}"
