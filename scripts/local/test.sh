#!/usr/bin/env bash
set -euo pipefail

tier="${1:-}"

cd "$(git rev-parse --show-toplevel)"

tiers=".config/bun-base.coverage.yaml"
[[ -n ${tier} && "$(yq ".tiers | has(\"${tier}\")" "${tiers}")" == "true" ]] || {
  echo "❌ usage: $0 <$(yq '.tiers | keys | join("|")' "${tiers}")> [bun test args]" >&2
  exit 2
}
tests="$(yq ".tiers.${tier}.tests // \"\"" "${tiers}")"
[[ -z ${tests} ]] && echo "❌ ${tiers} gives tier ${tier} no tests folder" >&2 && exit 2

# Same file names bun test discovers.
if [[ -z "$(rg --files -g '*{.test,_test,.spec,_spec}.{ts,tsx,js,jsx}' "${tests}" 2>/dev/null || true)" ]]; then
  echo "✅ ${tier} tier has no test files under ${tests}; nothing to run"
  exit 0
fi
config="bunfig.${tier}.toml"
[[ -f ${config} ]] || { echo "❌ ${tier} tier has tests but no ${config}" >&2 && exit 1; }

bun test --config="${config}" "${@:2}"
