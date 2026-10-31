#!/usr/bin/env bash
set -euo pipefail

# Pinned snapshot only, never a live cross-repo read (rules/PROBES.md §2.10).

dir="$(dirname "${BASH_SOURCE[0]}")"
surface="${dir}/fixture-surface.txt"
tracked="$(git -c core.quotePath=false ls-files)"
bad=0

has() { grep -qxF -- "$1" <<<"${tracked}"; }

while IFS= read -r line; do
  [[ -z ${line} || ${line} == '#'* ]] && continue
  if [[ ${line} == *' !retired '* ]]; then
    path="${line%% !retired *}"
    if has "${path}"; then
      echo "❌ ${path} is retired (${line#* !retired }) but still tracked" >&2
      bad=1
    fi
  elif [[ ${line} == *' -> '* ]]; then
    path="${line%% -> *}"
    target="${line#* -> }"
    if has "${path}"; then
      echo "❌ ${path} is re-answered as ${target} but still tracked" >&2
      bad=1
    fi
    if ! has "${target}"; then
      echo "❌ ${path} -> ${target}: target missing" >&2
      bad=1
    fi
  elif ! has "${line}"; then
    echo "❌ fixture path ${line} missing" >&2
    bad=1
  fi
done <"${surface}"

[[ ${bad} -eq 0 ]] || exit 1
echo "fixture surface reproduced ($(grep -cv '^#\|^$' "${surface}") entries)"
