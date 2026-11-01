#!/usr/bin/env bash
set -euo pipefail

# bun-base depends on no graph descendant: every @atomicloud/diene.* package is
# built from a bun-base descendant, so package.json declares none of them.

tree="$(git write-tree)"
found="$(git show "${tree}:package.json" | jq -r '[(.dependencies, .devDependencies, .peerDependencies, .optionalDependencies) // {} | keys[] | select(startswith("@atomicloud/diene."))] | unique | join(", ")')"

if [[ -n ${found} ]]; then
  echo "❌ package.json depends on graph descendants: ${found}" >&2
  exit 1
fi

echo "✅ no-descendant-dependency: package.json declares no @atomicloud/diene.* package"
