#!/usr/bin/env bash
set -euo pipefail

# (a) A job with a nscloud-cache-tag- label has an AtomiCloud/actions.setup-nix step. (f) A job with the shared cache tag asks for nscloud-cache-size-40gb.

dir="${1:-.github/workflows}"
if [ ! -d "${dir}" ]; then
  echo "❌ workflows directory '${dir}' does not exist" >&2
  exit 1
fi
dir="$(cd "${dir}" && pwd)"
cd "$(git rev-parse --show-toplevel)"

command -v yq >/dev/null || {
  echo "❌ yq is required" >&2
  exit 1
}

fail=0
# shellcheck disable=SC2016
for file in "${dir}"/*.y*ml; do
  [ -e "${file}" ] || continue
  if ! rows="$(yq -r '.jobs | to_entries[] | .key as $k | .value as $j
    | [$k,
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(test("^nscloud-cache-tag-"))] | length > 0),
       ([$j.steps[]? | select((.uses // "") | test("^AtomiCloud/actions.setup-nix@"))] | length > 0),
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(. == "nscloud-cache-size-40gb")] | length > 0)] | @tsv' "${file}")"; then
    echo "❌ ${file}: yq could not read the workflow" >&2
    fail=1
    continue
  fi
  while IFS=$'\t' read -r job tag nix size; do
    [ -n "${job}" ] || continue
    if [ "${tag}" = true ] && [ "${nix}" != true ]; then
      echo "❌ ${file}: job '${job}' has a nscloud-cache-tag label but no AtomiCloud/actions.setup-nix step" >&2
      fail=1
    fi
    if [ "${tag}" = true ] && [ "${size}" != true ]; then
      echo "❌ ${file}: job '${job}' has the shared cache tag but does not ask for nscloud-cache-size-40gb" >&2
      fail=1
    fi
  done <<<"${rows}"
done
[ "${fail}" -eq 0 ] || exit 1
echo "✅ CI cache labels have a setup-nix step and the 40gb volume"
