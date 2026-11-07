#!/usr/bin/env bash
set -euo pipefail

export TIER="${1:-}"

cd "$(git rev-parse --show-toplevel)"

export DOTNET_TEST_CONFIG="${DOTNET_TEST_CONFIG:-.config/dotnet-base.test.yaml}"
tiers="${DOTNET_TEST_CONFIG}"
[[ -n ${TIER} && "$(yq '.coverage | has(strenv(TIER))' "${tiers}")" == "true" ]] || {
  echo "❌ usage: $0 <$(yq '.coverage | keys | join("|")' "${tiers}")> [--watch|--coverage]" >&2
  exit 2
}

listed="$(yq -r '.coverage[strenv(TIER)].projects[]?' "${tiers}")"
mapfile -t projects < <(printf '%s' "${listed}")
dirs=()
for project in "${projects[@]}"; do
  [[ -f ${project} ]] || { echo "❌ ${tiers} lists ${TIER} project ${project}, which does not exist" >&2 && exit 1; }
  dirs+=("$(dirname "${project}")")
done

# Over-match on purpose: a false "has tests" only runs dotnet test; a false "none" skips the coverage gate.
found=1
[[ ${#dirs[@]} -eq 0 ]] || { rg -q -g '*.cs' -g '!bin/' -g '!obj/' 'Fact|Theory' "${dirs[@]}" && found=0 || found=$?; }
[[ ${found} -gt 1 ]] && echo "❌ could not search the ${TIER} projects for tests" >&2 && exit 1
if [[ ${found} -eq 1 ]]; then
  echo "✅ ${TIER} tier has no test files; nothing to run"
  exit 0
fi

exec ./scripts/local/dotnet-test.sh "${TIER}" "${@:2}"
