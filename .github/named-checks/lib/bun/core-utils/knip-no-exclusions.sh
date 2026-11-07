#!/usr/bin/env bash
set -euo pipefail

# R12: the four knip configs carry no ignore/exclude entries, negated globs or
# disabled/warn-only rules at any depth (knip.json may switch off devDependencies
# only), and the knip hooks pass no exclusion flags.

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
  negated="$(git show "${tree}:${config}" | jq -r '[.. | strings | select(startswith("!"))] | unique | join(", ")')"
  if [[ -n ${negated} ]]; then
    echo "❌ ${config} negates globs: ${negated}" >&2
    failed=1
  fi
  off="$(git show "${tree}:${config}" | jq -r --arg c "${config}" '[(.rules // {}) | to_entries[] | select(.value != "error") | .key | select(($c == "knip.json" and . == "devDependencies") | not)] | join(", ")')"
  if [[ -n ${off} ]]; then
    echo "❌ ${config} switches rules off or to warn: ${off}" >&2
    failed=1
  fi
done

flags="$(git show "${tree}:nix/pre-commit.nix" | grep -E 'node_modules/\.bin/knip' | grep -oE -- '--(exclude|include|no-exit-code|treat-config-hints-as-errors=false|max-issues)[^ "]*' || true)"
if [[ -n ${flags} ]]; then
  echo "❌ nix/pre-commit.nix knip hooks pass exclusion flags: $(tr '\n' ' ' <<<"${flags}")" >&2
  failed=1
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ knip-no-exclusions: ${configs[*]} carry no ignore/exclude entries, negated globs or disabled rules"
