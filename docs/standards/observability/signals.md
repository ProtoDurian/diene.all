# Signal Decisions

Use this page whenever a feature is added or changed. Walk the six gates in order, answer every one with a reason and a cost, and record the answers as one block in `observability/SIGNALS.md`. The block format is [the SIGNALS template](/.claude/skills/observability-check/templates/SIGNALS-template.md).

Terms such as LPSM, ATS and SLO are defined in [Observability Standards](/docs/standards/observability/index.md#terms).

## Cost: strict on metrics, liberal on logs and traces

| Signal  | What it costs                                                                    | Stance                                                                              |
| ------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Metrics | ATS = product of each label's number of values; a histogram is about 10–15× that | **Strict.** Estimate ATS first; over 100 ATS for one feature needs a written reason |
| Logs    | Lines × bytes × retention                                                        | **Liberal**, as long as logs follow events, not loops                               |
| Traces  | Spans × traffic × retention                                                      | **Liberal.** The platform team samples traces in the collector                      |

An unbounded label (user ID, URL, request ID) turns one metric into millions of ATS. Put IDs in logs and span attributes instead. If the collector keeps a per-pod label (`pod` or `instance`; check one series in Grafana Explore), multiply the ATS by the replica count. For a new metric, assume it does and use the planned replica count. Count every landscape the service runs in, wherever its data is stored. Until you know the landscapes or replicas, assume 2 landscapes × 2 replicas and say so in the ATS cell.

## The six gates

### Gate 1 — Metrics (default NO)

Say YES only if a person or automation acts on the number, an SLO uses it, or you need an aggregate logs cannot give (such as p99 latency). List only the metrics this feature adds, each with its type, labels and ATS; name an existing metric an SLO uses in the Why line. Prefer counters and gauges; use a histogram only when you need percentiles.

Example: gauge `webhook_retry_queue_depth` with label `module` (2 values) in 2 landscapes × 2 replicas → about 8 ATS.

### Gate 2 — Logs (default YES for events)

Log every meaningful user or business event (request handled, job run, state change, decision, failure) as one structured line with its inputs and key values, so someone can rebuild what happened, in order, without a redeploy. Never log inside hot loops or per tick; count those in a metric or log once per batch.

Example: one INFO line per delivery attempt with `delivery_id`, `target`, `attempt`, `outcome`.

### Gate 3 — Traces (default YES for user flows)

Add a span for each meaningful stage of a user flow, with key IDs as attributes. Skip tracing only for internal work with no per-request flow. The service sets only its head-sampling `ratio` (the share of new traces kept); keeping every error trace is the platform team's **tail sampling** (the collector decides after a trace ends, so it can keep all errors).

Example: span `webhook.deliver` with `delivery_id`, ratio 0.1.

### Gate 4 — Dashboard (default: the generic dashboard is enough)

Never copy panels of the [generic dashboard](/docs/standards/observability/index.md#terms). Only custom metrics from Gate 1 earn a curated dashboard; their log evidence (the failure classes from Gates 2 and 5) sits beside them. No custom metrics means no curated dashboard. See [Dashboards](/docs/standards/grafana-dashboards/index.md).

Example: "Retry queue depth" panel in a detail row.

### Gate 5 — Alerts (default NO)

An alert must pass all three checks:

1. **Nothing heals it already.** If an autoscaler, restart policy or retry loop fixes the condition, do not alert on it. Alert when that mechanism is exhausted.
2. **Someone can act.** The runbook must say what to do. "Watch it" means `info` at most, or no alert.
3. **Someone owns it.** The owner team in `observability/overview.md` agrees to receive it. Write `pending` in the Gate 5 Owner column until `overview.md` (written later, with `grafana-runbook`) names the owner team; an alert set cannot merge while its owner is pending. Delivery is the platform team's routing; if `{platform}` has no route yet, ask them.

| Condition                             | Already healed by         | Alert?                          |
| ------------------------------------- | ------------------------- | ------------------------------- |
| CPU 80%, autoscaler on                | autoscaling               | No                              |
| CPU 80%, no autoscaler                | nothing                   | `warning`                       |
| Autoscaler at max and still saturated | the autoscaler has failed | `critical`                      |
| One pod restart                       | restart policy            | No; a sustained crash loop: yes |
| Retry queue growing despite retries   | retries are losing        | Yes                             |

For each alert that survives, fill every Gate 5 column of the template ([tiers and types](/docs/standards/observability/alerts.md)); the **noise budget** is how often you expect it to fire, e.g. "≤2 pages/month". An alert that fires more often than someone acts fails check 2.

### Gate 6 — Alert-set folders

Each Gate 5 alert becomes one folder, `observability/alerts/<slug>/`, with its tier files and `runbook.md`, in the same PR. Record a short slug next to each alert name, using only `a-z`, `0-9` and `-`: `Retry queue saturated` → `retry-queue`. Its length limit: [Shipping](/docs/standards/observability/shipping.md#structural-checks); if the platform is not known yet, keep the slug ≤ 12 and ≤ 23 − len(service) characters, which fits any platform name of up to 6 characters, and recheck once it is known.

## Review checklist

- [ ] The feature has a block in `SIGNALS.md` with all six gates answered.
- [ ] Every answer has a one-line reason; a bare YES or NO fails review.
- [ ] Every YES names its metric, log event, span, panel or folder, and its cost (ATS, log volume or sampling).
- [ ] Every Gate 5 row is fully filled (Owner may be `pending`).
- [ ] Everything named exists in the PR: each metric in the service code (unless its Gate 1 row says `planned`), each Gate 6 folder under `observability/alerts/`.
- [ ] No unbounded metric labels, no logs in hot loops, a sampling ratio for every trace.
