# Signals — `{platform}`/`{service}`

One block per feature. Answer every gate with a reason and a cost. Rules: [Signal decisions](docs/standards/observability/signals.md).

## Feature: `{feature name}` ({PR link or date})

### Gate 1 — Metrics

**Decision:** NO | YES
**Why:** {who acts on the number, which SLO uses it, or which aggregate it answers}

| Metric   | Type                    | Labels             | ATS (active time series)     | Why      |
| -------- | ----------------------- | ------------------ | ---------------------------- | -------- |
| `{name}` | counter/gauge/histogram | `{bounded labels}` | {estimate; histogram ×10–15} | {reason} |

### Gate 2 — Logs

**Decision:** YES | NO
**Why:** {which user or business events; NO only if there is no event flow}

| Event                          | Level           | Inputs and key values        | Volume                    |
| ------------------------------ | --------------- | ---------------------------- | ------------------------- |
| `{event, decision or failure}` | INFO/WARN/ERROR | `{values to rebuild events}` | {lines per second or day} |

### Gate 3 — Traces

**Decision:** YES | NO
**Why:** {which user flow; NO only if there is no per-request flow}

| Span          | Attributes                 | Sampling                                 |
| ------------- | -------------------------- | ---------------------------------------- |
| `{span name}` | LPSM + `{key ids, values}` | {e.g. keep all errors, sample successes} |

### Gate 4 — Dashboard

**Decision:** generic dashboard is enough | curated panels
**Why:** {custom metrics only; standard signals are on the generic dashboard}

| Panel     | Row             | Metric     |
| --------- | --------------- | ---------- |
| `{title}` | overview/detail | `{metric}` |

### Gate 5 — Alerts

**Decision:** NO | YES
**Already healed by:** {autoscaler, restarts, retries… and why that does not cover it}
**Noise budget:** {expected fire rate, e.g. ≤2 pages/month}

| Alert name  | Type                                                        | Tiers | Thresholds                      |
| ----------- | ----------------------------------------------------------- | ----- | ------------------------------- |
| `{symptom}` | threshold/absence/event/burn rate/seasonal/forecast/outlier | 1/2/3 | `{warning at X, critical at Y}` |

### Gate 6 — Alert-set folders

- None, or `observability/alerts/{alert-slug}/`
