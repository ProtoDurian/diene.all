---
name: grafana-alert-set
description: Create or review an alert set, the folder observability/alerts/<slug>/ holding one to three tier files and a runbook. Use when turning a Gate 5 decision in SIGNALS.md into alerts, or reviewing a service's alerts.
---

# Grafana Alert Set

1. Follow [Alerts](docs/standards/observability/alerts.md): one folder per alert set, file name = severity.
2. Write each tier file with `grafana-alert`, from [the alert template](.claude/skills/grafana-alert-set/templates/alert-template.yaml).
3. Write the folder's `runbook.md` with `grafana-runbook`.
