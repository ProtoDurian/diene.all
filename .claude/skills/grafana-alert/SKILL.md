---
name: grafana-alert
description: Write or review one alert tier file (critical.yaml, warning.yaml or info.yaml) in an alert set. Use when writing an alert rule, picking an alert type, or wording its title, summary and description.
---

# Grafana Alert

1. Copy the alert template that [Alerts](/docs/standards/observability/alerts.md#the-tier-file) names to `observability/alerts/<slug>/<severity>.yaml`.
2. Pick the type and fill every field following that page.
3. Run its Validation steps and `pre-commit run --all-files`; say in the PR which ones you ran.
