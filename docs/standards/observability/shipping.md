# Shipping Observability Files to Grafana

The files in `observability/` are plain Grafana content. The service's **primordial chart** turns them into Grafana Operator resources (terms: [Observability Standards](/docs/standards/observability/index.md#terms)). This repo has no primordial chart yet; when you add one at `infra/primordial_chart/`, it must follow this page. **Until it exists, nothing renders these files, so the reviewer runs the [structural checks](#structural-checks) by hand.** You need `helm-wrapper`'s repository (the Helm library the chart builds on) from the platform team before you can write this chart; its README has the helpers.

## Where things run

- **One Grafana per landscape.** The chart is installed once per landscape, onto Primordial, into that landscape's namespace `{grafana-namespace}`. Each install targets that landscape's Grafana through the operator's `instanceSelector` (`{instance-selector}`; both values from the [platform team](/docs/standards/observability/index.md#values-the-platform-team-gives-you)). Installs never share a Grafana, so uids and names carry no landscape and never collide.
- Each install stamps its landscape on the alert rules and points them at that landscape's datasources, so one rule file works everywhere and `expr` never selects `landscape`. Dashboards use the `$landscape` variable.
- The app chart, `infra/root_chart/`, only runs the service. It never renders observability files.
- Build the rendering with `helm-wrapper`, not with CI scripts.

## The chart copy

Helm can only read files inside its chart folder and rejects symlinks that point outside it. This repo has no copy step yet. The chart build must copy `observability/` to `infra/primordial_chart/files/observability/` before every lint, template, package or publish, and `.gitignore` must hold `infra/primordial_chart/files/`. Add the copy as a `primordial_chart:copy` task in `tasks/Taskfile.helm.yaml` that the chart's other tasks depend on (a chart's tasks are named `<chart folder>:<verb>`: [Helm standard](/docs/standards/helm/index.md), [Taskfile conventions](/docs/standards/taskfile/index.md)). Never edit or commit the copy; `observability/` stays the source.

## One file → one resource

| Source file                     | Rendered resource                                                                                    |
| ------------------------------- | ---------------------------------------------------------------------------------------------------- |
| (the service itself)            | One `GrafanaFolder`, uid `<platform>-<service>-folder`, parent folder `<platform>`                   |
| `dashboards/<purpose>.json`     | One `GrafanaDashboard`, uid `<platform>-<service>-<purpose>`                                         |
| `alerts/<slug>/<severity>.yaml` | One `GrafanaAlertRuleGroup`, name `<platform>-<service>-<slug>-<severity>`, holding exactly one rule |

- Every resource's `metadata.name` equals its uid. Every dashboard and rule group sits in the service folder: `folderRef` is the `GrafanaFolder`'s `metadata.name`, `<platform>-<service>-folder`.
- The platform team creates the parent `<platform>` folder once; the operator retries until it exists. Nobody creates folders by hand.
- The `-folder` suffix keeps the folder uid apart from dashboard uids; Grafana keeps both in one namespace.
- Implement it as one `.Files.Glob` loop: parse each file as one map (`fromYaml`), check it, emit one resource. No arrays built across files, no YAML surgery. The label merge is one call, e.g. `mergeOverwrite (dict "severity" (base $path | trimSuffix ".yaml")) $.Values.serviceTree`.

## What the chart adds to each alert

The chart renders every rule the same way, so every rule has query `A` and condition `B` below.

| Rendered field                                                                   | Comes from                                                                                                                                                                                                                                                                                                                                                                 |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `severity` label and the 🚨/⚠️/ℹ️ title prefix                                   | The file name                                                                                                                                                                                                                                                                                                                                                              |
| Rule `uid` and group name                                                        | `<platform>-<service>-<slug>-<severity>`                                                                                                                                                                                                                                                                                                                                   |
| `metadata.namespace`, `instanceSelector`                                         | This landscape's `{grafana-namespace}` and `{instance-selector}`                                                                                                                                                                                                                                                                                                           |
| `folderRef`, `interval: 1m`                                                      | The service folder; a fixed evaluation interval                                                                                                                                                                                                                                                                                                                            |
| `condition: B`, `noDataState: OK`, `execErrState: Error`                         | Fixed values                                                                                                                                                                                                                                                                                                                                                               |
| `data` query `A`: the `expr`, instant, `relativeTimeRange: { from: 600, to: 0 }` | The tier file                                                                                                                                                                                                                                                                                                                                                              |
| `data` query `A`: `datasourceUid`                                                | `datasource: metrics` or `logs` → this landscape's `{metrics-datasource-uid}` or `{logs-datasource-uid}`                                                                                                                                                                                                                                                                   |
| `data` query `B`                                                                 | Fixed: the math expression in the example below, true when `$A` is a number, NaN or infinite. A plain query condition fires only on non-zero values; `B` makes any series `A` returns fire, even with value 0, as in Prometheus (which the offline `promtool` test uses); the [sandbox](/docs/standards/grafana-dashboards/sandbox.md#check-the-alert-condition) proves it |
| `landscape`, `platform`, `service`, `module` labels                              | The chart's `serviceTree` values                                                                                                                                                                                                                                                                                                                                           |
| `runbook_url`                                                                    | `{repo-url}/observability/alerts/<slug>/runbook.md`                                                                                                                                                                                                                                                                                                                        |
| `__dashboardUid__`, `__panelId__`                                                | `panel` set → `<platform>-<service>-overview` and that panel id as a string; unset → `{generic-dashboard-uid}`                                                                                                                                                                                                                                                             |

**Example.** The `critical.yaml` in [Alerts](/docs/standards/observability/alerts.md#the-tier-file), with `serviceTree: {landscape: raichu, platform: tracker, service: zinc, module: webhook}` and the example values namespace `raichu-grafana`, instance selector `{dashboards: raichu}`, metrics datasource uid `raichu-metrics` and repo URL `https://github.com/example/zinc/blob/main`, must render exactly as:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaAlertRuleGroup
metadata:
  name: tracker-zinc-retry-queue-critical
  namespace: raichu-grafana
spec:
  instanceSelector:
    matchLabels: { dashboards: raichu }
  folderRef: tracker-zinc-folder
  interval: 1m
  rules:
    - uid: tracker-zinc-retry-queue-critical
      title: 🚨 Retry queue saturated
      condition: B
      for: 10m
      noDataState: OK
      execErrState: Error
      data:
        - refId: A
          relativeTimeRange: { from: 600, to: 0 }
          datasourceUid: raichu-metrics
          model: { expr: 'webhook_retry_queue_depth{service="zinc"} > 5000', instant: true }
        - refId: B
          datasourceUid: __expr__
          model: { type: math, expression: 'is_number($A) || is_nan($A) || is_inf($A)' }
      labels:
        severity: critical
        landscape: raichu
        platform: tracker
        service: zinc
        module: webhook
      annotations:
        summary: 'Retry queue at {{ $values.A.Value }}; deliveries dropping'
        description: 'Check downstream health; the queue drains only if endpoints are up.'
        runbook_url: https://github.com/example/zinc/blob/main/observability/alerts/retry-queue/runbook.md
        __dashboardUid__: tracker-zinc-overview
        __panelId__: '2'
```

## Structural checks

Check for each of these errors (by hand until the chart exists; the chart then enforces them with Helm's `required`/`fail`, so `helm template` stops before emitting anything):

- a tier file is not named `critical.yaml`, `warning.yaml` or `info.yaml`;
- a tier file breaks [the tier file](/docs/standards/observability/alerts.md#the-tier-file) table: a required field is missing, the title is too long, or `panel` is not an integer;
- `panel` is not the `id` of a panel in `observability/dashboards/overview.json`;
- a uid is longer than 40 characters, Grafana's limit. So `len("<platform>-<service>-<slug>-<severity>") ≤ 40`, which with `critical` leaves the slug `29 − len(platform) − len(service)` characters: 18 for `tracker`/`zinc`, so `tracker-zinc-retry-queue-critical` (33) fits. Dashboard uids `<platform>-<service>-<purpose>` follow the same limit;
- an alert set has no `runbook.md`;
- a dashboard is not valid JSON or its `uid` is not `<platform>-<service>-<purpose>`;
- a `serviceTree` value is missing.

A clean render proves the structure only. Whether a query returns data is checked in the [dashboard sandbox](/docs/standards/grafana-dashboards/sandbox.md) and by the alert [validation](/docs/standards/observability/alerts.md#validation) steps.
