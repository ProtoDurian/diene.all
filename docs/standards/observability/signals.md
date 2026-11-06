# Signal Decisions

Use this page whenever a feature is added or changed. Walk the six gates in order, answer every one with a reason and a cost, and record the answers as one block in `observability/SIGNALS.md`. The block format is [the SIGNALS template](.claude/skills/observability-check/templates/SIGNALS-template.md).

Terms such as LPSM and ATS are defined in [Observability Standards](docs/standards/observability/index.md#terms).

## Cost: strict on metrics, liberal on logs and traces

| Signal  | What it costs                                                                    | Stance                                                                              |
| ------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Metrics | ATS = product of each label's number of values; a histogram is about 10–15× that | **Strict.** Estimate ATS first; over 100 ATS for one feature needs a written reason |
| Logs    | Lines × bytes × retention                                                        | **Liberal**, as long as logs follow events, not loops                               |
| Traces  | Spans × traffic × retention                                                      | **Liberal.** The platform samples traces to control volume                          |

An unbounded label (user ID, URL, request ID) turns one metric into millions of ATS. Put IDs in logs and span attributes instead.

## The six gates

### Gate 1 — Metrics (default NO)

Say YES only if a person or automation acts on the number, an SLO uses it, or you need an aggregate logs cannot give (such as p99 latency). Name each metric, its type, its labels and its ATS. Prefer counters and gauges; use a histogram only when you need percentiles.

Example: gauge `webhook_retry_queue_depth` with label `module` (2 values) in 2 landscapes → about 4 ATS.

### Gate 2 — Logs (default YES for events)

Log every meaningful user or business event (request handled, job run, state change, decision, failure) as one structured line with its inputs and key values, so someone can rebuild what happened, in order, without a redeploy. Never log inside hot loops or per tick; count those in a metric or log once per batch.

Example: one INFO line per delivery attempt with `delivery_id`, `target`, `attempt`, `outcome`.

### Gate 3 — Traces (default YES for user flows)

Add a span for each meaningful stage of a user flow, with key IDs as attributes. State the sampling you want. Skip tracing only for internal work with no per-request flow.

Example: span `webhook.deliver` with `delivery_id`; keep every error trace, sample successes.

### Gate 4 — Dashboard (default: the generic dashboard is enough)

The generic dashboard already shows request rate, errors, duration and resource use; never copy those panels. Only custom metrics from Gate 1 can earn a panel on a curated dashboard. No custom metrics means no curated dashboard. See [Dashboards](docs/standards/grafana-dashboards/index.md).

Example: "Retry queue depth" panel in the detail row.

### Gate 5 — Alerts (default NO)

An alert must pass all three checks:

1. **Nothing heals it already.** If an autoscaler, restart policy or retry loop fixes the condition, do not alert on it. Alert when that mechanism is exhausted.
2. **Someone can act.** The runbook must say what to do. "Watch it" means `info` at most, or no alert.
3. **It can be routed.** Its LPSM labels lead to the team that owns it.

| Condition                             | Already healed by         | Alert?                          |
| ------------------------------------- | ------------------------- | ------------------------------- |
| CPU 80%, autoscaler on                | autoscaling               | No                              |
| CPU 80%, no autoscaler                | nothing                   | `warning`                       |
| Autoscaler at max and still saturated | the autoscaler has failed | `critical`                      |
| One pod restart                       | restart policy            | No; a sustained crash loop: yes |
| Retry queue growing despite retries   | retries are losing        | Yes                             |

For each alert that survives, record its tier count (1 for a plain failure, 2 for capacity or slow decline, 3 only when the trend matters), its type (see [Alerts](docs/standards/observability/alerts.md)), and a **noise budget**: how often you expect it to fire, e.g. "≤2 pages/month". An alert that fires more often than someone acts fails check 2.

### Gate 6 — Alert-set folders

Each Gate 5 alert becomes one folder, `observability/alerts/<slug>/`, with its tier files and `runbook.md`, in the same PR. The slug is the alert name in lower case with spaces turned into hyphens, using only `a-z`, `0-9` and `-`: `Webhook retry queue` → `webhook-retry-queue`.

## Worked example

| Gate      | Decision                                                                                              | Why                                                       |
| --------- | ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| Metrics   | Yes: `webhook_retry_queue_depth` (gauge, ~4 ATS), `webhook_delivery_failures_total` (counter, ~8 ATS) | Queue depth drives capacity; failures give the error rate |
| Logs      | Yes: one line per delivery attempt, one ERROR per permanent failure                                   | Rebuild the order of events when debugging                |
| Traces    | Yes: span per delivery attempt; keep errors, sample successes                                         | See why one delivery was slow or failed                   |
| Dashboard | Curated: queue depth (detail row), failure rate (overview row)                                        | Custom metrics                                            |
| Alerts    | Yes: 2 tiers on queue depth; none on retry rate                                                       | Retrying is the healing; alert when it is losing          |
| Folders   | `alerts/webhook-retry-queue/`                                                                         |                                                           |

## Review checklist

- [ ] The feature has a block in `SIGNALS.md` with all six gates answered.
- [ ] Every answer has a one-line reason; a bare YES or NO fails review.
- [ ] Every YES names its metric, log event, span, panel or folder, and its cost (ATS, log volume or sampling).
- [ ] Every Gate 5 YES has a tier count, an alert type and a noise budget.
- [ ] Everything named exists in the PR: the metric in code, each Gate 6 folder under `observability/alerts/`.
- [ ] No unbounded metric labels, no logs in hot loops, a sampling choice for every trace.
