# Grafana Dashboards

How to write this service's dashboards as code, and how to check them by looking at them. Terms such as LPSM, generic and curated dashboard are defined in [Observability Standards](/docs/standards/observability/index.md#terms). Whether to write one at all is Gate 4 of [Signal decisions](/docs/standards/observability/signals.md).

**Never ship a dashboard you have not seen rendered.** Valid JSON can still be unreadable: wrong units, flat lines, "No data". Only a render shows that.

Dashboards are Grafana JSON files in `observability/dashboards/`, one per dashboard, `overview.json` first. Write them in the format Grafana's Dashboard → Export → JSON gives you (the classic schema, not the newer v2 schema). Copy exact JSON keys (variables, log panel options, `schemaVersion`) from [the sandbox fixture](/.claude/skills/grafana-dashboards/sandbox/dashboards/sample.json). The primordial chart turns each file into a Grafana dashboard ([Shipping](/docs/standards/observability/shipping.md)).

- `overview.json` (uid `<platform>-<service>-overview`) is the one alerts link to with their [`panel`](/docs/standards/observability/alerts.md#the-tier-file) field.
- A deep-dive gets its own file (uid `<platform>-<service>-<purpose>`), linked from the overview.

## Authoring rules

### Identity

- Pin the `uid` to `<platform>-<service>-<purpose>` ([length limit](/docs/standards/observability/shipping.md#structural-checks)), so re-applying never makes duplicates and alert links stay valid.
- Title: `<Service> — <Purpose>`, e.g. `Zinc — Retry overview`.
- Experiments are made in the Grafana UI only and never committed.

### Layout

- A row is one horizontal band of panels, made with `type: row` panels. Use **RED** (rate, errors, duration) for request-driven views and **USE** (utilization, saturation, errors) for resources.
- The first row (the **overview row**) answers "is it healthy?" in under 5 seconds, with trend panels and threshold colors. The rows below (**detail rows**) follow in the order a responder triages.
- Open with a text panel: purpose, audience, and links to `{repo-url}/observability/overview.md` ([placeholders](/docs/standards/observability/index.md#values-the-platform-team-gives-you)) and the generic dashboard (`/d/{generic-dashboard-uid}?{generic-dashboard-vars}`). The chart does not template dashboard JSON: write the real values into the JSON once you know them.
- Use more text panels to introduce sections where the triage order is not obvious from the panels alone, e.g. "If the error rate above is red, start here: which failure class is it?".
- One dashboard, one purpose. Put deep dives on a linked dashboard, not in row 12.

### Panels

- Every panel has a title, a description and an explicit unit (`reqps`, `ms`, `percentunit`). The description says what the panel shows and what bad looks like.
- Prefer trend panels. Use a stat or gauge only when one number is the whole story, e.g. days until a cert expires.
- Color by threshold: green is good, red is bad. For line colors to follow thresholds, set `fieldConfig.defaults.custom.gradientMode: scheme`. Exception: a split by category (e.g. `outcome` = `success`/`error`) gives each series a fixed color, error red. When every category is bad, color by severity: red worst, then orange, then yellow.
- Draw the alert threshold on any panel an alert links to.
- Legends show only the label that differs (`{{status}}`). Hide the legend on single-series panels; give each percentile its own panel or a clear legend name.

### Queries

- Use `$__rate_interval` in `rate()` and `increase()`. Rate first, then sum: `sum by (status) (rate(x_total[$__rate_interval]))`, never `rate(sum(...))`.
- Always aggregate by the labels you want to see; never a bare `sum(rate(...))` and never an unaggregated query. Aggregate gauges with `max` for saturation and `min` for headroom (the worst pod either way), `sum` for totals. (Dashboards only: an alert `expr` may sum everything.)
- Cap anything with many label values: `topk(10, ...)`.
- Show latency as percentiles (p50, p95, p99) from histograms, not averages.

### Variables and links

- `$landscape` is required on every dashboard, with `refresh: 2` (reload on time change), so one dashboard works whether a Grafana's datasource holds one landscape or several; in a one-landscape Grafana it has one value. Every query selects `landscape="$landscape"`, e.g. `sum by (outcome) (rate(x_total{service="zinc",landscape="$landscape"}[$__rate_interval]))`. Add the datasource variable `prometheus_datasource` labeled `Prometheus data source` and, with log panels, `loki_datasource` labeled `Loki data source`; these names pass strict lint. Set `editable: false`.
- Log panels also get a `$filter` text variable, applied as `|~ "$filter"`.
- Dashboard links (the links bar at the top) point at `{repo-url}/observability/overview.md` and, on a panel an alert links to, that alert's `{repo-url}/observability/alerts/<slug>/runbook.md`.

### Drill-down

A responder should click from "something is wrong" straight to the detail, not hunt through the folder tree.

- **Panel data links.** A panel that names a subject (a service, a status, a trace id) links to the next view. Use `${__value.raw}` or `${__field.labels.<x>}` in the link, e.g. a status tile links to `/d/<platform>-${__field.labels.service}-overview`, and a trace table links to that trace's logs. A log line links to its trace through the logs datasource's derived fields, which the platform team sets up (the sandbox's Loki datasource has one); that link is not in dashboard JSON.
- **Overview → deep-dive.** An overview links down to the detail: a `dashlist` panel scoped to the service folder `<platform>-<service>-folder` ([Shipping](/docs/standards/observability/shipping.md#where-things-run)), or stat tiles that link to `/d/<platform>-<service>-overview`. Each service overview links to its own deep-dive dashboards.
- **Carry context across the link.** Pre-fill the target's variables in the URL so it opens already scoped: `/d/tracker-zinc-retries?var-landscape=${landscape}`. Carry only `var-landscape` plus variables both dashboards have; never `var-service` or a cluster label, which the target does not have.

## Log and trace panels

The log line in the store is not what the app wrote: the logging library's JSON wrapper changes it, and the collector turns some fields into labels ("label promotion"). So build log panels from real stored lines:

1. **Sample** 50–100 stored lines per stream (a stream is the lines that share one set of log labels) for this service, from the real landscape with Grafana Explore. Include an error window. No access to the store? Push lines shaped like the template's logger (pino in the Bun template) into the sandbox's [logs and traces profile](/docs/standards/grafana-dashboards/sandbox.md#logs-and-traces-profile) and build the panel there. Mark it `UNVERIFIED` in its description until the real store is sampled, check it after the first deploy, and still create `log-notes.md` (step 9) saying nothing was sampled yet.
2. **Test the query engine.** LogQL support differs between Loki versions. Compare row counts for a raw query, `|~`, `| json`, `| logfmt` and `line_format`, and use only what works: on the real store, or in the profile pinned to the platform team's Loki version. Re-test when Loki is upgraded.
3. **Split by label first**: `sum by (module) (count_over_time({service="zinc"}[1h]))`. Parse line bodies only when labels cannot answer.
4. **Note each stream's format and level encoding.** One service often mixes formats (logfmt from one module, JSON from another, or JSON with stray plain lines). The level can look like:
   - `level=error` (logfmt);
   - `"level":"error"` (JSON with level names);
   - `"level":50` (JSON with level numbers, from pino, the Bun template's JSON logger: 30 info, 40 warn, 50 error);
   - `"severity":"ERROR"` (JSON that names the field `severity`);
   - a tab-separated word, e.g. `<time>⇥error⇥<message>` (console-style output);
   - a one-letter prefix with the date, e.g. `E0707` for an error on 7 July (klog, the Kubernetes logger);
   - none: plain text, where only markers such as `Fatal` or an emoji show the outcome.
5. **Filter the noise** with one targeted negative filter per noisy line type, e.g. `!= "grpc.health"`.
6. **One panel per failure class**, taken from the failures named in `SIGNALS.md` (Gates 2 and 5). A panel answers one question, named by the failure, not by the level: never a bare "Errors" or "Logs" panel. Typical panels by kind of service:

   | Kind of service                                                        | Panels (one question each)                                                                                                                                                           |
   | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
   | Request server (HTTP API)                                              | "Server errors (5xx)" · "Auth denials (401/403)" · "Slow requests (≥1s)", each a targeted line filter on the sampled access-log shape                                                |
   | Reconciler or controller                                               | "Reconcile failures" (scoped to its `module`) · "Git or repo failures" · "Processing timeline" (one line per unit of work)                                                           |
   | Batch or cron job                                                      | "Failed runs" · "Run outcomes" (the completion or summary lines) · the full run log (it is low-volume)                                                                               |
   | Host daemon (logs to the systemd journal, the Linux service log store) | "OOM (out of memory) and kernel crashes" · "Failed systemd units" · "Disk and I/O (read and write) errors", one class per panel, matched to the host alerts; never the whole journal |
   | Data collector                                                         | "Delivery failures (drops, push errors)", backing the delivery alerts · "Other collector errors" (the same level match minus the delivery class, so nothing hides)                   |
   | Explorer dashboard                                                     | the one generic panel set allowed: `$filter` over volume, errors and all lines                                                                                                       |

   Two rules make the set complete:
   - **Every alert has an evidence panel**: the panel that shows what happened when it fired, the first thing its runbook sends a responder to read. An alert that sets `panel` links straight to it; an alert that leaves `panel` out has the generic dashboard as its evidence.
   - **The class panels cover every error**: the last panel is "all errors minus the classes above", so a failure nobody predicted still shows up. An empty class panel on a healthy service is correct; say so in its description.

7. **Place log evidence in the row of the metric it explains**, or in the detail row directly under it when that metric is in the overview row; never in a generic logs row at the bottom.
8. **Rewrite lines to their key fields**: `| json | line_format "{{.level}} {{.msg}}"`. If `line_format` does not work on the engine, use `options.displayedFields`. Leave plain-text lines raw. Keep `prettifyLogMessage` off.
9. **Record what you found** (formats, level encoding, noise filters, engine limits, date) in `observability/dashboards/log-notes.md`.

Every logs panel: newest first, dedup on, a limit of about 100, time shown.

Add a slow- or error-trace table (TraceQL) only once the service emits spans. No dead panels.

## Test layers

A dashboard is tested in three layers, in this order. Each one catches what the one before it cannot.

1. **Sandbox with fake data: does the JSON render?** Before merge, load generated metrics ([`generate-metrics.awk`](/.claude/skills/grafana-dashboards/sandbox/generate-metrics.awk)) and, for log and trace panels, generated logs ([`generate-logs.awk`](/.claude/skills/grafana-dashboards/sandbox/generate-logs.awk)) and a sample trace in the [logs and traces profile](/docs/standards/grafana-dashboards/sandbox.md#logs-and-traces-profile) (Loki and Tempo). It proves every panel parses, runs and draws, not that the app's real data looks like the fake data. How: [Dashboard sandbox](/docs/standards/grafana-dashboards/sandbox.md) and [Check it before merge](#check-it-before-merge).
2. **Query check against real traffic (planned, not built yet).** An end-to-end test drives real requests through the app, each with a trace id, and every panel and alert query must return rows from that run. Until the tool exists, skip this layer. Goal draft: [diene-corpus pull request 63](https://github.com/ProtoDurian/diene-corpus/pull/63).
3. **Real stored lines, after deploy.** Sample the real store in Grafana Explore. A panel stays `UNVERIFIED` until it is checked against those lines, and what you found goes in `observability/dashboards/log-notes.md`. How: [Log and trace panels](#log-and-trace-panels), steps 1–9.

## Check it before merge

Run this for every new or changed dashboard file. Tools and the sandbox: [Dashboard sandbox](/docs/standards/grafana-dashboards/sandbox.md).

1. Parse and lint, from the repo root. `dashboard-linter` is Grafana's dashboard linter; `--strict` also fails on warnings.

   ```bash
   for dashboard in observability/dashboards/*.json; do
     jq empty "$dashboard" && dashboard-linter lint "$dashboard" --strict
   done
   ```

   Fix every finding, or justify it in `observability/dashboards/.lint` (the linter reads `.lint` from the dashboard's folder). Start that file as a copy of `.claude/skills/grafana-dashboards/sandbox/dashboards/.lint`. A dashboard that selects only by LPSM labels (no `job` or `instance`) needs its four `job` and `instance` exclusions; keep `target-promql-rule` only for TraceQL panels, listed by title, because the linter reads every target that is not Loki as PromQL. For any exclusion you add beyond them: drop it, lint again, and put it back only if the lint fails.

2. Render in the sandbox with synthetic data and read the PNGs.
3. Fix what the checklist below finds and repeat from step 1.

### Visual checklist

- [ ] No "No data" or error panels once synthetic data is loaded. Log and trace panels need the [logs and traces profile](/docs/standards/grafana-dashboards/sandbox.md#logs-and-traces-profile); only a panel whose lines cannot be made up from the template's logger may stay [`UNVERIFIED`](#log-and-trace-panels).
- [ ] Units show as units (`1.2k req/s`, `250 ms`), not raw numbers.
- [ ] Y-axes fit: no clipped peaks, no lines flattened by a wrong scale.
- [ ] Legends are short and do not swallow the panel.
- [ ] The overview row shows health at a glance.
- [ ] Colors follow thresholds the same way on every panel.
- [ ] The grid lines up at 1600 px wide with no sideways scroll.
- [ ] In the sandbox (two landscapes), changing `$landscape` changes the data.
