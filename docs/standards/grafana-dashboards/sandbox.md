# Dashboard Sandbox

A local Grafana, image renderer and Prometheus, so you can render a dashboard with synthetic data and look at it before merge. Rules for what to check: [Grafana Dashboards](/docs/standards/grafana-dashboards/index.md#visual-checklist).

## What it checks, and what it does not

- **Metrics only.** The sandbox has Prometheus, but no log store (Loki) or trace store (Tempo). Log and trace panels show "No data" or a datasource error here; they are the [`UNVERIFIED`](/docs/standards/grafana-dashboards/index.md#log-and-trace-panels) ones.
- **No folders.** Dashboards land in Grafana's General folder. The service folder (`<platform>-<service>-folder`, see [Shipping](/docs/standards/observability/shipping.md)) is checked after deploy.
- **One sandbox at a time.** Ports 3000 (Grafana) and 9090 (Prometheus) are fixed.

## Tools

Every tool comes from this repo's nix shell. Check with `command -v jq curl file awk docker kubectl dashboard-linter promtool`: each must print a `/nix/store/…` path. `dashboard-linter` and `promtool` are declared in `nix/env.nix`; the others come from its atomiutils and infrautils bundles. You also need the Docker daemon running on the host.

## Files

Everything lives in `.claude/skills/grafana-dashboards/sandbox/`:

| File                     | What it is                                                                                         |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| `compose.yaml`           | The three containers, pinned by digest, bound to `127.0.0.1` only                                  |
| `provisioning/`          | Adds the Prometheus datasource (uid `prometheus`) and loads `dashboards/`                          |
| `generate-metrics.awk`   | Writes 6 hours of synthetic metrics for two landscapes, with an incident, from the list at its top |
| `dashboards/sample.json` | A small fixture dashboard that passes strict lint and renders with that data                       |
| `dashboards/.lint`       | Example `dashboard-linter` exclusions, each with a reason                                          |

After you copy the sandbox (below), edit the metric list at the top of `$sb/generate-metrics.awk`, not the skill's copy. Add one line per metric and label set your dashboard queries (type, name, labels, normal value, incident value), including error series and values near your thresholds, so threshold colors show.

## Run it

First pass step 1 of [Check it before merge](/docs/standards/grafana-dashboards/index.md#check-it-before-merge). Then, from the repo root:

```bash
dashboard=observability/dashboards/overview.json
sb="$(mktemp -d)"
cp -r .claude/skills/grafana-dashboards/sandbox/. "$sb"
cp "$dashboard" "$sb/dashboards/"
# now edit "$sb/generate-metrics.awk"
mkdir "$sb/prom-data"
awk -f "$sb/generate-metrics.awk" > "$sb/metrics.om"
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

- `SANDBOX_UID`/`SANDBOX_GID` make Prometheus run as you, so it can write `prom-data`.
- The unique project name keeps the containers and volumes apart from other stacks.
- Grafana is anonymous admin, which is why every port is bound to `127.0.0.1`.
- Grafana re-reads `$sb/dashboards/` about every 10 seconds: copy an edited JSON there and render again.

## Render and look

```bash
uid="$(jq -r .uid "$dashboard")"
curl -fsS -o "$sb/board.png" \
  "http://127.0.0.1:3000/render/d/$uid/x?kiosk&width=1600&height=1200&from=now-6h&to=now&tz=UTC&var-landscape=pichu"
file "$sb/board.png" | grep -q 'PNG image data' && test -s "$sb/board.png"

curl -fsS -o "$sb/panel-2.png" \
  "http://127.0.0.1:3000/render/d-solo/$uid/x?panelId=2&width=1000&height=500&from=now-6h&to=now&var-landscape=pichu"
```

- Render once per landscape (`var-landscape=pichu`, `raichu`) to prove the variable changes the data.
- Raise `height` until the bottom row is in the picture.
- Open every PNG and go through the [visual checklist](/docs/standards/grafana-dashboards/index.md#visual-checklist).

## Clean up

```bash
docker compose -p "$project" -f "$sb/compose.yaml" down -v
rm -rf "$sb"
```
