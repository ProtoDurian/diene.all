#!/usr/bin/env bash
set -euo pipefail

# A cache-tag label needs a setup-nix step; the OIDC token permission needs flakehub-login off; a cached shell needs DURIAN_SHELL_KEEP.
# Every setup-nix step sets store-gc-at-percent 75, and DURIAN_SHELL_KEEP is 20.

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
  if ! rows="$(yq -r '(.permissions // null) as $top | .jobs | to_entries[] | .key as $k | .value as $j
    | ($j.permissions // $top) as $p
    | ([$j.steps[]? | select((.uses // "") | test("^AtomiCloud/actions.setup-nix@"))]) as $s
    | [$k,
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(test("^nscloud-cache-tag-"))] | length > 0),
       ($s | length > 0),
       (($p == "write-all") or (($p | tag) == "!!map" and ($p["id-" + "token"] // "") == "write")),
       ([$s[] | ((.with["flakehub-login"] // "") == "false")] | any_c(. == false) | not),
       ([$s[].with["devshell-cache"]?] | any_c(. == "true")),
       (($j.env.DURIAN_SHELL_KEEP // "") != ""),
       (($j.env.DURIAN_SHELL_KEEP // "") == "20"),
       ([$s[] | ((.with["store-gc-at-percent"] // "") == "75")] | any_c(. == false) | not)] | @tsv' "${file}")"; then
    echo "❌ ${file}: yq could not read the workflow" >&2
    fail=1
    continue
  fi
  while IFS=$'\t' read -r job tag nix idtoken login cache keep keep20 gc; do
    [ -n "${job}" ] || continue
    if [ "${tag}" = true ] && [ "${nix}" != true ]; then
      echo "❌ ${file}: job '${job}' has a nscloud-cache-tag label but no AtomiCloud/actions.setup-nix step" >&2
      fail=1
    fi
    if [ "${idtoken}" = true ] && [ "${nix}" = true ] && [ "${login}" != true ]; then
      echo "❌ ${file}: job '${job}' has the OIDC token permission (write), so setup-nix must set flakehub-login: 'false'" >&2
      fail=1
    fi
    if [ "${cache}" = true ] && [ "${keep}" != true ]; then
      echo "❌ ${file}: job '${job}' sets devshell-cache: 'true' but not DURIAN_SHELL_KEEP" >&2
      fail=1
    fi
    if [ "${keep}" = true ] && [ "${keep20}" != true ]; then
      echo "❌ ${file}: job '${job}' DURIAN_SHELL_KEEP is not '20'" >&2
      fail=1
    fi
    if [ "${gc}" != true ]; then
      echo "❌ ${file}: job '${job}' has a setup-nix step without store-gc-at-percent: '75'" >&2
      fail=1
    fi
  done <<<"${rows}"
done
[ "${fail}" -eq 0 ] || exit 1
echo "✅ CI cache labels, flakehub-login, store GC and DURIAN_SHELL_KEEP are consistent"
