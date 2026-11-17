# Dashboard Sandbox

A local Grafana, image renderer and Prometheus, plus VictoriaLogs and Tempo if you ask for them, so you can render a dashboard with synthetic data and look at it before merge. Rules for what to check: [Grafana Dashboards](/docs/standards/grafana-dashboards/index.md#visual-checklist).

## What it checks, and what it does not

- **Metrics by default; logs and traces on request.** A plain `docker compose up` runs Prometheus only, and log and trace panels show "No data" with a red error icon. The `logs` profile adds a log store (VictoriaLogs) and a trace store (Tempo) with synthetic lines and one trace ([Logs and traces profile](#logs-and-traces-profile)). The profile proves a query parses, runs on that engine version and renders. Only the real store proves the stored line shape, so a log panel built without sampled lines stays [`UNVERIFIED`](/docs/standards/grafana-dashboards/index.md#log-and-trace-panels).
- **No folders.** Dashboards land in Grafana's General folder. The service folder (`<platform>-<service>-folder`, see [Shipping](/docs/standards/observability/shipping.md)) is checked after deploy.
- **One sandbox at a time.** Ports 3000 (Grafana) and 9090 (Prometheus) are fixed; with the `logs` profile, also 9428 (VictoriaLogs), 3200 (Tempo queries) and 4318 (Tempo's OTLP receiver).
- **Alert condition.** It also proves the chart's alert condition fires on a value-0 series ([Check the alert condition](#check-the-alert-condition)).

## Tools

Every tool comes from this repo's nix shell. Run `command -v jq curl file awk sed docker dashboard-linter promtool`; that is the check: each must print a `/nix/store/…` path. In `nix/env.nix`, `dashboard-linter` is in the `lint` group, `promtool` comes from `prometheus.cli` in the `dev` group (default shell), and the rest are expected from atomiutils and infrautils: tool bundles from the nix registry this repo's `flake.nix` uses (input `atomipkgs`); `command -v <tool>` shows which bundle a tool comes from. If `command -v` prints nothing or a non-`/nix/store` path, add the tool to `nix/packages.nix`. The Docker CLI comes from infrautils; the Docker daemon comes from your Docker install (`CLAUDE.md`, Prerequisites) and must be running.

## Files

Everything lives in `.claude/skills/grafana-dashboards/sandbox/`:

| File                     | What it is                                                                                                                                                      |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `compose.yaml`           | Grafana, the renderer and Prometheus; VictoriaLogs and Tempo under the `logs` profile. Pinned by digest, bound to `127.0.0.1` only                              |
| `provisioning/`          | Adds the datasources Prometheus (uid `prometheus`), VictoriaLogs (uid `victorialogs`) and Tempo (uid `tempo`), loads `dashboards/` and the rules in `alerting/` |
| `generate-metrics.awk`   | Writes 6 hours of synthetic metrics for two landscapes, with an incident, from the list at its top                                                              |
| `generate-logs.awk`      | Writes the same 6 hours as VictoriaLogs JSON lines, with the same incident                                                                                      |
| `trace.json`             | One OTLP trace of three spans, two with error status; its trace id is on the newest error line                                                                  |
| `tempo.yaml`             | Tempo's config: local storage and the OTLP receiver on port 4318                                                                                                |
| `dashboards/sample.json` | A small fixture dashboard that passes strict lint and renders with that data; its log and trace panels need the `logs` profile                                  |
| `dashboards/.lint`       | Example `dashboard-linter` exclusions, each with a reason                                                                                                       |

For your own dashboard, write one line per metric and label set its queries use to `$sb/rows.txt`, in the format of the list at the top of `generate-metrics.awk` (type, name, labels, normal value, incident value), including error series and values near your thresholds, so threshold colors show. Pass it with `-v rows=`, and pass your platform, service and module, as your queries select them, with `-v identity=`; if your queries still say `{service}`, set `service=sandbox` (the `sed` line below puts `sandbox` there).

## Run it

First pass step 1 of [Check it before merge](/docs/standards/grafana-dashboards/index.md#check-it-before-merge). Then, from the repo root:

```bash
dashboard=observability/dashboards/overview.json # first try: .claude/skills/grafana-dashboards/sandbox/dashboards/sample.json
sb="$(mktemp -d)"
cp -r .claude/skills/grafana-dashboards/sandbox/. "$sb"
board="$sb/dashboards/$(basename "$dashboard")"
cp "$dashboard" "$board"
sed -i 's/\([^{]\){platform}/\1sandbox/g; s/\([^{]\){service}/\1sandbox/g; s/\([^{]\){module}/\1api/g' "$board"
# your rows in "$sb/rows.txt" and your identity (see above); for sample.json, drop both -v options
mkdir "$sb/prom-data"
awk -v rows="$sb/rows.txt" -v identity=platform=sandbox,service=sandbox,module=api -f "$sb/generate-metrics.awk" > "$sb/metrics.om"
promtool tsdb create-blocks-from openmetrics "$sb/metrics.om" "$sb/prom-data"

export SANDBOX_UID="$(id -u)" SANDBOX_GID="$(id -g)"
project="dash-sandbox-$(date +%s)"
docker compose -p "$project" -f "$sb/compose.yaml" up -d
for _ in $(seq 60); do
  curl -fsS http://127.0.0.1:9090/-/ready >/dev/null 2>&1 &&
    curl -fsS http://127.0.0.1:3000/api/health >/dev/null 2>&1 && break
  sleep 2
done
```

- The `sed` line fills `{platform}`, `{service}` and `{module}`, if still unknown, with `sandbox`, `sandbox` and `api` in the sandbox copy only, because Grafana uids allow only `A-Za-z0-9-_`. It leaves `{{…}}` legend names alone.
- `promtool tsdb create-blocks-from openmetrics` writes the synthetic history straight into Prometheus's storage, so no scraping is needed.
- `SANDBOX_UID`/`SANDBOX_GID` make Prometheus run as you, so it can write `prom-data`.
- The unique project name keeps the containers and volumes apart from other stacks.
- Grafana is anonymous admin, which is why every port is bound to `127.0.0.1`.
- Grafana re-reads `$sb/dashboards/` about every 10 seconds: copy an edited JSON there and render again.

## Check the alert condition

`provisioning/alerting/condition-check.yaml` loads three known-answer alert rules, evaluated every 10 seconds. `cond-A` uses its query as the condition; `cond-B` uses the condition the chart renders for every rule ([Shipping](/docs/standards/observability/shipping.md#what-the-chart-adds-to-each-alert)). Both query `vector(0) < 1`, which returns one series with value 0, as in a total outage. `absent` is an `absent_over_time` rule on a metric that does not exist. Grafana must show `cond-B` and `absent` firing and `cond-A` not; the last line prints `true`:

```bash
rules=http://127.0.0.1:3000/api/prometheus/grafana/api/v1/rules
check='[.data.groups[].rules[] | {(.name): .state}] | add | .["cond-A"] == "inactive" and .["cond-B"] == "firing" and .absent == "firing"'
for _ in $(seq 30); do curl -fsS "$rules" | jq -e "$check" >/dev/null && break; sleep 2; done
curl -fsS "$rules" | jq -e "$check"
```

## Render and look

```bash
uid="$(jq -r .uid "$board")"
curl -fsS -o "$sb/board.png" \
  "http://127.0.0.1:3000/render/d/$uid/x?kiosk&width=1600&height=1200&from=now-6h&to=now&tz=UTC&var-landscape=pichu"
file "$sb/board.png" | grep -q 'PNG image data' && test -s "$sb/board.png"

curl -fsS -o "$sb/panel-2.png" \
  "http://127.0.0.1:3000/render/d-solo/$uid/x?panelId=2&width=1000&height=500&from=now-6h&to=now&var-landscape=pichu"
```

- Render once per landscape (`var-landscape=pichu`, `raichu`) to prove the variable changes the data.
- Raise `height` until the bottom row is in the picture.
- `panelId=2` is an example: use the id of a panel an alert links to, or any panel that is not a row.
- Open every PNG and go through the [visual checklist](/docs/standards/grafana-dashboards/index.md#visual-checklist).

## Logs and traces profile

The `logs` profile adds VictoriaLogs (log store) and Tempo (trace store), so you can test the LogsQL and TraceQL of your log and trace panels. The profile proves a query parses, runs on that engine version and renders. Only the real store proves the stored line shape: build log queries from sampled lines ([Log and trace panels](/docs/standards/grafana-dashboards/index.md#log-and-trace-panels)).

LogsQL and TraceQL support differ between versions, so test on the versions the platform runs: VictoriaLogs v1.54.0 with the `victoriametrics-logs-datasource` plugin 0.34.0, and Tempo 3.1.1 ([versions](/docs/standards/observability/otel.md#versions)). `compose.yaml` pins `victorialogs` and `tempo` to those versions and installs the plugin through `GF_INSTALL_PLUGINS`. When the platform bumps a version, bump the line (`docker pull victoriametrics/victoria-logs:<version>` prints the digest to pin as `<version>@sha256:<digest>`).

### Start it and push data

Follow [Run it](#run-it), but start the stack with the profile and also wait for VictoriaLogs and Tempo:

```bash
docker compose -p "$project" -f "$sb/compose.yaml" --profile logs up -d
for _ in $(seq 60); do
  curl -fsS http://127.0.0.1:3000/api/health >/dev/null 2>&1 &&
    curl -fsS http://127.0.0.1:9428/health >/dev/null 2>&1 &&
    curl -fsS http://127.0.0.1:3200/ready >/dev/null 2>&1 && break
  sleep 2
done

awk -f "$sb/generate-logs.awk" > "$sb/logs.json"
curl -fsS -H 'Content-Type: application/stream+json' --data-binary @"$sb/logs.json" \
  'http://127.0.0.1:9428/insert/jsonline?_stream_fields=durian.cloud.landscape,durian.cloud.service,durian.cloud.module&_msg_field=_msg&_time_field=_time'

jq --argjson t0 "$(date +%s)000" \
  'walk(if type == "string" and startswith("@") then "\($t0 + (.[1:] | tonumber))000000" else . end)' \
  "$sb/trace.json" > "$sb/trace-now.json"
curl -fsS -H 'Content-Type: application/json' --data-binary @"$sb/trace-now.json" http://127.0.0.1:4318/v1/traces
```

- Each log line is one JSON object shaped like a stored OTLP log: `_time`, `_msg`, `severity_text` (`info`, `warn` or `error`), `severity_number` (30, 40 or 50), `trace_id`, `span_id`, `k8s.pod.name` and, on errors, `err.message`. The three stream fields are `durian.cloud.landscape`, `durian.cloud.service` and `durian.cloud.module`; every other field is an ordinary field. There are two streams per landscape (`pichu`, `raichu`). If your queries select other values, pass them, e.g. `-v identity=service=zinc,module=api`.
- VictoriaLogs accepts the 6-hour history as it is (its default retention is 7 days).
- The newest `pichu` line is an error with trace id `4bf92f3577b34da6a3ce929d0e0e4736`, stamped now. `trace.json` is that trace. Its span times are written as `@<milliseconds from now>`, and the `jq` line stamps them with the current time. Push the trace soon after the logs: Tempo's TraceQL search finds a trace only if its span times are close to when it arrived. A trace stamped hours back can be fetched by id, but search does not find it.

Check that Tempo has the trace. Fetching it by id works at once; search prints `[]` until about 30 seconds after the push:

```bash
trace=4bf92f3577b34da6a3ce929d0e0e4736
curl -fsS "http://127.0.0.1:3200/api/v2/traces/$trace" | jq -c '[.trace.resourceSpans[].scopeSpans[].spans[].name]'
curl -fsS -G http://127.0.0.1:3200/api/search \
  --data-urlencode 'q={ resource.service.name = "sample" && status = error }' | jq -c '[.traces[].traceID]'
```

### Test the LogsQL pipes

For each filter and pipe your panels use, compare row counts against the raw query. A dotted field name is quoted:

```bash
rows() {
  curl -fsS http://127.0.0.1:9428/select/logsql/query --data-urlencode "query=$1" \
    --data-urlencode "start=$(($(date +%s) - 7 * 3600))" --data-urlencode limit=5000 | wc -l
}
rows '_stream:{"durian.cloud.service"="sample"}'
rows '_stream:{"durian.cloud.service"="sample"} _msg:~"request failed|slow upstream"'
rows '_stream:{"durian.cloud.service"="sample"} severity_text:=error'
rows '_stream:{"durian.cloud.service"="sample"} | fields _time, _msg, trace_id'
rows '_stream:{"durian.cloud.service"="sample"} | stats by (severity_text) count()'
```

A query works on that engine if it returns rows and the fields you name hold values. Select levels with `severity_text:=error` (or `severity_number`), never with a `level` field: it does not exist in VictoriaLogs.

### Render log and trace panels

```bash
curl -fsS -o "$sb/logs.png" \
  "http://127.0.0.1:3000/render/d-solo/$uid/x?panelId=5&width=1400&height=500&from=now-6h&to=now&tz=UTC&var-landscape=pichu"
curl -fsS -o "$sb/traces.png" \
  "http://127.0.0.1:3000/render/d-solo/$uid/x?panelId=8&width=1400&height=400&from=now-6h&to=now&tz=UTC&var-landscape=pichu"
file "$sb/logs.png" "$sb/traces.png"
```

- `panelId=5` is the error-lines logs panel of `sample.json` and `panelId=8` is its error-trace table. Use your own panel ids.
- Add `&var-filter=$trace` to the logs URL to show the one line of that trace.
- The trace id is a plain field on each log line. Link it to Tempo with a panel data link, not through the datasource ([Grafana Dashboards](/docs/standards/grafana-dashboards/index.md)). In the real Grafana, the platform team sets up the datasource links.
- `dashboard-linter` reads every target that is not a Prometheus query as PromQL, so `dashboards/.lint` excludes `target-promql-rule` for the TraceQL and LogsQL panels by their titles.

## Clean up

```bash
docker compose -p "$project" -f "$sb/compose.yaml" --profile logs down -v
rm -rf "$sb"
```

Keep `--profile logs` even if you did not use it: without it, `down` leaves VictoriaLogs and Tempo running.
