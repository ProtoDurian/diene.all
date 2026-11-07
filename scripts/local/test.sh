#!/usr/bin/env bash
set -euo pipefail

tier="${1:-}"

cd "$(git rev-parse --show-toplevel)"

tiers=".config/dotnet-base.test.yaml"
[[ -n ${tier} && "$(yq ".coverage | has(\"${tier}\")" "${tiers}")" == "true" ]] || {
  echo "❌ usage: $0 <$(yq '.coverage | keys | join("|")' "${tiers}")> [--watch|--coverage]" >&2
  exit 2
}

mapfile -t projects < <(yq -r ".coverage.${tier}.projects[]?" "${tiers}")
dirs=()
for project in "${projects[@]}"; do
  [[ -f ${project} ]] || { echo "❌ ${tiers} lists ${tier} project ${project}, which does not exist" >&2 && exit 1; }
  dirs+=("$(dirname "${project}")")
done

# rg exits 0 on a match, 1 on none, 2 on an error.
found=1
[[ ${#dirs[@]} -eq 0 ]] || { rg -q -g '*.cs' -g '!bin/' -g '!obj/' '\[(Fact|Theory)\b' "${dirs[@]}" && found=0 || found=$?; }
[[ ${found} -gt 1 ]] && echo "❌ could not search the ${tier} projects for tests" >&2 && exit 1
if [[ ${found} -eq 1 ]]; then
  echo "✅ ${tier} tier has no test files; nothing to run"
  exit 0
fi

exec ./scripts/local/dotnet-test.sh "${tier}" "${@:2}"
