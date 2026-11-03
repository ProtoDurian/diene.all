#!/usr/bin/env bash
set -euo pipefail

# The diff from shared's .3 commit is exactly the O file-set: the observability
# and grafana-dashboards standards, the five thin skills, the O1 root
# observability/ skeleton, probes/observability-* and this node's named checks,
# plus insertion-only registrations in CLAUDE.md (the anchored link section) and
# probes/features.json (the observability rows). Nothing tracked by shared is
# deleted, renamed or rewritten.

# The graph ancestor: shared at its recorded .3 commit (parent.sha).
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

skills='observability-check|grafana-dashboards|grafana-alert|grafana-alert-set|grafana-runbook'
added_pattern="^(docs/standards/(observability|grafana-dashboards)/[^/]+\.md|\.claude/skills/(${skills})/.+|observability/.+|probes/observability-[^/]+|\.github/named-checks/observability/[^/]+)$"
# Parent files that may only gain lines: the CLAUDE.md link section and the feature rows.
insert_only_pattern='^(CLAUDE\.md|probes/features\.json)$'

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

while IFS=$'\t' read -r status path; do
  case "${status}" in
  A)
    if [[ ! ${path} =~ ${added_pattern} ]]; then
      echo "❌ added outside the O file-set: ${path}" >&2
      failed=1
    fi
    ;;
  M)
    if [[ ! ${path} =~ ${insert_only_pattern} ]]; then
      echo "❌ parent-owned file modified: ${path}" >&2
      failed=1
    fi
    ;;
  *)
    echo "❌ ${status} of a shared path: ${path}" >&2
    failed=1
    ;;
  esac
done < <(git -c core.quotePath=false diff --no-renames --name-status "${parent_sha}" "${tree}")

while IFS=$'\t' read -r added deleted path; do
  if [[ ${path} =~ ${insert_only_pattern} && ${deleted} != 0 ]]; then
    echo "❌ ${path} must only gain lines; ${deleted} removed (+${added})" >&2
    failed=1
  fi
done < <(git -c core.quotePath=false diff --no-renames --numstat "${parent_sha}" "${tree}")

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ payload-purity: O file-set additions and insertion-only registrations against shared .3 ${parent_sha}"
