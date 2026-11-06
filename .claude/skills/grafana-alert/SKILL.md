---
name: grafana-alert
description: Write or review one alert tier file (critical.yaml, warning.yaml or info.yaml) in an alert set. Use when writing an alert rule, picking an alert type, or wording its title, summary and description.
---

# Grafana Alert

1. Copy `.claude/skills/grafana-alert-set/templates/alert-template.yaml` to `observability/alerts/<slug>/<severity>.yaml`.
2. Pick the type and fill every field following [Alerts](/docs/standards/observability/alerts.md).
3. Run its Validation steps and `pre-commit run --all-files`; say in the PR which ones you ran.
