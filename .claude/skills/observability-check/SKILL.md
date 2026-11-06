---
name: observability-check
description: Decide which metrics, logs, traces, dashboard panels and alerts a feature needs, and record the answers in observability/SIGNALS.md. Use when adding or reviewing a feature, or when asked "is this observable enough".
---

# Observability Check

1. Walk the six gates in [Signal decisions](/docs/standards/observability/signals.md), in order.
2. Append the feature's block to `observability/SIGNALS.md`: copy `.claude/skills/observability-check/templates/SIGNALS-template.md` from `## Feature:` to the end.
3. Run `pre-commit run --all-files`, then hand off what the gates approved: dashboards to `grafana-dashboards`, alerts to `grafana-alert-set`.
