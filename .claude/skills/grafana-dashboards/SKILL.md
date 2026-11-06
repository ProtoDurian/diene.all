---
name: grafana-dashboards
description: Write or change a Grafana dashboard in observability/dashboards/, then lint it and render it in a local sandbox before merge. Use for dashboard JSON, panels or template variables.
---

# Grafana Dashboards

1. Write or change the dashboard following [Grafana Dashboards](/docs/standards/grafana-dashboards/index.md).
2. Run its "Check it before merge" steps: JSON parse, strict lint, sandbox render, visual checklist.
3. Sandbox files, metric generator and lint example: `.claude/skills/grafana-dashboards/sandbox/`.
