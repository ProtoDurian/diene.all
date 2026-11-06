---
name: observability-check
description: Decide which metrics, logs, traces, dashboard panels and alerts a feature needs, and record the answers in observability/SIGNALS.md. Use when adding or reviewing a feature, or when asked "is this observable enough".
---

# Observability Check

1. Read [Signal decisions](docs/standards/observability/signals.md) and walk the six gates in order.
2. Add one block per feature to `observability/SIGNALS.md`, using [the SIGNALS template](.claude/skills/observability-check/templates/SIGNALS-template.md).
3. Hand off what the gates approved: dashboards to `grafana-dashboards`, alerts to `grafana-alert-set`.
