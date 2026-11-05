#!/usr/bin/env bash
set -euo pipefail

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

fail() {
  echo "❌ $*" >&2
  failed=1
}

for script in scripts/local/deadcode-whole.sh scripts/local/deadcode-production.sh scripts/local/staticcheck-whole.sh scripts/local/staticcheck-production.sh; do
  if ! grep -qx "${script}" <<<"${files}"; then
    fail "${script} is missing"
  elif git show "${tree}:${script}" | grep -nE -- '-(filter|checks|ignore)\b|grep -v'; then
    fail "${script} narrows its scanner"
  fi
done
wrapper=scripts/local/with-deadcode-consumer.sh
if grep -qx "${wrapper}" <<<"${files}" && git show "${tree}:${wrapper}" | grep -nE -- '-(filter|checks|ignore)\b|grep -v'; then
  fail "${wrapper} narrows its scanner"
fi

if grep -qx 'staticcheck.conf' <<<"${files}"; then
  fail "staticcheck.conf switches checks off"
fi

exclusion_keys() {
  local config="$1"
  shift
  git show "${tree}:${config}" | yq -r '[.. | path | map(tostring) | select(any_c(test("(?i)^exclu"))) | join(".")] | .[]' | grep -vxF -e '' "${@/#/-e}" || true
}

for config in .golangci.yaml .golangci.docs.yaml; do
  if ! grep -qx "${config}" <<<"${files}"; then
    fail "${config} is missing"
    continue
  fi
  # go-base keeps only `linters.exclusions.generated: lax` (generated files are not ours).
  if [[ ${config} == .golangci.yaml ]]; then
    keys="$(exclusion_keys "${config}" linters.exclusions linters.exclusions.generated)"
  else
    keys="$(exclusion_keys "${config}")"
  fi
  [[ -z ${keys} ]] || fail "${config} carries an exclusion: $(paste -sd, <<<"${keys}")"
done

while IFS= read -r path; do
  if git show "${tree}:${path}" | grep -nE '//(nolint|lint:ignore|lint:file-ignore)'; then
    fail "${path} suppresses a finding"
  fi
done < <(grep -E '\.go(\.txt)?$' <<<"${files}" || true)

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ deadcode-no-exclusions: no scanner narrowing, config exclusions or source suppressions"
