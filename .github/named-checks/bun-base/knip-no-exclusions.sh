#!/usr/bin/env bash
set -euo pipefail

# R12: Knip configuration carries no ignore/exclude entries, at any depth, in
# any of the four configs.

tree="$(git write-tree)"
mapfile -t configs < <(git -c core.quotePath=false ls-tree --name-only "${tree}" | grep -E '^knip(\.production)?(\.llm)?\.json$' || true)

if [[ ${#configs[@]} -ne 4 ]]; then
  echo "❌ expected the four knip configs, found ${#configs[@]}: ${configs[*]:-none}" >&2
  exit 1
fi

failed=0
for config in "${configs[@]}"; do
  keys="$(git show "${tree}:${config}" | jq -r '[paths | .[-1] | strings | select(test("^(ignore|exclude)"; "i"))] | unique | join(", ")')"
  if [[ -n ${keys} ]]; then
    echo "❌ ${config} declares exclusions: ${keys}" >&2
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ knip-no-exclusions: ${configs[*]} carry no ignore/exclude entries"
