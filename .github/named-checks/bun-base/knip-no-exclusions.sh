#!/usr/bin/env bash
set -euo pipefail

tree="$(git write-tree)"
mapfile -t configs < <(git -c core.quotePath=false ls-tree --name-only "${tree}" | grep -E '^knip(\..+)?\.jsonc?$' || true)

if [[ ${configs[*]:-} != "knip.json" ]]; then
  echo "❌ expected exactly one knip config (knip.json), found: ${configs[*]:-none}" >&2
  exit 1
fi

keys="$(git show "${tree}:knip.json" | jq -r '[paths | .[-1] | strings | select(test("^(ignore|exclude)"; "i"))] | unique | join(", ")')"
if [[ -n ${keys} ]]; then
  echo "❌ knip.json declares exclusions: ${keys}" >&2
  exit 1
fi

echo "✅ knip-no-exclusions: knip.json is the only knip config and carries no ignore/exclude entries"
