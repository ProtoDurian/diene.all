# Runbooks and the System Overview

- **Every alert set has its own runbook** at `observability/alerts/<slug>/runbook.md`.
- **Shared context lives once** in `observability/overview.md`. Runbooks link to it instead of repeating it.
- **Namespace, workload, team, channel and Grafana URL** come from the platform team; see [Values the platform team gives you](/docs/standards/observability/index.md#values-the-platform-team-gives-you).
- **Commands use `kubectl`** (from the infrautils [bundle](/docs/standards/grafana-dashboards/sandbox.md#tools); check with `command -v kubectl`). Cluster access comes from the platform team.

## The system overview

Write `observability/overview.md` from [the overview template](/.claude/skills/grafana-runbook/templates/overview-template.md). It is the one page a responder who has never seen this service reads first. Fill every section, and keep it to one screen. A command used by more than one runbook goes in its Common commands table, not in each runbook.

## The per-alert runbook

Start from [the runbook template](/.claude/skills/grafana-runbook/templates/runbook-template.md). The reader is half awake, so every step is copy-paste and every judgment is spelled out.

- **Triage, Remediation and Escalation are required sections.** A branchy alert may open Triage with a small Mermaid flowchart.
- **Every fix ends with a check.** Example: "Restart the consumer. Confirm with: `kubectl rollout status {workload} -n {namespace}`".
- **Say what good looks like.** Example: "Normal is under 100; over 1000 means the consumer is stuck."
- **Record past incidents** on the template's Known causes line, e.g. `Known causes: 2026-03-02 — expired TLS cert on the partner endpoint.` Updating the runbook is part of every incident follow-up.
- **Code blocks hold only commands, queries or output.** Prose goes outside them. Tag each fence with its language: `bash`, `promql`, `logql` or `traceql`.
- **A runbook that only restates the alert** means nobody can act on it, so the alert fails Gate 5. Go back to [Signal decisions](/docs/standards/observability/signals.md).

## Review checklist

- [ ] Triage, Remediation and Escalation are present and filled.
- [ ] Every fix ends with "Confirm with: …".
- [ ] Any Mermaid diagram renders: view the file in the pull request (GitHub draws Mermaid), or paste it into the website mermaid.live.
- [ ] Every `{placeholder}` is filled, except platform-team values not known yet (they keep their name) and `{landscape}` in queries, which the responder fills in.
- [ ] `overview.md` still fits on one screen.
