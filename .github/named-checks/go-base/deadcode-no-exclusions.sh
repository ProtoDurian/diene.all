#!/usr/bin/env bash
set -euo pipefail

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

for script in scripts/local/deadcode-whole.sh scripts/local/deadcode-production.sh scripts/local/staticcheck-whole.sh scripts/local/staticcheck-production.sh; do
  if ! grep -qx "${script}" <<<"${files}"; then
    echo "❌ ${script} is missing" >&2
    failed=1
  elif git show "${tree}:${script}" | grep -nE -- '-(filter|checks|ignore)\b|grep -v'; then
    echo "❌ ${script} narrows its scanner" >&2
    failed=1
  fi
done

if grep -qx 'staticcheck.conf' <<<"${files}"; then
  echo "❌ staticcheck.conf switches checks off" >&2
  failed=1
fi

if [[ "$(git show "${tree}:.golangci.yaml" | yq -r '(.linters.exclusions // {}) | del(.generated) | keys | length')" != 0 ]]; then
  echo "❌ .golangci.yaml carries an exclusion" >&2
  failed=1
fi

while IFS= read -r path; do
  if git show "${tree}:${path}" | grep -nE '//(nolint|lint:ignore|lint:file-ignore)'; then
    echo "❌ ${path} suppresses a finding" >&2
    failed=1
  fi
done < <(grep -E '\.go$' <<<"${files}" || true)

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ deadcode-no-exclusions: no scanner narrowing, config exclusions or source suppressions"
