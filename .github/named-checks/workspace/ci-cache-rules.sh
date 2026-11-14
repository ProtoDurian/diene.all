#!/usr/bin/env bash
set -euo pipefail

# A cache-tag label needs a setup-nix step; the OIDC token permission needs flakehub-login off; a cached shell needs DURIAN_SHELL_KEEP.

cd "$(git rev-parse --show-toplevel)"

fail=0
# shellcheck disable=SC2016
for file in .github/workflows/*.y*ml; do
  [ -e "${file}" ] || continue
  while IFS=$'\t' read -r job tag nix idtoken login cache keep; do
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
  done < <(yq -r '(.permissions // null) as $top | .jobs | to_entries[] | .key as $k | .value as $j
    | ($j.permissions // $top) as $p
    | ([$j.steps[]? | select((.uses // "") | test("^AtomiCloud/actions.setup-nix@"))]) as $s
    | [$k,
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(test("^nscloud-cache-tag-"))] | length > 0),
       ($s | length > 0),
       (($p == "write-all") or (($p | tag) == "!!map" and ($p["id-" + "token"] // "") == "write")),
       ([$s[] | ((.with["flakehub-login"] // "") == "false")] | any_c(. == false) | not),
       ([$s[].with["devshell-cache"]?] | any_c(. == "true")),
       (($j.env.DURIAN_SHELL_KEEP // "") != "")] | @tsv' "${file}")
done
[ "${fail}" -eq 0 ] || exit 1
echo "✅ CI cache labels, flakehub-login and DURIAN_SHELL_KEEP are consistent"
