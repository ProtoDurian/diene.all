# Grafana Dashboards

How to write this service's dashboards as code, and how to check them by looking at them. Terms such as LPSM, generic and curated dashboard are defined in [Observability Standards](/docs/standards/observability/index.md#terms). Whether to write one at all is Gate 4 of [Signal decisions](/docs/standards/observability/signals.md).

**Never ship a dashboard you have not seen rendered.** Valid JSON can still be unreadable: wrong units, flat lines, "No data". Only a render shows that.

Dashboards are Grafana JSON files in `observability/dashboards/`, one per dashboard, `overview.json` first. Write them in the format Grafana's Dashboard → Export → JSON gives you (the classic schema, not the newer v2 schema). The primordial chart turns each file into a Grafana dashboard ([Shipping](/docs/standards/observability/shipping.md)).

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
- Open with a text panel: purpose, audience, and links to `{repo-url}/observability/overview.md` ([placeholders](/docs/standards/observability/index.md#values-the-platform-team-gives-you)) and the generic dashboard (`/d/{generic-dashboard-uid}`). The chart does not template dashboard JSON: write the real values into the JSON once you know them.
- One dashboard, one purpose. Put deep dives on a linked dashboard, not in row 12.

### Panels

- Every panel has a title, a description and an explicit unit (`reqps`, `ms`, `percentunit`). The description says what the panel shows and what bad looks like.
- Prefer trend panels. Use a stat or gauge only when one number is the whole story, e.g. days until a cert expires.
- Color by threshold: green is good, red is bad. For line colors to follow thresholds, set `fieldConfig.defaults.custom.gradientMode: scheme`. Exception: a split by category (e.g. `outcome` = `success`/`error`) gives each series a fixed color, error red.
- Draw the alert threshold on any panel an alert links to.
- Legends show only the label that differs (`{{status}}`). Hide the legend on single-series panels; give each percentile its own panel or a clear legend name.

### Queries

- Use `$__rate_interval` in `rate()` and `increase()`. Rate first, then sum: `sum by (status) (rate(x_total[$__rate_interval]))`, never `rate(sum(...))`.
- Always aggregate by the labels you want to see; never a bare `sum(rate(...))` and never an unaggregated query. (Dashboards only: an alert `expr` may sum everything.)
- Cap anything with many label values: `topk(10, ...)`.
- Show latency as percentiles (p50, p95, p99) from histograms, not averages.

### Variables and links

- `$landscape` is required on every dashboard, with `refresh: 2` (reload on time change), so one dashboard works whether a Grafana's datasource holds one landscape or several; in a one-landscape Grafana it has one value. Add the datasource variable `prometheus_datasource` labeled `Prometheus data source` and, with log panels, `loki_datasource` labeled `Loki data source`; these names pass strict lint. Set `editable: false`.
- Log panels also get a `$filter` text variable, applied as `|~ "$filter"`.
- Link panels to the next view: a log line to its trace, a service tile to `/d/<platform>-<service>-overview`. Carry the scope in the URL: `?var-landscape=${landscape}`.

## Log and trace panels

The log line in the store is not what the app wrote: the logging library's JSON wrapper changes it, and the collector turns some fields into labels ("label promotion"). So build log panels from real stored lines:

1. **Sample** 50–100 stored lines per stream (a stream is the lines that share one set of log labels) for this service, from the real landscape with Grafana Explore. Include an error window. No access? Mark the panel `UNVERIFIED` in its description and check it after the first deploy.
2. **Test the query engine.** LogQL support differs between backend versions. Compare row counts for a raw query, `|~`, `| json`, `| logfmt` and `line_format`, and use only what works. Re-test when the backend is upgraded.
3. **Split by label first**: `sum by (module) (count_over_time({service="zinc"}[1h]))`. Parse line bodies only when labels cannot answer.
4. **Note each stream's format and level encoding**, e.g. `level=error` (logfmt), `"level":"error"` (JSON), `"level":50` (pino numeric).
5. **Filter the noise** with one targeted negative filter per noisy line type, e.g. `!= "grpc.health"`.
6. **One panel per failure class**, taken from the failures named in `SIGNALS.md` (Gates 2 and 5), e.g. "Server errors (5xx)", "Auth denials (401/403)". An alert that sets `panel` links to the panel showing the data it fires on. The last panel is "all errors minus the classes above", so nothing hides. An empty class panel on a healthy service is correct; say so in its description.
7. **Place log evidence in the row of the metric it explains**, not in a generic logs row at the bottom.
8. **Rewrite lines to their key fields**: `| json | line_format "{{.level}} {{.msg}}"`. If `line_format` does not work on the engine, use `options.displayedFields`. Leave plain-text lines raw. Keep `prettifyLogMessage` off.
9. **Record what you found** (formats, level encoding, noise filters, engine limits, date) in `observability/dashboards/log-notes.md`.

Every logs panel: newest first, dedup on, a limit of about 100, time shown.

Add a slow- or error-trace table (TraceQL) only once the service emits spans. No dead panels.

## Check it before merge

Run this for every new or changed dashboard file. Tools and the sandbox: [Dashboard sandbox](/docs/standards/grafana-dashboards/sandbox.md).

1. Parse and lint, from the repo root. `dashboard-linter` is Grafana's dashboard linter; `--strict` also fails on warnings.

   ```bash
   for dashboard in observability/dashboards/*.json; do
     jq empty "$dashboard" && dashboard-linter lint "$dashboard" --strict
   done
   ```

   Fix every finding, or justify it in `observability/dashboards/.lint` (the linter reads `.lint` from the dashboard's folder). Start that file as a copy of `.claude/skills/grafana-dashboards/sandbox/dashboards/.lint` and keep only the exclusions your dashboards need: drop one, lint again, and put it back only if the lint fails.

2. Render in the sandbox with synthetic data and read the PNGs.
3. Fix what the checklist below finds and repeat from step 1.

### Visual checklist

- [ ] No "No data" or error panels once synthetic data is loaded, except [`UNVERIFIED`](#log-and-trace-panels) log and trace panels.
- [ ] Units show as units (`1.2k req/s`, `250 ms`), not raw numbers.
- [ ] Y-axes fit: no clipped peaks, no lines flattened by a wrong scale.
- [ ] Legends are short and do not swallow the panel.
- [ ] The overview row shows health at a glance.
- [ ] Colors follow thresholds the same way on every panel.
- [ ] The grid lines up at 1600 px wide with no sideways scroll.
- [ ] In the sandbox (two landscapes), changing `$landscape` changes the data.
