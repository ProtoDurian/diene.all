# Observability Standards

How this service decides what to measure, and how it keeps its Grafana dashboards, alerts and runbooks as files in this repo.

## Terms

- **Service tree (LPSM)**: four labels that say where something runs: `landscape` (the environment, e.g. `pichu` = development, `raichu` = production), `platform` (the product), `service` (usually one repo, like this one) and `module` (one component, e.g. `api`). Naming rules: [Service Tree](docs/standards/service-tree/index.md).
- **Stamping**: the deployment adds the LPSM labels to every metric, log line, trace and alert. You never type them into an alert or dashboard file.
- **Signal**: one metric, log event or trace span.
- **Active time series (ATS)**: one metric name with one set of label values. Metrics storage costs grow with the ATS count.
- **The six gates**: six questions you answer for each feature to decide its signals. See [Signal decisions](docs/standards/observability/signals.md).
- **Severity tier**: `critical`, `warning` or `info`. An alert's tier is its file name (table below).
- **Alert set**: one folder under `observability/alerts/` holding one to three tier files and their runbook. See [Alerts](docs/standards/observability/alerts.md).
- **Generic dashboard**: a dashboard the platform team runs for every service. It shows standard request and resource signals, filtered by LPSM. It is not in this repo.
- **Curated dashboard**: a dashboard this repo owns, for this service's own custom metrics.
- **Grafana Operator**: a Kubernetes controller that creates Grafana folders, dashboards and alert rules from Kubernetes resources.
- **Primordial chart**: this service's Helm chart for the Grafana resources. It reads `observability/` and is deployed to Primordial, the cluster that runs the Grafana Operator. See [Shipping](docs/standards/observability/shipping.md).

## Pages

| Page                                                              | Read it when you…                                                  |
| ----------------------------------------------------------------- | ------------------------------------------------------------------ |
| [Signal decisions](docs/standards/observability/signals.md)       | add or change a feature and must decide its metrics, logs, traces  |
| [Alerts](docs/standards/observability/alerts.md)                  | write an alert set or one alert file                               |
| [Runbooks](docs/standards/observability/runbooks.md)              | write a runbook or the system overview                             |
| [Dashboards](docs/standards/grafana-dashboards/index.md)          | write or change a dashboard                                        |
| [Dashboard sandbox](docs/standards/grafana-dashboards/sandbox.md) | render a dashboard locally before merge                            |
| [Shipping](docs/standards/observability/shipping.md)              | build or change the chart that turns `observability/` into Grafana |
| [OpenTelemetry](docs/standards/observability/otel.md)             | configure logs, metrics and traces in a backend service            |
| [Faro](docs/standards/observability/faro.md)                      | add telemetry to a Next.js or Flutter frontend                     |

Skills, in the order you use them: `observability-check` (decide signals) → `grafana-dashboards` → `grafana-alert-set` → `grafana-alert` (one file) → `grafana-runbook`.

## Folder layout

```text
observability/
├── SIGNALS.md          # the six-gate answers, one block per feature
├── overview.md         # system overview that every runbook links to
├── dashboards/         # curated dashboards; empty until Gate 4 says yes
│   └── overview.json
└── alerts/
    └── <alert-slug>/   # one alert set (see Alerts)
```

Start empty. Add a dashboard or alert only when a gate in `SIGNALS.md` says yes.

## Three rules

1. **Labels are stamped, never written.** Alert and dashboard files hold plain Grafana content: no Kubernetes wrapper, no LPSM labels. The primordial chart adds them to alerts. For metrics, logs and traces, the deployment puts the LPSM values on the pod, and the collector copies them onto every sample.
2. **Strict on metrics and alerts, liberal on logs and traces.** Metrics cost ATS for as long as they exist, and alerts cost a person's attention, so both default to NO. Logs and traces default to YES for user and business events; the platform samples them to control volume.
3. **Rules never decide who gets paged.** The platform's routing reads the `severity` and LPSM labels and decides who is notified in each landscape. The same rule file works in every landscape.

## Severity tiers

| Tier          | Meaning                                     | Usual delivery         |
| ------------- | ------------------------------------------- | ---------------------- |
| `critical` 🚨 | Act now: users are affected or soon will be | Pages on-call          |
| `warning` ⚠️  | Act in working hours                        | Team channel, no page  |
| `info` ℹ️     | Worth recording; nobody acts                | Archive channel / none |

## How each file is checked

| File                   | Checked automatically when the chart renders                                 | Checked by the reviewer                                |
| ---------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------ |
| `SIGNALS.md`           | —                                                                            | All six gates answered, justified and costed           |
| Alert set              | Required fields, tier file names, title ≤48 characters, `runbook.md` present | Tiers >20% apart; `panel` id exists in `overview.json` |
| Runbook, `overview.md` | —                                                                            | Every section filled                                   |
| Dashboard              | Valid JSON, expected `uid`                                                   | Lint, sandbox render and visual checklist              |
| Deployed alert         | —                                                                            | Grafana **Preview** shows data before merge            |

## Check a signal exists before you use it

Before you chart or alert on a metric, label or log stream, open Grafana's **Explore** view and run the query against the real landscape. A series that is not collected shows "No data". Check metrics, logs and traces separately: a trace panel stays empty until the service emits spans.

## Further reading

- [Grafana alerting: labels and annotations](https://grafana.com/docs/grafana/latest/alerting/fundamentals/alert-rules/annotation-label/)
- [Google SRE workbook: alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
