#!/usr/bin/env bash
set -euo pipefail

# Standards live at docs/standards/** (D5/R15); no legacy
# docs/developer/standard/** path survives on the payload branch.

tree="$(git write-tree)"
mapfile -t offending < <(git -c core.quotePath=false ls-tree -r --name-only "${tree}" | grep -E '^docs/developer/standard(/|$)' || true)

if [[ ${#offending[@]} -gt 0 ]]; then
  echo "❌ legacy standard path present:" >&2
  printf '   %s\n' "${offending[@]}" >&2
  exit 1
fi

echo "✅ legacy-path-absence: no docs/developer/standard/** path"
