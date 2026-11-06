# Grafana Dashboards

How to write this service's dashboards as code, and how to check them by looking at them. Terms such as LPSM, generic and curated dashboard are defined in [Observability Standards](docs/standards/observability/index.md#terms).

**Never ship a dashboard you have not seen rendered.** Valid JSON can still be unreadable: wrong units, flat lines, "No data". Only a render shows that.

Dashboards are classic Grafana JSON files in `observability/dashboards/`, one per dashboard, `overview.json` first. The primordial chart turns each file into a Grafana dashboard ([Shipping](docs/standards/observability/shipping.md)).

## Generic or curated

Decide this before you write a panel.

1. **Generic dashboard** (not in this repo): request rate, errors, duration and resource panels for every service, filtered by LPSM variables. This service shows up there once its metrics carry LPSM labels. Never copy its panels.
2. **Curated dashboards** (`observability/dashboards/<purpose>.json`): custom metrics only, and only when Gate 4 in `SIGNALS.md` says yes ([Signal decisions](docs/standards/observability/signals.md)). No curated dashboard is a fine outcome.
   - `overview.json` (uid `<platform>-<service>-overview`) is the one alerts link to. **Every `panel` id an alert uses must exist in it.**
   - A deep-dive gets its own file (uid `<platform>-<service>-<purpose>`), linked from the overview.

## Authoring rules

### Identity

- Pin the `uid` to `<platform>-<service>-<purpose>`, so re-applying never makes duplicates and alert links stay valid.
- Title: `<Service> — <Purpose>`, e.g. `Checkout — RED overview`.
- Experiments: title starts with `TMP-<initials>-`, use a throwaway uid, delete after use.

### Layout

- Use **RED** (rate, errors, duration) for request-driven views and **USE** (utilization, saturation, errors) for resources.
- The first row answers "is it healthy?" in under 5 seconds, with trend panels and threshold colors. Detail rows follow, in the order a responder triages.
- Open with a text panel: purpose, audience, links to `observability/overview.md` and the generic dashboard.
- One dashboard, one purpose. Put deep dives on a linked dashboard, not in row 12.

### Panels

- Every panel has a title, a description and an explicit unit (`reqps`, `ms`, `percentunit`). The description says what the panel shows and what bad looks like.
- Prefer trend panels. Use a stat or gauge only when one number is the whole story, e.g. days until a cert expires.
- Color by threshold only: green is good, red is bad. For line colors to follow thresholds, set `fieldConfig.defaults.custom.gradientMode: scheme`.
- Draw the alert threshold on any panel an alert links to.
- Legends show only the label that differs (`{{status}}`). Hide the legend on single-series panels; give each percentile its own panel or a clear legend name.

### Queries

- Use `$__rate_interval` in `rate()` and `increase()`. Rate first, then sum: `sum by (status) (rate(x_total[$__rate_interval]))`, never `rate(sum(...))`.
- Always aggregate by the labels you want to see; never a bare `sum(rate(...))` and never an unaggregated query.
- Cap anything with many label values: `topk(10, ...)`.
- Show latency as percentiles (p50, p95, p99) from histograms, not averages.

### Variables and links

- `$landscape` is required on every dashboard, with `refresh: 2` (reload on time change). Add a datasource variable labeled `Data source`. Set `editable: false`.
- Log panels also get a `$filter` text variable, applied as `|~ "$filter"`.
- Link panels to the next view: a log line to its trace, a service tile to `/d/<platform>-<service>-overview`. Carry the scope in the URL: `?var-landscape=${landscape}&var-service=...`.

## Log and trace panels

The log line in the store is not what the app wrote: wrappers, the collector and label promotion all change it. So build log panels from real stored lines:

1. **Sample** 50–100 stored lines per stream for this service, from the real landscape with Grafana Explore. Include an error window. No access? Mark the panel `UNVERIFIED` in its description and check it after the first deploy.
2. **Test the query engine.** LogQL support differs between backend versions. Compare row counts for a raw query, `|~`, `| json`, `| logfmt` and `line_format`, and use only what works. Re-test when the backend is upgraded.
3. **Split by label first**: `sum by (module) (count_over_time({service="zinc"}[1h]))`. Parse line bodies only when labels cannot answer.
4. **Note each stream's format and level encoding**, e.g. `level=error` (logfmt), `"level":"error"` (JSON), `"level":50` (pino numeric).
5. **Filter the noise** with one targeted negative filter per noisy line type, e.g. `!= "grpc.health"`.
6. **One panel per failure class**, taken from `observability/overview.md` and the alert sets, e.g. "Server errors (5xx)", "Auth denials (401/403)". Every alert has an evidence panel. The last panel is "all errors minus the classes above", so nothing hides. An empty class panel on a healthy service is correct; say so in its description.
7. **Place log evidence in the row of the metric it explains**, not in a generic logs row at the bottom.
8. **Rewrite lines to their key fields**: `| json | line_format "{{.level}} {{.msg}}"`. If `line_format` does not work on the engine, use `options.displayedFields`. Leave plain-text lines raw. Keep `prettifyLogMessage` off.
9. **Record what you found** (formats, level encoding, noise filters, engine limits, date) in a short note next to the dashboard, e.g. `observability/dashboards/log-notes.md`.

Every logs panel: newest first, dedup on, a limit of about 100, time shown.

Add a slow- or error-trace table (TraceQL) only once the service emits spans. No dead panels.

## Check it before merge

Run this for every new or changed dashboard. Commands and files: [Dashboard sandbox](docs/standards/grafana-dashboards/sandbox.md).

1. `jq empty observability/dashboards/overview.json`: the JSON parses.
2. `dashboard-linter lint observability/dashboards/overview.json --strict`: fix every finding, or justify it in `observability/dashboards/.lint`.
3. Render in the sandbox with synthetic data and read the PNGs.
4. Fix what the checklist below finds and repeat from step 1.

### Visual checklist

- [ ] No "No data" or error panels once synthetic data is loaded.
- [ ] Units show as units (`1.2k req/s`, `250 ms`), not raw numbers.
- [ ] Y-axes fit: no clipped peaks, no lines flattened by a wrong scale.
- [ ] Legends are short and do not swallow the panel.
- [ ] The first row shows health at a glance.
- [ ] Colors follow thresholds the same way on every panel.
- [ ] The grid lines up at 1600 px wide with no sideways scroll.
- [ ] Changing `$landscape` changes the data.
