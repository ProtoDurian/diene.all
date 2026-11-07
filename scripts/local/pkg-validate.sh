#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
modes=(module-path vet api-compat export-docs examples consumer-test)
if [ "${mode}" != "all" ]; then
  known=false
  for each in "${modes[@]}"; do [ "${each}" = "${mode}" ] && known=true; done
  [ "${known}" = false ] && echo "❌ unknown package-validation mode '${mode}'" >&2 && exit 1
  modes=("${mode}")
fi

for each in "${modes[@]}"; do
  "./scripts/validate/go-${each}.sh"
done

echo "✅ Go library ${mode} validation passed"
