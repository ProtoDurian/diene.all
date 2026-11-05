#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" && ${mode} != "sit" ]] && echo "❌ usage: $0 <unit|int|sit>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

bun install --frozen-lockfile

# sit runs the compiled binary, so it has no coverage ledger to scope.
if [[ ${mode} == "sit" ]]; then
  if [[ -d dist/bin ]]; then chmod -R +x dist/bin; fi
  if [[ -n ${CLI_BIN:-} ]]; then chmod +x "${CLI_BIN}"; fi
  echo "🧪 Running sit tests..."
  bun test --config=bunfig.sit.toml
  echo "✅ sit tests passed"
  exit 0
fi

config="bunfig.${mode}.toml"
report_dir="reports/unit"
scope="src/lib/"
[[ ${mode} == "int" ]] && report_dir="reports/integration" && scope="src/adapters/"
coverage_file="${report_dir}/lcov.info"

echo "🧪 Running ${mode} tests with coverage..."
rm -rf "${report_dir}"

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

echo "✅ ${mode} tests passed; coverage is complete and scoped to ${scope}: ${coverage_file}"
