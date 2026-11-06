---
name: grafana-alert-set
description: Create or review an alert set, the folder observability/alerts/<slug>/ holding one to three tier files and a runbook. Use when turning a Gate 5 decision in SIGNALS.md into alerts, or reviewing a service's alerts.
---

# Grafana Alert Set

1. Create the folder and choose its tiers following [Alerts](/docs/standards/observability/alerts.md).
2. Write each tier file with `grafana-alert`, from `.claude/skills/grafana-alert-set/templates/alert-template.yaml`.
3. Write the folder's `runbook.md` with `grafana-runbook`, then run `pre-commit run --all-files`.
