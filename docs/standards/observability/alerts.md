# Alerts

How to write the files of an alert set. Whether an alert should exist at all is Gate 5 of [Signal decisions](docs/standards/observability/signals.md). How the files become Grafana alert rules is in [Shipping](docs/standards/observability/shipping.md).

## One alert set = one folder

An alert set covers one measured thing, with one to three severity tiers and one runbook:

```text
observability/alerts/webhook-retry-queue/
├── critical.yaml
├── warning.yaml
└── runbook.md
```

- **The file name is the severity**: `critical.yaml`, `warning.yaml` or `info.yaml`. There is no severity field, so the two can never disagree.
- **Use only the tiers you need**: one file for a plain failure, two for capacity or slow decline, three only when the trend itself is worth recording.
- **Tiers need real gaps**: thresholds more than 20% apart. Example: warning at 4000, critical at 5000.
- **The folder name is the slug** (rule in [Gate 6](docs/standards/observability/signals.md#gate-6--alert-set-folders)).
- **Every Gate 5 YES has a folder, and every folder has a Gate 5 YES.** No Gate 5 YES at all means no `alerts/<slug>/` folders, which is fine.
- **One page per root cause**: if two sets fire for the same cause, keep the one users feel (the symptom) and demote or delete the other. One burn-rate set usually replaces several hand-made error and latency sets.

## The tier file

One flat YAML map per file. Start from [the alert template](.claude/skills/grafana-alert-set/templates/alert-template.yaml).

```yaml
title: Webhook retry queue saturated
datasource: metrics
expr: webhook_retry_queue_depth{service="zinc"} > 5000
for: 10m
summary: 'Retry queue at {{ $values.A }}; deliveries dropping'
description: 'Check downstream health; the queue drains only if endpoints are up.'
panel: 2
```

| Field         | Where people see it                            | Rule                                                                                               |
| ------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `title`       | The notification title: lock screen, chat line | The symptom, ≤48 characters, no emoji (🚨/⚠️/ℹ️ is added from the file name)                       |
| `datasource`  | —                                              | `metrics` (PromQL) or `logs` (LogQL)                                                               |
| `expr`        | —                                              | A query that is true while the problem lasts; its shape comes from the type below                  |
| `for`         | —                                              | How long it must stay true before firing                                                           |
| `summary`     | First line of the notification body            | What and how bad; put the value in with `{{ $values.A }}`                                          |
| `description` | Alert detail view                              | The first thing to do                                                                              |
| `panel`       | The "view panel" link                          | A panel id in `observability/dashboards/overview.json`; leave it out to link the generic dashboard |

Front-load the symptom: `Retry queue saturated`, not `The webhook delivery retry queue has become saturated`. Keep LPSM names and query values out of the title. Route and silence by the `severity` label, never by emoji. Moving an alert to another tier changes its name, so silences on the old name stop working.

## Pick the alert type

The type decides the shape of `expr`. Everything else stays the same.

| Type                | `expr` shape                                                                                 | Use for                                               | Avoid when                              |
| ------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------- |
| Static threshold    | `metric > N` plus `for`                                                                      | Hard limits: disk %, queue depth, cert expiry         | The metric rises and falls with the day |
| Absence / heartbeat | `absent(metric)` or `rate(metric[15m]) == 0`                                                 | Scrape gone, cron did not run, consumer silent        | Scrapes are flaky (fix those first)     |
| Event (logs)        | `sum(count_over_time({service="zinc"} \|= "panic" [5m])) > 0`, `for: 0m`, `datasource: logs` | Panics, out-of-memory kills, corruption markers       | A metric exists for it (use the metric) |
| SLO burn rate       | Error ratio over two windows (example below)                                                 | The preferred page for user-facing errors and latency | Internal-only signals                   |
| Seasonal deviation  | This week vs last week, with a floor (example below)                                         | Traffic-shaped metrics: volume, cost                  | Under 2 weeks of history                |
| Forecast            | `predict_linear(metric[6h], 4*3600) < limit` plus a threshold backstop                       | Slow resources: disk full in 4 hours, quota           | Fast, spiky metrics                     |
| Outlier             | One instance more than 3 standard deviations from its peers                                  | One pod unlike the others                             | Fewer than 4 peers                      |

**SLO burn rate** (99.9% SLO, so the error budget is 0.001). This fast-burn critical tier fires when both windows burn budget 14.4× faster than allowed; a slow-burn warning tier uses 6× over 30m and 6h:

```text
( sum(rate(http_requests_total{service="zinc",status=~"5.."}[5m]))
  / sum(rate(http_requests_total{service="zinc"}[5m])) ) > (14.4 * 0.001)
and
( sum(rate(http_requests_total{service="zinc",status=~"5.."}[1h]))
  / sum(rate(http_requests_total{service="zinc"}[1h])) ) > (14.4 * 0.001)
```

**Seasonal deviation** (traffic below half of last week, smoothed over 1h, and only when last week had real traffic):

```text
avg_over_time(sum(rate(webhook_deliveries_total{service="zinc"}[5m]))[1h:])
  / avg_over_time(sum(rate(webhook_deliveries_total{service="zinc"}[5m]))[1h:] offset 1w) < 0.5
and
avg_over_time(sum(rate(webhook_deliveries_total{service="zinc"}[5m]))[1h:] offset 1w) > 1
```

**Forecast with backstop** (two tier files in one set):

```text
warning.yaml:  predict_linear(dlq_disk_free_bytes{service="zinc"}[6h], 4*3600) < 0
critical.yaml: dlq_disk_used_ratio{service="zinc"} > 0.95
```

**Outlier**:

```text
(
  webhook_delivery_duration_seconds{service="zinc", quantile="0.99"}
  - on() group_left avg(webhook_delivery_duration_seconds{service="zinc", quantile="0.99"})
)
> on() group_left 3 * stddev(webhook_delivery_duration_seconds{service="zinc", quantile="0.99"})
```

Trace-based alerts: alert on the metrics the tracing pipeline derives from spans (request rate, errors, duration), not on trace queries.

**One alert cannot combine metrics and logs.** A tier file has one `datasource` and one `expr`. To confirm a metric with logs, put a metric alert and a log alert in the same set.

## Validation

There is no automated test that fires an alert. Three checks instead:

1. **Render**: the chart refuses to render a broken set (list in [Shipping](docs/standards/observability/shipping.md#structural-checks)).
2. **Review**: tiers more than 20% apart, `panel` points at the right panel, runbook complete, slug correct.
3. **Preview before merge**: open the rule in Grafana and press **Preview**. It must return data and evaluate. This is the only check that catches an alert that can never fire, such as a misspelled metric. Say in the PR that you did it.
