#!/usr/bin/env bash
set -euo pipefail

# A cache-tag label needs a setup-nix step; the OIDC token permission needs flakehub-login off; a cached shell needs DURIAN_SHELL_KEEP.
# A job with the shared cache tag asks for nscloud-cache-size-40gb and its setup-nix steps set cache-size-gb 40.
# Levels read per rule:
# - Job level: runs-on labels (the shared cache tag, nscloud-cache-size-40gb) and permissions (a job overrides the workflow).
# - Workflow (.env), job (.jobs.<id>.env) and step (.jobs.<id>.steps[].env) level: DURIAN_SHELL_KEEP.
#   It is judged for each setup-nix and durian-shell step as GitHub Actions resolves it (step over job over workflow), and must be 64.
#   Every such step needs it at one of the three levels.
# - Step level (with:) only: flakehub-login, devshell-cache, store-gc-at-percent (90) and cache-size-gb (40).
# - The nix-store-clean-up.yaml workflow (rule h) is exempt from the 90 percent rule; it needs a schedule, the shared tag, the 40gb volume, no do-not-commit label, and GC at 0/0.

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
       ([$s[] | ((.with["store-gc-at-percent"] // "") == "90")] | any_c(. == false) | not),
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(. == "nscloud-cache-size-40gb")] | length > 0),
       ([$s[] | ((.with["cache-size-gb"] // "") == "40")] | any_c(. == false) | not)] | @tsv' "${file}")"; then
    echo "❌ ${file}: yq could not read the workflow" >&2
    fail=1
    continue
  fi
  while IFS=$'\t' read -r job tag nix idtoken login gc size cgb; do
    [ -n "${job}" ] || continue
    if [ "${tag}" = true ] && [ "${nix}" != true ]; then
      echo "❌ ${file}: job '${job}' has a nscloud-cache-tag label but no AtomiCloud/actions.setup-nix step" >&2
      fail=1
    fi
    if [ "${idtoken}" = true ] && [ "${nix}" = true ] && [ "${login}" != true ]; then
      echo "❌ ${file}: job '${job}' has the OIDC token permission (write), so setup-nix must set flakehub-login: 'false'" >&2
      fail=1
    fi
    if [ "${gc}" != true ] && [ "${file##*/}" != nix-store-clean-up.yaml ]; then
      echo "❌ ${file}: job '${job}' has a setup-nix step without store-gc-at-percent: '90'" >&2
      fail=1
    fi
    if [ "${tag}" = true ] && [ "${size}" != true ]; then
      echo "❌ ${file}: job '${job}' has the shared cache tag but does not ask for nscloud-cache-size-40gb" >&2
      fail=1
    fi
    if [ "${tag}" = true ] && [ "${cgb}" != true ]; then
      echo "❌ ${file}: job '${job}' has a setup-nix step without cache-size-gb: '40'" >&2
      fail=1
    fi
  done <<<"${rows}"
  if ! steps="$(yq -r '(.env // {}) as $w | .jobs | to_entries[] | .key as $k | .value as $j
    | ($j.steps // []) | to_entries[] | .key as $i | .value as $st
    | select((($st.uses // "") | test("^AtomiCloud/actions.setup-nix@")) or (($st.run // "") | test("durian-shell")))
    | (($st.env // {}) | has("DURIAN_SHELL_KEEP")) as $hs | (($j.env // {}) | has("DURIAN_SHELL_KEEP")) as $hj | ($w | has("DURIAN_SHELL_KEEP")) as $hw
    | [$k, ($st.name // $st.uses // ("#" + ($i | tostring))),
       $hs, $hj, $hw,
       "[" + ($st.env.DURIAN_SHELL_KEEP // "") + "]", "[" + ($j.env.DURIAN_SHELL_KEEP // "") + "]", "[" + ($w.DURIAN_SHELL_KEEP // "") + "]"] | @tsv' "${file}")"; then
    echo "❌ ${file}: yq could not read the workflow steps" >&2
    fail=1
    continue
  fi
  while IFS=$'\t' read -r job step hs hj hw sv jv wv; do
    [ -n "${job}" ] || continue
    sv="${sv#[}"
    sv="${sv%]}"
    jv="${jv#[}"
    jv="${jv%]}"
    wv="${wv#[}"
    wv="${wv%]}"
    level=none
    value=""
    if [ "${hs}" = true ]; then
      level=step
      value="${sv}"
    elif [ "${hj}" = true ]; then
      level=job
      value="${jv}"
    elif [ "${hw}" = true ]; then
      level=workflow
      value="${wv}"
    fi
    if [ "${level}" = none ]; then
      echo "❌ ${file}: job '${job}' step '${step}' has no DURIAN_SHELL_KEEP at workflow, job or step level" >&2
      fail=1
    elif [ "${value}" != 64 ]; then
      echo "❌ ${file}: job '${job}' step '${step}' DURIAN_SHELL_KEEP is not '64' (in effect: '${value}', set at ${level} level)" >&2
      fail=1
    fi
  done <<<"${steps}"
done

# Rule (h): the nightly clean-up workflow commits the cleaned volume on the shared tag and GCs everything unneeded.
cleanup="${dir}/nix-store-clean-up.yaml"
if [ ! -f "${cleanup}" ]; then
  echo "❌ ${cleanup}: the Nix store clean-up workflow is missing" >&2
  fail=1
else
  # shellcheck disable=SC2016
  if ! hrows="$(yq -r '(.on.schedule // []) as $sc | .jobs | to_entries[] | .key as $k | .value as $j
    | ([$j.steps[]? | select((.uses // "") | test("^AtomiCloud/actions.setup-nix@"))]) as $s
    | [$k,
       ($sc | length > 0),
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(. == "nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64")] | length > 0),
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(. == "nscloud-cache-size-40gb")] | length > 0),
       ([$j["runs-on"]? | .. | select(tag == "!!str") | select(test("do-not-commit"))] | length == 0),
       ($s | length > 0),
       ([$s[] | ((.with["cache-size-gb"] // "") == "40")] | any_c(. == false) | not),
       ([$s[] | ((.with["store-gc-at-percent"] // "") == "0")] | any_c(. == false) | not),
       ([$s[] | ((.with["store-gc-target-percent"] // "") == "0")] | any_c(. == false) | not)] | @tsv' "${cleanup}")"; then
    echo "❌ ${cleanup}: yq could not read the workflow" >&2
    fail=1
    hrows=""
  fi
  [ -n "${hrows}" ] || {
    echo "❌ ${cleanup}: the clean-up workflow has no job" >&2
    fail=1
  }
  while IFS=$'\t' read -r job sched tag size commit nix cgb at target; do
    [ -n "${job}" ] || continue
    [ "${sched}" = true ] || {
      echo "❌ ${cleanup}: the clean-up workflow has no schedule trigger" >&2
      fail=1
    }
    [ "${tag}" = true ] || {
      echo "❌ ${cleanup}: job '${job}' is not on the shared cache tag" >&2
      fail=1
    }
    [ "${size}" = true ] || {
      echo "❌ ${cleanup}: job '${job}' does not ask for nscloud-cache-size-40gb" >&2
      fail=1
    }
    [ "${commit}" = true ] || {
      echo "❌ ${cleanup}: job '${job}' has a do-not-commit label, but the clean-up must commit the volume" >&2
      fail=1
    }
    [ "${nix}" = true ] || {
      echo "❌ ${cleanup}: job '${job}' has no AtomiCloud/actions.setup-nix step" >&2
      fail=1
    }
    [ "${cgb}" = true ] || {
      echo "❌ ${cleanup}: job '${job}' setup-nix step is not cache-size-gb: '40'" >&2
      fail=1
    }
    [ "${at}" = true ] || {
      echo "❌ ${cleanup}: job '${job}' setup-nix step is not store-gc-at-percent: '0'" >&2
      fail=1
    }
    [ "${target}" = true ] || {
      echo "❌ ${cleanup}: job '${job}' setup-nix step is not store-gc-target-percent: '0'" >&2
      fail=1
    }
  done <<<"${hrows}"
fi
[ "${fail}" -eq 0 ] || exit 1
echo "✅ CI cache labels, flakehub-login, store GC, cache size, clean-up workflow and DURIAN_SHELL_KEEP are consistent"
