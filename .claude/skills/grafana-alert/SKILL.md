---
name: grafana-alert
description: Write or review one alert tier file (critical.yaml, warning.yaml or info.yaml) in an alert set. Use when writing an alert rule, picking an alert type, or wording its title, summary and description.
---

# Grafana Alert

1. Copy [the alert template](.claude/skills/grafana-alert-set/templates/alert-template.yaml) to `observability/alerts/<slug>/<severity>.yaml`.
2. Fill it in following [Alerts](docs/standards/observability/alerts.md): pick the type, keep the title ≤48 characters.
3. Before merge, press **Preview** on the rule in Grafana and say so in the PR.
