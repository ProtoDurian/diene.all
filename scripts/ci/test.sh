#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage_mode="${2:-no-coverage}"

member_dir="${MEMBER_DIR:-packages/diene_result}"
test_helper_path="${TEST_HELPER_PATH:-lib/test_helper.dart}"
meta_test_path="${META_TEST_PATH:-test/meta}"

[[ ${mode} != "unit" && ${mode} != "meta" && ${mode} != "consumer" ]] && echo "❌ usage: $0 <unit|meta|consumer> [coverage|no-coverage]" >&2 && exit 2
[[ ${coverage_mode} != "coverage" && ${coverage_mode} != "no-coverage" ]] && echo "❌ coverage mode must be coverage or no-coverage" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

[[ ${mode} == "consumer" ]] && exec ./scripts/ci/consumer-test.sh

if [[ ${mode} == "meta" && ! -f "${member_dir}/${test_helper_path}" ]]; then
  echo "✅ Meta tier inactive: this package has no TestHelper"
  exit 0
fi
[[ ${mode} == "meta" && ! -d "${member_dir}/${meta_test_path}" ]] && echo "❌ ${member_dir}/${test_helper_path} ships without its meta suite ${meta_test_path}" >&2 && exit 1

dart pub get

package_config="${root_dir}/.dart_tool/package_config.json"
cd "${root_dir}/${member_dir}"

tests=("${meta_test_path}")
[[ ${mode} == "unit" ]] && tests=(test/unit test/conformance)

if [[ ${coverage_mode} == "no-coverage" ]]; then
  dart test --reporter=expanded "${tests[@]}"
  echo "✅ ${mode} tests passed"
  exit 0
fi

report_dir="${root_dir}/reports/${mode}"
raw_dir="$(mktemp -d)"
trap 'rm -rf "${raw_dir}"' EXIT
all_ledger="${raw_dir}/all.info"
ledger="${report_dir}/lcov.info"
rm -rf "${report_dir}"
mkdir -p "${report_dir}"

set +e
dart test --reporter=expanded --coverage="${raw_dir}" "${tests[@]}"
test_status=$?
set -e

dart run coverage:format_coverage \
  --lcov \
  --in="${raw_dir}" \
  --out="${all_ledger}" \
  --packages="${package_config}" \
  --report-on=lib

pattern="(^|/)${test_helper_path//./[.]}$"
exclude=''
[[ ${mode} == "unit" ]] && pattern='(^|/)lib/.*[.]dart$' && exclude="(^|/)${test_helper_path//./[.]}$"

"${root_dir}/scripts/ci/coverage-ledger.sh" "${all_ledger}" "${ledger}" "${pattern}" "${mode}" "${exclude}"

[[ ${test_status} -ne 0 ]] && echo "❌ ${mode} tests failed (exit ${test_status})" >&2 && exit "${test_status}"
echo "✅ ${mode} coverage artifact: reports/${mode}/lcov.info"
