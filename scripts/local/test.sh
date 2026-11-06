#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage="${2:-false}"
watch="${3:-false}"

[ -z "${mode}" ] && echo "❌ test mode not set" >&2 && exit 1
tests="$(yq -r ".tiers.${mode}.tests" .config/go-base.coverage.yaml)"
packages="$(yq -r ".tiers.${mode}.packages" .config/go-base.coverage.yaml)"

[ "${watch}" = "true" ] && exec gotestsum --watch -- "${tests}"

profile="reports/${mode/int/integration}/coverage.out"
[ "${coverage}" = "true" ] && mkdir -p "$(dirname "${profile}")"
cover_packages="$([ "${coverage}" = "true" ] && go list "${packages}" | paste -sd, - || echo "")"
coverage_args=()
[ "${coverage}" = "true" ] && coverage_args=(-covermode=atomic -coverpkg="${cover_packages}" -coverprofile="${profile}")

gotestsum --format pkgname -- -count=1 "${coverage_args[@]}" "${tests}"
[ "${coverage}" = "true" ] && ./scripts/validate/go-coverage.sh "${mode}" "${profile}"

echo "✅ Go ${mode} tests passed"
