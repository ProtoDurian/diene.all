#!/usr/bin/env bash
set -euo pipefail

# Release workflow gating (goal: "release workflow gating — gate"): release.yaml runs on
# workflow_run of CI success on main and holds the single `release` concurrency group.
# Every assertion runs; the gate passes only when all of them conform.

workflow=".github/workflows/release.yaml"
[ -f "${workflow}" ] || {
  echo "❌ ${workflow} is missing" >&2
  exit 1
}

json="$(yq -o=json "${workflow}")"
failed=0

check() {
  local expr="$1" reason="$2"
  if ! jq -e "${expr}" >/dev/null <<<"${json}"; then
    echo "❌ ${reason}" >&2
    failed=1
  fi
}

check '.on.workflow_run.workflows == ["CI"]' "release must trigger from CI"
check '.on.workflow_run.branches == ["main"]' "release must be limited to main"
check '.on.workflow_run.types == ["completed"]' "release workflow_run type must be completed"
check '.jobs.release.if == "github.event.workflow_run.conclusion == '\''success'\''"' "release job must require CI success"
check '.concurrency.group == "release"' "release concurrency group must be release"

[ "${failed}" -eq 0 ] || exit 1
echo "✅ Release policy conforms"
