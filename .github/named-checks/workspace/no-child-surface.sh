#!/usr/bin/env bash
set -euo pipefail

# No child-owned surface is tracked: language manifests/lockfiles, languages/,
# or the observability payload file-set (CHAIN-REFERENCES §1: language is not an
# axis; O is additive). Each base/payload node adds these, never workspace.

manifest_globs=(
  'package.json' 'bun.lock' 'bun.lockb' 'tsconfig*.json'
  '*.csproj' '*.sln' '*.fsproj' 'Directory.Build.props' 'global.json'
  'go.mod' 'go.sum' 'pubspec.yaml' 'Cargo.toml' 'pyproject.toml'
)

# Observability payload (authoritative/observability minus shared), explicit.
observability_paths=(
  .claude/skills/grafana-alert-set/SKILL.md
  .claude/skills/grafana-alert-set/templates/alert-template.yaml
  .claude/skills/grafana-alert/SKILL.md
  .claude/skills/grafana-dashboards/SKILL.md
  .claude/skills/grafana-runbook/SKILL.md
  .claude/skills/grafana-runbook/templates/overview-template.md
  .claude/skills/grafana-runbook/templates/runbook-template.md
  .claude/skills/observability-check/SKILL.md
  .claude/skills/observability-check/templates/SIGNALS-template.md
  docs/standards/grafana-dashboards/index.md
  docs/standards/grafana-dashboards/sandbox.md
  docs/standards/observability/alerts.md
  docs/standards/observability/faro.md
  docs/standards/observability/index.md
  docs/standards/observability/otel.md
  docs/standards/observability/primordial-chart.md
  docs/standards/observability/runbooks.md
  docs/standards/observability/signals.md
  observability/README.md
  observability/SIGNALS.md
  observability/alerts/README.md
  observability/dashboards/README.md
  observability/overview.md
  probes/observability-add-back-checklist.md
  probes/observability-standards-present.ts
)

tracked="$(git -c core.quotePath=false ls-files)"
found=()

while IFS= read -r path; do
  [[ -z ${path} ]] && continue
  base="${path##*/}"
  for glob in "${manifest_globs[@]}"; do
    # shellcheck disable=SC2053
    [[ ${base} == ${glob} ]] && found+=("${path}  (language manifest)")
  done
  [[ ${path} == languages/* || ${path} == */languages/* ]] && found+=("${path}  (languages/)")
done <<<"${tracked}"

for path in "${observability_paths[@]}"; do
  grep -qxF -- "${path}" <<<"${tracked}" && found+=("${path}  (observability payload)")
done

if [[ ${#found[@]} -gt 0 ]]; then
  echo "❌ child-owned surface is tracked in workspace:" >&2
  printf '   %s\n' "${found[@]}" >&2
  exit 1
fi

echo "no child-owned surface tracked"
