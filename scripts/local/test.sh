#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage="${2:-false}"
watch="${3:-false}"

[ -z "${mode}" ] && echo "❌ test mode not set" >&2 && exit 1
[ "${mode}" = "meta" ] && [ ! -d testhelper ] && [ ! -d tests/meta ] && echo "✅ meta tier skipped: no testhelper package" && exit 0
tests="$(yq -r ".tiers.${mode}.tests" .config/go-base.coverage.yaml)"
packages="$(yq -r ".tiers.${mode}.packages" .config/go-base.coverage.yaml)"
scope="$(yq -r ".tiers.${mode}.pathMarker" .config/go-base.coverage.yaml | sed 's|^/||; s|/$||')"
# A tier with no Go source under its scope or tests (a library without adapters) stays green and empty.
[ -z "$(find "${scope}" "${tests%/...}" -name '*.go' -print -quit 2>/dev/null || true)" ] && echo "✅ Go ${mode} tier is empty: no Go source under '${scope}/' or '${tests%/...}/'" && exit 0

[ "${watch}" = "true" ] && exec gotestsum --watch -- "${tests}"

profile="reports/${mode/int/integration}/coverage.out"
[ "${coverage}" = "true" ] && mkdir -p "$(dirname "${profile}")"
cover_packages="$([ "${coverage}" = "true" ] && go list "${packages}" | paste -sd, - || echo "")"
[ "${coverage}" = "true" ] && [ -z "${cover_packages}" ] && echo "❌ ${mode} coverage scope '${packages}' matches no package" >&2 && exit 1
coverage_args=()
[ "${coverage}" = "true" ] && coverage_args=(-covermode=atomic -coverpkg="${cover_packages}" -coverprofile="${profile}")

gotestsum --format pkgname -- -count=1 "${coverage_args[@]}" "${tests}"
[ "${coverage}" = "true" ] && ./scripts/validate/go-coverage.sh "${mode}" "${profile}"

echo "✅ Go ${mode} tests passed"
