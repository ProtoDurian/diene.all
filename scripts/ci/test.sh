#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" && ${mode} != "e2e" ]] && echo "❌ usage: $0 <unit|int|e2e>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

bun install --frozen-lockfile

config="bunfig.${mode}.toml"
report_dir="reports/unit"
scope="src/lib/"
[[ ${mode} == "int" ]] && report_dir="reports/integration" && scope="src/adapters/"
[[ ${mode} == "e2e" ]] && report_dir="reports/e2e" && scope=""
coverage_file="${report_dir}/lcov.info"

echo "🧪 Running ${mode} tests with coverage..."
rm -rf "${report_dir}"

bun test --config="${config}" --coverage

# rg exits 2 on a missing file, so absence needs its own refusal.
[[ -f ${coverage_file} ]] || {
  echo "❌ no coverage artifact at ${coverage_file}" >&2
  exit 1
}
[[ -z ${scope} ]] && echo "✅ e2e tests passed; ledger at ${coverage_file}" && exit 0

sources="$(rg -N --replace '' '^SF:' "${coverage_file}" || true)"
[[ -z ${sources} ]] && echo "❌ coverage ledger at ${coverage_file} names no source file" >&2 && exit 1
outside="$(printf '%s\n' "${sources}" | rg -v "(^|/)${scope}" || true)"
[[ -n ${outside} ]] && echo "❌ coverage path outside ${scope}: ${outside}" >&2 && exit 1

echo "✅ ${mode} tests passed; coverage is complete and scoped to ${scope}: ${coverage_file}"
