# Observability Standards

How this service decides what to measure, and how it keeps its Grafana dashboards, alerts and runbooks as files in this repo.

## Terms

Examples in these docs use a made-up service: platform `tracker`, service `zinc`, module `webhook`.

- **Service tree (LPSM)**: four labels that say where something runs: `landscape` (the environment, e.g. `pichu` = development, `raichu` = production), `platform` (the product), `service` (usually one repo, like this one) and `module` (one component, e.g. `api`). The linked page also defines a cluster level (LCPSM); telemetry labels leave it out. Naming rules: [Service Tree](/docs/standards/service-tree/index.md).
- **Platform team**: the people who run Grafana, the collectors and alert routing. Not the same thing as the `platform` label.
- **Stamping**: adding the LPSM labels automatically (rule 1 below).
- **Signal**: one metric, log event or trace span. Their query languages are PromQL (metrics), LogQL (logs, in Loki) and TraceQL (traces, in Tempo).
- **Active time series (ATS)**: one metric name with one set of label values. Metrics storage costs grow with the ATS count.
- **SLO** (service level objective): the target share of good events over a 30-day window, e.g. 99.9% of requests succeed. The **error budget** is 1 − SLO, here 0.001. A service writes its SLOs in its `SIGNALS.md` answers (Gate 5).
- **Burn rate**: how many times faster than allowed the error budget is being spent. 14.4× for 1 hour spends about 2% of the 30-day budget; 6× for 6 hours spends about 5%.
- **The six gates**: six questions you answer for each feature to decide its signals. See [Signal decisions](/docs/standards/observability/signals.md).
- **Severity tier**: `critical` (act now; usually pages on-call), `warning` (act in working hours; usually the team channel) or `info` (worth recording; nobody acts).
- **Alert set**: one folder under `observability/alerts/` holding one to three tier files and their runbook. See [Alerts](/docs/standards/observability/alerts.md).
- **Generic dashboard**: a dashboard the platform team runs for every service: request rate, errors, duration, SLO and resource use, filtered by LPSM. This service shows up in it automatically once its metrics carry LPSM labels. It is not in this repo.
- **Curated dashboard**: a dashboard this repo owns, for this service's own custom metrics.
- **Grafana Operator**: a Kubernetes controller that creates Grafana folders, dashboards and alert rules from Kubernetes resources.
- **Primordial chart**: a Helm chart, separate from the app chart, that turns `observability/` into Grafana Operator resources. It is installed on Primordial, the cluster that runs the Grafana Operator. This repo has none yet; see [Shipping](/docs/standards/observability/shipping.md).

## Values the platform team gives you

This repo does not contain these values, so the docs use the placeholder shown. Ask the platform team for each value except `{repo-url}`, which is your repo's web URL plus `/blob/<default branch>`. Record each value in the places the last column names. Until a value is known, keep its placeholder. A dashboard cannot merge while `{platform}` or `{service}` is unknown (its uid needs them); for when an alert set can merge, see [Gate 5](/docs/standards/observability/signals.md#gate-5--alerts-default-no).

| Value                                                                                         | Placeholder                                                                                                       | Recorded in                                                                                                                                                    |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This service's platform, service and modules                                                  | `{platform}`, `{service}`, `{module}`                                                                             | `observability/SIGNALS.md` title; modules in `overview.md` (How it works)                                                                                      |
| Kubernetes namespace and workload                                                             | `{namespace}`, `{workload}` (e.g. `deployment/zinc-webhook`)                                                      | `observability/overview.md` (Common commands)                                                                                                                  |
| Owner team and chat channel                                                                   | `{team}`, `{#channel}`                                                                                            | `observability/overview.md` (Links)                                                                                                                            |
| Grafana URL, generic dashboard uid and the query that scopes it                               | `{grafana-url}`, `{generic-dashboard-uid}`, `{generic-dashboard-vars}` (its `var-…=…` URL query for this service) | `observability/overview.md` (Links); the uid also in dashboard text panels                                                                                     |
| Web URL of this repo's files on its default branch                                            | `{repo-url}` (e.g. `https://github.com/example/zinc/blob/main`)                                                   | the primordial chart's values; dashboard text panels                                                                                                           |
| OTLP (OpenTelemetry Protocol) collector endpoint, per landscape                               | `{otlp-endpoint}`                                                                                                 | each landscape's app config ([OpenTelemetry](/docs/standards/observability/otel.md))                                                                           |
| Metrics and logs datasource uids, per landscape                                               | `{metrics-datasource-uid}`, `{logs-datasource-uid}`                                                               | the primordial chart's values                                                                                                                                  |
| Loki and Tempo versions                                                                       | —                                                                                                                 | the `loki` and `tempo` images in `.claude/skills/grafana-dashboards/sandbox/compose.yaml` ([Dashboard sandbox](/docs/standards/grafana-dashboards/sandbox.md)) |
| Primordial namespace and Grafana `instanceSelector`, per landscape                            | `{grafana-namespace}`, `{instance-selector}`                                                                      | the primordial chart's values ([Shipping](/docs/standards/observability/shipping.md#where-things-run))                                                         |
| `helm-wrapper` (the Helm library the primordial chart builds on) chart repository and version | —                                                                                                                 | the primordial chart's `Chart.yaml`                                                                                                                            |
| Faro collector URL, app id and stack id                                                       | —                                                                                                                 | the frontend's config ([Faro](/docs/standards/observability/faro.md))                                                                                          |

The platform team also owns, outside this repo: who is notified for each tier and landscape (routing), on-call, [trace tail sampling](/docs/standards/observability/signals.md#gate-3--traces-default-yes-for-user-flows), and deploying the primordial chart.

## Pages

| Page                                                               | Read it when you…                                                  |
| ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| [Signal decisions](/docs/standards/observability/signals.md)       | add or change a feature and must decide its metrics, logs, traces  |
| [Dashboards](/docs/standards/grafana-dashboards/index.md)          | write or change a dashboard                                        |
| [Dashboard sandbox](/docs/standards/grafana-dashboards/sandbox.md) | render a dashboard locally before merge                            |
| [Alerts](/docs/standards/observability/alerts.md)                  | write an alert set or one alert file                               |
| [Runbooks](/docs/standards/observability/runbooks.md)              | write a runbook or the system overview                             |
| [Shipping](/docs/standards/observability/shipping.md)              | build or change the chart that turns `observability/` into Grafana |
| [OpenTelemetry](/docs/standards/observability/otel.md)             | configure logs, metrics and traces in a backend service            |
| [Faro](/docs/standards/observability/faro.md)                      | add telemetry to a Next.js or Flutter frontend                     |

Skills, in the order you use them: `observability-check` (decide signals) → `grafana-dashboards` → `grafana-alert-set`, which runs `grafana-alert` (one file) and then `grafana-runbook` inside it.

## Folder layout

```text
observability/
├── index.md            # points here
├── SIGNALS.md          # the six-gate answers, one block per feature
├── overview.md         # system overview that every runbook links to
├── dashboards/         # log-notes.md from the first log review; dashboards once Gate 4 says yes
│   ├── README.md       # keeps the folder in git
│   ├── overview.json
│   ├── .lint           # exclusions for dashboard-linter (Grafana's dashboard linter), each with a reason
│   └── log-notes.md    # what the stored log lines look like
└── alerts/
    ├── README.md       # keeps the folder in git
    └── <slug>/         # one alert set: tier files and runbook.md
```

Start empty. Add a dashboard or alert only when a gate in `SIGNALS.md` says yes.

## Three rules

1. **Labels are stamped, never written.** Alert and dashboard files hold plain Grafana content: no Kubernetes wrapper and no LPSM label blocks. Selecting LPSM labels in a query, such as `{service="zinc"}`, is expected. The primordial chart stamps alerts. For metrics, logs and traces, the OTel library sets the values from the service's config, and the collector (Grafana Alloy, an agent on each Kubernetes node) turns them into labels. The app chart, if the repo has one, sets none.
2. **Strict on metrics and alerts, liberal on logs and traces**: [why and how](/docs/standards/observability/signals.md#cost-strict-on-metrics-liberal-on-logs-and-traces).
3. **Rules never decide who gets paged**, e.g. no `team:` or `receiver:` label and no contact point in a tier file. The platform team's routing reads the `severity` and LPSM labels and decides who is notified in each landscape. The same rule file works in every landscape.

## Check a signal exists before you use it

Before you chart or alert on a metric, label or log stream, open Grafana's **Explore** view and run the query against the real landscape. A series that is not collected shows "No data". Check metrics, logs and traces separately: a trace panel stays empty until the service emits spans.

## Further reading

- [Grafana alerting: labels and annotations](https://grafana.com/docs/grafana/latest/alerting/fundamentals/alert-rules/annotation-label/)
- [Google SRE workbook: alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
