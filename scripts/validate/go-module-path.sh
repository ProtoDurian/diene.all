#!/usr/bin/env bash
set -euo pipefail

expected="$(yq -r '.module' .config/go-lib.yaml)"
mirror="$(yq -r '.mirror' .config/go-lib.yaml)"
actual="$(go list -m -f '{{.Path}}')"

[ "${actual}" != "${expected}" ] && echo "❌ module path '${actual}' must be '${expected}'" >&2 && exit 1
[ "${expected}" != "github.com/${mirror}" ] && echo "❌ module path '${expected}' is not the mirror repo path 'github.com/${mirror}'" >&2 && exit 1
rg -qF "${expected}" README.md docs/developer/go-lib-baseline.md || {
  echo "❌ module path '${expected}' is missing from the library documentation" >&2
  exit 1
}

echo "✅ Go module path matches the mirror identity"
