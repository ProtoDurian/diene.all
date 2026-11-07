# Dashboard Sandbox

A local Grafana, image renderer and Prometheus, plus Loki and Tempo if you ask for them, so you can render a dashboard with synthetic data and look at it before merge. Rules for what to check: [Grafana Dashboards](/docs/standards/grafana-dashboards/index.md#visual-checklist).

## What it checks, and what it does not

- **Metrics by default; logs and traces on request.** A plain `docker compose up` runs Prometheus only, and log and trace panels show "No data" with a red error icon. The `logs` profile adds a log store (Loki) and a trace store (Tempo) with synthetic lines and one trace ([Logs and traces profile](#logs-and-traces-profile)). The profile proves a query parses, runs on that engine version and renders. Only the real store proves the stored line shape, so a log panel built without sampled lines stays [`UNVERIFIED`](/docs/standards/grafana-dashboards/index.md#log-and-trace-panels).
- **No folders.** Dashboards land in Grafana's General folder. The service folder (`<platform>-<service>-folder`, see [Shipping](/docs/standards/observability/shipping.md)) is checked after deploy.
- **One sandbox at a time.** Ports 3000 (Grafana) and 9090 (Prometheus) are fixed; with the `logs` profile, also 3100 (Loki), 3200 (Tempo queries) and 4318 (Tempo's OTLP receiver).
- **Alert condition.** It also proves the chart's alert condition fires on a value-0 series ([Check the alert condition](#check-the-alert-condition)).

## Tools

Every tool comes from this repo's nix shell. Run `command -v jq curl file awk sed docker dashboard-linter promtool`; that is the check: each must print a `/nix/store/…` path. In `nix/env.nix`, `dashboard-linter` is in the `lint` group, `promtool` comes from `prometheus.cli` in the `dev` group (default shell), and the rest are expected from atomiutils and infrautils: tool bundles from the nix registry this repo's `flake.nix` uses (input `atomipkgs`); `command -v <tool>` shows which bundle a tool comes from. If `command -v` prints nothing or a non-`/nix/store` path, add the tool to `nix/packages.nix`. The Docker CLI comes from infrautils; the Docker daemon comes from your Docker install (`CLAUDE.md`, Prerequisites) and must be running.

## Files

Everything lives in `.claude/skills/grafana-dashboards/sandbox/`:

| File                     | What it is                                                                                                                                                                               |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `compose.yaml`           | Grafana, the renderer and Prometheus; Loki and Tempo under the `logs` profile. Pinned by digest, bound to `127.0.0.1` only                                                               |
| `provisioning/`          | Adds the datasources Prometheus (uid `prometheus`), Loki (uid `loki`; a trace id in a log line links to Tempo) and Tempo (uid `tempo`), loads `dashboards/` and the rules in `alerting/` |
| `generate-metrics.awk`   | Writes 6 hours of synthetic metrics for two landscapes, with an incident, from the list at its top                                                                                       |
| `generate-logs.awk`      | Writes the same 6 hours as pino JSON log lines, with the same incident, as a Loki push body                                                                                              |
| `trace.json`             | One OTLP trace of three spans, two with error status; its trace id is on the newest error line                                                                                           |
| `tempo.yaml`             | Tempo's config: local storage and the OTLP receiver on port 4318                                                                                                                         |
| `dashboards/sample.json` | A small fixture dashboard that passes strict lint and renders with that data; its log and trace panels need the `logs` profile                                                           |
| `dashboards/.lint`       | Example `dashboard-linter` exclusions, each with a reason                                                                                                                                |

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

The `logs` profile adds Loki (log store) and Tempo (trace store), so you can test the LogQL and TraceQL of your log and trace panels. The profile proves a query parses, runs on that engine version and renders. Only the real store proves the stored line shape: build log queries from sampled lines ([Log and trace panels](/docs/standards/grafana-dashboards/index.md#log-and-trace-panels)).

LogQL and TraceQL support differ between versions, so test on the versions the platform runs. Ask the platform team for the Loki and Tempo versions they run and pin the `loki` and `tempo` images in `compose.yaml` to them, as `<version>@sha256:<digest>` like the other lines (`docker pull grafana/loki:<version>` prints the digest). This page was measured on Loki 3.7.9 and Tempo 3.1.1.

### Start it and push data

Follow [Run it](#run-it), but start the stack with the profile and also wait for Loki and Tempo:

```bash
docker compose -p "$project" -f "$sb/compose.yaml" --profile logs up -d
for _ in $(seq 60); do
  curl -fsS http://127.0.0.1:3000/api/health >/dev/null 2>&1 &&
    curl -fsS http://127.0.0.1:3100/ready >/dev/null 2>&1 &&
    curl -fsS http://127.0.0.1:3200/ready >/dev/null 2>&1 && break
  sleep 2
done

awk -f "$sb/generate-logs.awk" > "$sb/logs.json"
curl -fsS -H 'Content-Type: application/json' --data-binary @"$sb/logs.json" http://127.0.0.1:3100/loki/api/v1/push

jq --argjson t0 "$(date +%s)000" \
  'walk(if type == "string" and startswith("@") then "\($t0 + (.[1:] | tonumber))000000" else . end)' \
  "$sb/trace.json" > "$sb/trace-now.json"
curl -fsS -H 'Content-Type: application/json' --data-binary @"$sb/trace-now.json" http://127.0.0.1:4318/v1/traces
```

- The log lines are pino-shaped: `{"level":50,"time":1794002577999,"msg":"request failed","trace_id":"…","span_id":"…","err":{…},…}`, with `level` 30 (info), 40 (warn) or 50 (error) and `time` in milliseconds. There are two streams, one per landscape (`pichu`, `raichu`), each with the labels `landscape`, `service` and `module`. If your queries select other values, pass them, e.g. `-v identity=service=zinc,module=api`.
- Loki accepts lines up to a week old by default, so the 6-hour history goes in as it is. `compose.yaml` raises Loki's `max-chunk-age` to 7h. At the default 2h, queries miss lines older than about 2.5 hours.
- The newest `pichu` line is an error with trace id `4bf92f3577b34da6a3ce929d0e0e4736`, stamped now. `trace.json` is that trace. Its span times are written as `@<milliseconds from now>`, and the `jq` line stamps them with the current time. Push the trace soon after the logs: Tempo's TraceQL search finds a trace only if its span times are close to when it arrived. A trace stamped hours back can be fetched by id, but search does not find it.

Check that Tempo has the trace. Fetching it by id works at once; search prints `[]` until about 30 seconds after the push:

```bash
trace=4bf92f3577b34da6a3ce929d0e0e4736
curl -fsS "http://127.0.0.1:3200/api/v2/traces/$trace" | jq -c '[.trace.resourceSpans[].scopeSpans[].spans[].name]'
curl -fsS -G http://127.0.0.1:3200/api/search \
  --data-urlencode 'q={ resource.service.name = "sample" && status = error }' | jq -c '[.traces[].traceID]'
```

### Test the LogQL stages

For each stage your panels use, compare row counts against the raw query:

```bash
rows() {
  curl -fsS -G http://127.0.0.1:3100/loki/api/v1/query_range --data-urlencode "query=$1" \
    --data-urlencode "start=$(($(date +%s) - 7 * 3600))000000000" --data-urlencode limit=5000 |
    jq '[.data.result[].values | length] | add // 0'
}
rows '{service="sample"}'
rows '{service="sample"} |~ "request failed|slow upstream"'
rows '{service="sample"} | json'
rows '{service="sample"} | logfmt'
rows '{service="sample"} | json | line_format "{{.level}} {{.msg}}"'
```

A stage works on that engine if it returns rows, the rows carry no `__error__` label, and parsed fields hold values. Measured on Loki 3.7.9 with the generated lines:

| Stage                                          | Rows | Result                                                                              |
| ---------------------------------------------- | ---- | ----------------------------------------------------------------------------------- |
| `{service="sample"}` (raw)                     | 1217 | Works                                                                               |
| `\|~ "request failed\|slow upstream"`          | 352  | Works                                                                               |
| `\| json`                                      | 1217 | Works. Nested keys are flattened: `err.message` becomes `err_message`               |
| `\| json \| level >= 50`                       | 241  | Works. It compares pino's numeric level as a number                                 |
| `\| logfmt`                                    | 1217 | Runs without `__error__`, but finds no fields in JSON lines. Use `\| json` for pino |
| `\| json \| line_format "{{.level}} {{.msg}}"` | 1217 | Works: `50 request failed`                                                          |

Loki also adds a `detected_level` label by itself. For pino lines it is `error` for 50 but `unknown` for 30 and 40, so select levels with `| json | level >= 50` or the line filter `` |= `"level":50` ``, not with `detected_level`.

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
- In Grafana at `http://127.0.0.1:3000`, a log line's trace id shows a "View trace" link that opens the trace in Tempo. That link comes from the Loki datasource's derived field in `provisioning/datasources/datasources.yaml`, not from dashboard JSON. In the real Grafana, the platform team sets it up.
- `dashboard-linter` reads every target that is not Loki as PromQL, so `dashboards/.lint` excludes `target-promql-rule` for the TraceQL panel by its title.

## Clean up

```bash
docker compose -p "$project" -f "$sb/compose.yaml" --profile logs down -v
rm -rf "$sb"
```

Keep `--profile logs` even if you did not use it: without it, `down` leaves Loki and Tempo running.
