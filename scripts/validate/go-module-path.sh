#!/usr/bin/env bash
set -euo pipefail

expected="$(yq -r '.module' .config/go-lib.yaml)"
mirror="$(yq -r '.mirror' .config/go-lib.yaml)"
actual="$(go list -m -f '{{.Path}}')"

[ "${actual}" != "${expected}" ] && echo "❌ module path '${actual}' must be '${expected}'" >&2 && exit 1
[ "${expected}" != "github.com/${mirror}" ] && echo "❌ module path '${expected}' is not the mirror repo path 'github.com/${mirror}'" >&2 && exit 1
for doc in README.md docs/developer/go-lib-baseline.md; do
  rg -qF "${expected}" "${doc}" || {
    echo "❌ module path '${expected}' is missing from ${doc}" >&2
    exit 1
  }
done

echo "✅ Go module path matches the mirror identity"
