#!/usr/bin/env bash
set -euo pipefail

# Runs every executable *.sh in .github/named-checks/<node-ref>/. A ref may
# contain "/" (e.g. lib/bun/result); it maps to nested directories.

cd "$(git rev-parse --show-toplevel)"

if [[ -n ${GITHUB_REPOSITORY:-} && ${GITHUB_REPOSITORY} != */diene.all ]]; then
  echo "named checks run only on diene.all; skipping on ${GITHUB_REPOSITORY}"
  exit 0
fi

node_ref="${NAMED_CHECKS_NODE:-${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}}}"

case "${node_ref}" in
'' | /* | */ | *..*)
  echo "❌ refusing malformed node ref '${node_ref}'" >&2
  exit 1
  ;;
esac

checks_dir=".github/named-checks/${node_ref}"
if [[ ! -d ${checks_dir} ]]; then
  echo "no named checks declared for ${node_ref}"
  exit 0
fi

mapfile -t checks < <(find "${checks_dir}" -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort)
if [[ ${#checks[@]} -eq 0 ]]; then
  echo "❌ ${checks_dir} declares no *.sh checks" >&2
  exit 1
fi

echo "named checks for ${node_ref} (${#checks[@]})"

passed=0
failed=0
for check in "${checks[@]}"; do
  name="$(basename "${check}" .sh)"
  if [[ ! -x ${check} ]]; then
    echo "❌ ${check} is not executable" >&2
    echo "FAIL ${name}"
    failed=$((failed + 1))
    continue
  fi
  echo "::group::${name}"
  if "${check}"; then
    result="PASS"
    passed=$((passed + 1))
  else
    result="FAIL"
    failed=$((failed + 1))
  fi
  echo "::endgroup::"
  echo "${result} ${name}"
done

echo "named checks for ${node_ref}: ${passed} passed, ${failed} failed"
[[ ${failed} -eq 0 ]]
