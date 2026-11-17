#!/usr/bin/env bash
set -euo pipefail

tree="$(git write-tree)"
failed=0
fail() {
  echo "❌ $1" >&2
  failed=1
}

mapfile -t scope < <(git -c core.quotePath=false ls-tree -r --name-only "${tree}" |
  grep -E '^(docs/standards/(observability|grafana-dashboards)/|\.claude/skills/(observability-check|grafana-alert|grafana-alert-set|grafana-dashboards|grafana-runbook)/)')
[[ ${#scope[@]} -gt 0 ]] || fail "no observability standards or skills on this tree"

for file in "${scope[@]}"; do
  content="$(git cat-file -p "${tree}:${file}")"
  hits="$(grep -n -i -E 'logql|\batomi\.|loki' <<<"${content}" | grep -v -i -E 'loki-api|loki\.relabel|replaced loki|replaces loki' || true)"
  [[ -z ${hits} ]] || fail "${file}: names Loki, LogQL or an atomi. attribute:"$'\n'"${hits}"
done

line="$(git cat-file -p "${tree}:docs/standards/observability/otel.md" | grep -F 'VL-Stream-Fields:' | head -1)"
for field in service.name service.namespace deployment.environment.name k8s.namespace.name durian.cloud.landscape durian.cloud.platform durian.cloud.service durian.cloud.module; do
  grep -qF -- "${field}" <<<"${line}" || fail "VL-Stream-Fields line lacks ${field}"
done

for path in \
  docs/standards/observability/{index,signals,otel,alerts,faro,runbooks,shipping}.md \
  docs/standards/grafana-dashboards/{index,sandbox}.md \
  .claude/skills/{observability-check,grafana-alert,grafana-alert-set,grafana-dashboards,grafana-runbook}/SKILL.md \
  .claude/skills/grafana-dashboards/sandbox/compose.yaml \
  observability/{index,overview,SIGNALS}.md observability/alerts/README.md observability/dashboards/README.md \
  probes/observability-standards-present.ts; do
  git cat-file -e "${tree}:${path}" 2>/dev/null || fail "missing ${path}"
done

for path in .github/named-checks/shared/lib/fold-checks.sh .github/named-checks/observability probes/observability-add-back-checklist.md; do
  [[ -z "$(git ls-tree -r --name-only "${tree}" -- "${path}")" ]] || fail "add-back machinery present: ${path}"
done

command -v obs >/dev/null 2>&1 || fail "obs is not in the dev shell"
obs --version >/dev/null || fail "obs --version failed"

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ observability-standards: wording, stream fields, files and obs binary"
