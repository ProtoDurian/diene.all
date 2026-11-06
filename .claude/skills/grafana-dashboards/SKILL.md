---
name: grafana-dashboards
description: Write or change a Grafana dashboard in observability/dashboards/, then lint it and render it in a local sandbox before merge. Use for dashboard JSON, panels or template variables.
---

# Grafana Dashboards

1. Follow [Grafana Dashboards](docs/standards/grafana-dashboards/index.md): curated dashboards only for custom metrics that Gate 4 approved.
2. Check it with the [Dashboard sandbox](docs/standards/grafana-dashboards/sandbox.md): `jq`, strict `dashboard-linter`, render, read the PNGs.
3. Sandbox files, metric generator and lint example: `.claude/skills/grafana-dashboards/sandbox/`.
