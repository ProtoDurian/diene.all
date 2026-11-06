---
name: grafana-runbook
description: Write or update an alert set's runbook.md or the shared observability/overview.md. Use when an alert set lacks a runbook, or after an incident showed a runbook gap.
---

# Grafana Runbook

1. Follow [Runbooks](/docs/standards/observability/runbooks.md).
2. Runbook: copy `.claude/skills/grafana-runbook/templates/runbook-template.md` to `observability/alerts/<slug>/runbook.md` and fill it.
3. Overview: fill `.claude/skills/grafana-runbook/templates/overview-template.md` into `observability/overview.md`. Last, run `pre-commit run --all-files`.
