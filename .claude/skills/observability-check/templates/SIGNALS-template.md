## Feature: `{feature name}` ({PR link or date})

### Gate 1 — Metrics

**Decision:** NO | YES
**Why:** {who acts on the number, which SLO uses it, or which aggregate it answers}

| Metric   | Type                    | Labels             | ATS                          | Why                                                       |
| -------- | ----------------------- | ------------------ | ---------------------------- | --------------------------------------------------------- |
| `{name}` | counter/gauge/histogram | `{bounded labels}` | {estimate; histogram ×10–15} | {reason; `planned` if the service has no code for it yet} |

### Gate 2 — Logs

**Decision:** YES | NO
**Why:** {which user or business events; NO only if there is no event flow}

| Event                          | Level           | Inputs and key values        | Volume                    |
| ------------------------------ | --------------- | ---------------------------- | ------------------------- |
| `{event, decision or failure}` | INFO/WARN/ERROR | `{values to rebuild events}` | {lines per second or day} |

### Gate 3 — Traces

**Decision:** YES | NO
**Why:** {which user flow; NO only if there is no per-request flow}

| Span          | Attributes                                  | Sampling               |
| ------------- | ------------------------------------------- | ---------------------- |
| `{span name}` | `{key ids, values}` (the library adds LPSM) | {head ratio, e.g. 0.1} |

### Gate 4 — Dashboard

**Decision:** generic dashboard is enough | curated panels
**Why:** {custom metrics only; standard signals are on the generic dashboard}

| Panel     | Row             | Metric or log event        |
| --------- | --------------- | -------------------------- |
| `{title}` | overview/detail | `{metric or Gate 2 event}` |

### Gate 5 — Alerts

**Decision:** NO | YES
**Why:** {what users feel when it breaks, or why no alert is needed}

| Alert name  | Type                                                        | Tiers | Thresholds                                     | SLO            | Already healed by       | Noise budget | Owner                |
| ----------- | ----------------------------------------------------------- | ----- | ---------------------------------------------- | -------------- | ----------------------- | ------------ | -------------------- |
| `{symptom}` | threshold/absence/event/burn rate/seasonal/forecast/outlier | 1/2/3 | `{warning X, critical Y; or SLO + burn rates}` | {SLO, or none} | {mechanism, or nothing} | {≤2/month}   | {team, or `pending`} |

### Gate 6 — Alert-set folders

- None, or `{alert name}` → `observability/alerts/{slug}/`, one line per Gate 5 alert
