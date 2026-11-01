#!/usr/bin/env bash
set -euo pipefail

# shared ships agnostic standards only: no language variants (each base adds its
# own), no observability or grafana-dashboards content (the observability
# payload branch owns it), and no legacy docs/developer/standard/** path.

tree="$(git write-tree)"
mapfile -t offending < <(git -c core.quotePath=false ls-tree -r --name-only "${tree}" |
  grep -E '(^|/)languages/[^/]+\.md$|^(docs/standards|\.claude/skills)/(observability|grafana-dashboards)(/|$)|^docs/developer/standard/' |
  grep -v '^\.claude/skills/vendor/' || true)

if [[ ${#offending[@]} -gt 0 ]]; then
  echo "❌ payload purity violated:" >&2
  printf '   %s\n' "${offending[@]}" >&2
  exit 1
fi

echo "✅ payload-purity: no language variants, no observability, no legacy standard path"
