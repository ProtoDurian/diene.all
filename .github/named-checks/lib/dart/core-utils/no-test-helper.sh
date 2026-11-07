#!/usr/bin/env bash
set -euo pipefail

# TestHelper verdict NO: no helper library, no meta suite, no helper package,
# no test framework in the runtime graph, and the meta tier no-ops.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
pkg="packages/diene_core_utils"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

mapfile -t pkg_files < <(git ls-tree -r --name-only "${tree}" -- "${pkg}/")
[[ " ${pkg_files[*]} " == *" ${pkg}/lib/diene_core_utils.dart "* ]] || fail "control: ${pkg}/lib/diene_core_utils.dart is missing"

hits="$(printf '%s\n' "${pkg_files[@]}" | grep -E "^${pkg}/(lib/.*test_helper[^/]*\.dart|test/meta/.+)$" || true)"
[[ -z ${hits} ]] || fail "TestHelper is NO, yet the package ships helper or meta files:"$'\n'"${hits}"

members="$(git show "${tree}:pubspec.yaml" | yq -o=json -I=0 '.workspace // []')"
[[ ${members} == "[\"${pkg}\"]" ]] || fail "workspace members are ${members}; a separate helper package is not allowed"
others="$(git ls-tree -d --name-only "${tree}" packages/ | grep -vx "${pkg}" || true)"
[[ -z ${others} ]] || fail "packages/ holds more than ${pkg}:"$'\n'"${others}"

runtime="$(git show "${tree}:${pkg}/pubspec.yaml" | yq '.dependencies // {} | keys | .[]')"
bad="$(grep -xE 'test|test_api|test_core|matcher|checks|mocktail|mockito|fake_async' <<<"${runtime}" || true)"
[[ -z ${bad} ]] || fail "test framework packages are runtime dependencies: $(paste -sd ' ' <<<"${bad}")"

# with a helper present test.sh would run the meta suite; the file checks above already failed
if [[ ${failed} -eq 0 ]]; then
  out="$(./scripts/ci/test.sh meta coverage 2>&1)" || fail "test.sh meta coverage failed without a TestHelper:"$'\n'"${out}"
  grep -qF 'Meta tier inactive' <<<"${out}" || fail "the meta tier did not no-op:"$'\n'"${out}"
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ no-test-helper: no helper, meta suite or helper package; ${pkg} runtime graph has no test framework; meta tier no-ops"
