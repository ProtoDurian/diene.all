#!/usr/bin/env bash
set -euo pipefail

config="${1:-}"
coverage_mode="${2:-}"
[ -z "${config}" ] && echo "❌ usage: $0 <bunfig-int-config> [coverage]" >&2 && exit 2
[[ -n ${coverage_mode} && ${coverage_mode} != "coverage" ]] && echo "❌ optional mode must be 'coverage'" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

[[ ${coverage_mode} == "coverage" ]] && rm -rf reports/integration

adapter_source="$(find src/adapters -type f -name '*.ts' -print -quit 2>/dev/null || true)"
int_test="$(find tests/integration -type f -name '*.test.ts' -print -quit 2>/dev/null || true)"
[[ -z ${adapter_source} && -z ${int_test} ]] && echo "⏭️ No adapters or integration tests exist; integration tier is a successful no-op" && exit 0
[[ -z ${adapter_source} || -z ${int_test} ]] && echo "❌ adapter source and integration tests must be added together" >&2 && exit 1

[[ ${coverage_mode} == "coverage" ]] && bun test --config="${config}" --coverage
[[ -z ${coverage_mode} ]] && bun test --config="${config}"

echo "✅ Integration tests passed"
