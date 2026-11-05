#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
modes=(module-path vet api-compat export-docs examples)
[ "${mode}" != "all" ] && [[ ! " ${modes[*]} " =~ \ ${mode}\  ]] && echo "❌ unknown package-validation mode '${mode}'" >&2 && exit 1
[ "${mode}" != "all" ] && modes=("${mode}")

go mod download
for each in "${modes[@]}"; do
  "./scripts/validate/go-${each}.sh"
done

echo "✅ Go library ${mode} validation passed"
