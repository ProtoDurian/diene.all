# Shipping Observability Files to Grafana

The files in `observability/` are plain Grafana content. The service's **primordial chart** turns them into Grafana Operator resources (terms: [Observability Standards](/docs/standards/observability/index.md#terms)). This repo has no primordial chart yet; when you add one at `infra/primordial_chart/`, it must follow this page. **Until it exists, nothing renders these files, so the reviewer runs the [structural checks](#structural-checks) by hand.**

## Where things run

- **Landscapes:** one Grafana serves every landscape. The chart is installed once per landscape, onto Primordial. Each install stamps its landscape on the alert rules and points them at that landscape's datasources, so one rule file works everywhere. Dashboards and the folder carry no landscape (they use the `$landscape` variable), so every install renders them the same.
- The app chart, `infra/root_chart/`, only runs the service. It never renders observability files.
- Alerts become **Grafana-managed alert rules**, not Prometheus `PrometheusRule` resources.
- Build the rendering with the `helm-wrapper` Helm library (reusable templates the chart depends on; repository and version from the [platform team](/docs/standards/observability/index.md#values-the-platform-team-gives-you)), not with CI scripts or kustomize.

## The chart copy

Helm can only read files inside its chart folder and rejects symlinks that point outside it. So the chart build copies `observability/` into a gitignored folder inside `infra/primordial_chart/` before every lint, template, package or publish. Add that folder to `.gitignore`. Never edit or commit the copy; `observability/` stays the source.

## One file → one resource

| Source file                     | Rendered resource                                                                                                |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| (the service itself)            | One `GrafanaFolder`, uid `<platform>-<service>-folder`, parent folder `<platform>`                               |
| `dashboards/<purpose>.json`     | One `GrafanaDashboard`, uid `<platform>-<service>-<purpose>`                                                     |
| `alerts/<slug>/<severity>.yaml` | One `GrafanaAlertRuleGroup`, name `<landscape>-<platform>-<service>-<slug>-<severity>`, holding exactly one rule |

- Every dashboard and rule group sits in the service folder (`folderRef`). The platform team creates the parent `<platform>` folder once; the operator retries until it exists. Nobody creates folders by hand.
- The `-folder` suffix keeps the folder uid apart from dashboard uids; Grafana keeps both in one namespace.
- Implement it as one `.Files.Glob` loop: parse each file as one map (`fromYaml`), check it, emit one resource. No arrays built across files, no YAML surgery. The label merge is one call, e.g. `mergeOverwrite (dict "severity" (base $path | trimSuffix ".yaml")) $.Values.serviceTree`.

## What the chart adds to each alert

| Rendered field                                                                                           | Comes from                                                                                                     |
| -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `severity` label and the 🚨/⚠️/ℹ️ title prefix                                                           | The file name                                                                                                  |
| Rule `uid`                                                                                               | `<landscape>-<platform>-<service>-<slug>-<severity>`, at most 40 characters                                    |
| `folderRef`, `interval: 1m`                                                                              | The service folder; a fixed evaluation interval                                                                |
| `condition: A`, `refId: A`, `relativeTimeRange`, `noDataState: OK`, `execErrState: Error`, instant query | Fixed values                                                                                                   |
| `datasourceUid`                                                                                          | `datasource: metrics` or `logs` → this landscape's `{metrics-datasource-uid}` or `{logs-datasource-uid}`       |
| `landscape`, `platform`, `service`, `module` labels                                                      | The chart's `serviceTree` values                                                                               |
| `runbook_url`                                                                                            | The repo's web URL + `/blob/main/observability/alerts/<slug>/runbook.md`                                       |
| `__dashboardUid__`, `__panelId__`                                                                        | `panel` set → `<platform>-<service>-overview` and that panel id as a string; unset → `{generic-dashboard-uid}` |

**Example.** The `critical.yaml` in [Alerts](/docs/standards/observability/alerts.md#the-tier-file), with `serviceTree: {landscape: raichu, platform: tracker, service: zinc, module: webhook}` and the example metrics datasource uid `raichu-metrics`, must render exactly as:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaAlertRuleGroup
metadata:
  name: raichu-tracker-zinc-retry-queue-critical
spec:
  folderRef: tracker-zinc-folder
  interval: 1m
  rules:
    - uid: raichu-tracker-zinc-retry-queue-critical
      title: 🚨 Retry queue saturated
      condition: A
      for: 10m
      noDataState: OK
      execErrState: Error
      data:
        - refId: A
          relativeTimeRange: { from: 600, to: 0 }
          datasourceUid: raichu-metrics
          model: { expr: 'webhook_retry_queue_depth{service="zinc"} > 5000', instant: true }
      labels:
        severity: critical
        landscape: raichu
        platform: tracker
        service: zinc
        module: webhook
      annotations:
        summary: 'Retry queue at {{ $values.A }}; deliveries dropping'
        description: 'Check downstream health; the queue drains only if endpoints are up.'
        runbook_url: https://github.com/example/zinc/blob/main/observability/alerts/retry-queue/runbook.md
        __dashboardUid__: tracker-zinc-overview
        __panelId__: '2'
```

## Structural checks

The chart uses Helm's `required` and `fail`, so `helm template` stops with an error, before emitting anything, when:

- a tier file is not named `critical.yaml`, `warning.yaml` or `info.yaml`;
- a tier file breaks [the tier file](/docs/standards/observability/alerts.md#the-tier-file) table: a required field is missing, the title is too long, or `panel` is not an integer;
- a rule uid or dashboard uid is longer than 40 characters, Grafana's limit. `raichu-tracker-zinc-retry-queue-critical` is exactly 40, so keep slugs short;
- an alert set has no `runbook.md`;
- a dashboard is not valid JSON or its `uid` is not `<platform>-<service>-<purpose>`;
- a `serviceTree` value is missing.

A clean render proves the structure only. Whether a query returns data is checked in the [dashboard sandbox](/docs/standards/grafana-dashboards/sandbox.md) and by the alert [validation](/docs/standards/observability/alerts.md#validation) steps.
