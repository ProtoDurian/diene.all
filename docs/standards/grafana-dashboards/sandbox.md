# Dashboard Sandbox

A local Grafana, image renderer and Prometheus, so you can render a dashboard with synthetic data and look at it before merge. Rules for what to check: [Grafana Dashboards](/docs/standards/grafana-dashboards/index.md#visual-checklist).

## What it checks, and what it does not

- **Metrics only.** The sandbox has Prometheus, but no log store (Loki) or trace store (Tempo). Log and trace panels show "No data" or a datasource error here; they are the [`UNVERIFIED`](/docs/standards/grafana-dashboards/index.md#log-and-trace-panels) ones.
- **No folders.** Dashboards land in Grafana's General folder. The service folder (`<platform>-<service>-folder`, see [Shipping](/docs/standards/observability/shipping.md)) is checked after deploy.
- **One sandbox at a time.** Ports 3000 (Grafana) and 9090 (Prometheus) are fixed.
- **Alert condition.** It also proves the chart's alert condition fires on a value-0 series ([Check the alert condition](#check-the-alert-condition)).

## Tools

Every tool comes from this repo's nix shell. Run `command -v jq curl file awk sed docker dashboard-linter promtool`; that is the check: each must print a `/nix/store/…` path. In `nix/env.nix`, `dashboard-linter` is in the `lint` group, `promtool` comes from `prometheus.cli` in the `dev` group (default shell), and the rest are expected from atomiutils and infrautils: tool bundles from the nix registry this repo's `flake.nix` uses (input `atomipkgs`); `command -v <tool>` shows which bundle a tool comes from. If `command -v` prints nothing or a non-`/nix/store` path, add the tool to `nix/packages.nix`. The Docker CLI comes from infrautils; the Docker daemon comes from your Docker install (`CLAUDE.md`, Prerequisites) and must be running.

## Files

Everything lives in `.claude/skills/grafana-dashboards/sandbox/`:

| File                     | What it is                                                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `compose.yaml`           | The three containers, pinned by digest, bound to `127.0.0.1` only                                                   |
| `provisioning/`          | Adds the Prometheus datasource (uid `prometheus`), loads `dashboards/` and the alert-condition rules in `alerting/` |
| `generate-metrics.awk`   | Writes 6 hours of synthetic metrics for two landscapes, with an incident, from the list at its top                  |
| `dashboards/sample.json` | A small fixture dashboard that passes strict lint and renders with that data                                        |
| `dashboards/.lint`       | Example `dashboard-linter` exclusions, each with a reason                                                           |

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

## Clean up

```bash
docker compose -p "$project" -f "$sb/compose.yaml" down -v
rm -rf "$sb"
```
