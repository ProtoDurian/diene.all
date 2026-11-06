#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" && ${mode} != "meta" ]] && echo "❌ usage: $0 <unit|int|meta>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

bun install --frozen-lockfile

config="bunfig.${mode}.toml"
report_dir="reports/unit"
scope="src/lib/"
[[ ${mode} == "int" ]] && report_dir="reports/integration" && scope="src/adapters/"
[[ ${mode} == "meta" ]] && report_dir="reports/meta" && scope="src/test-helper/"
coverage_file="${report_dir}/lcov.info"

echo "🧪 Running ${mode} tests with coverage..."
rm -rf "${report_dir}"

if [[ ${mode} == "unit" ]]; then
  bun test --config="${config}" --coverage
elif [[ ${mode} == "meta" ]]; then
  ./scripts/local/test-meta.sh "${config}" coverage
  # Without a TestHelper the meta tier is a successful no-op: there is no ledger to check.
  [[ -z "$(find src/test-helper -type f -name "*.ts" -print -quit 2>/dev/null || true)" ]] && exit 0
else
  ./scripts/local/test-int.sh "${config}" coverage
  # Without adapters or integration tests the int tier is a successful no-op (A121).
  [[ -z "$(find src/adapters -type f -name "*.ts" -print -quit 2>/dev/null || true)" && -z "$(find tests/integration -type f -name "*.test.ts" -print -quit 2>/dev/null || true)" ]] && exit 0
fi

# rg exits 2 on a missing file, so absence needs its own refusal.
[[ -f ${coverage_file} ]] || {
  echo "❌ no coverage artifact at ${coverage_file}" >&2
  exit 1
}
sources="$(rg -N --replace '' '^SF:' "${coverage_file}" || true)"
[[ -z ${sources} ]] && echo "❌ coverage ledger at ${coverage_file} names no source file" >&2 && exit 1
outside="$(printf '%s\n' "${sources}" | rg -v "(^|/)${scope}" || true)"
[[ -n ${outside} ]] && echo "❌ coverage path outside ${scope}: ${outside}" >&2 && exit 1

echo "✅ ${mode} tests passed; coverage is complete and scoped to ${scope}: ${coverage_file}"
