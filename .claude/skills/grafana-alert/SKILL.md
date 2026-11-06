---
name: grafana-alert
description: Write or review one alert tier file (critical.yaml, warning.yaml or info.yaml) in an alert set. Use when writing an alert rule, picking an alert type, or wording its title, summary and description.
---

# Grafana Alert

1. Copy `.claude/skills/grafana-alert-set/templates/alert-template.yaml` to `observability/alerts/<slug>/<severity>.yaml`.
2. Pick the type and fill every field following [Alerts](/docs/standards/observability/alerts.md#the-tier-file).
3. Run its Validation steps and say in the PR which ones you ran. Last, `git add` the new files, then `pre-commit run --all-files`; if a hook changes files, stage them and run it again.
