---
name: observability-check
description: Decide which metrics, logs, traces, dashboard panels and alerts a feature needs, and record the answers in observability/SIGNALS.md. Use when adding or reviewing a feature, or when asked "is this observable enough".
---

# Observability Check

1. Walk the six gates in [Signal decisions](/docs/standards/observability/signals.md), in order.
2. In `observability/SIGNALS.md`, fill the title with the known platform and service (keep `{platform}`/`{service}` while unknown), then append the feature's block: a copy of `.claude/skills/observability-check/templates/SIGNALS-template.md`.
3. `git add` the new files, then `pre-commit run --all-files`; if a hook changes files, stage them and run it again. Then hand off what the gates approved: dashboards to `grafana-dashboards`, alerts to `grafana-alert-set`.
