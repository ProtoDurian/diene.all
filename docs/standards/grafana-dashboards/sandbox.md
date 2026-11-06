# Dashboard Sandbox

A local Grafana, image renderer and Prometheus, so you can render a dashboard with synthetic data and look at it before merge. Rules for what to check: [Grafana Dashboards](/docs/standards/grafana-dashboards/index.md#visual-checklist).

## What it checks, and what it does not

- **Metrics only.** The sandbox has Prometheus, but no log store (Loki) or trace store (Tempo). Log and trace panels show "No data" or a datasource error here. Mark them `UNVERIFIED` in their description and check them in Grafana Explore against the real landscape after deploy.
- **No folders.** Dashboards land in Grafana's General folder. The service folder (`<platform>-<service>-folder`, see [Shipping](/docs/standards/observability/shipping.md)) is checked after deploy.
- **One sandbox at a time.** Ports 3000 (Grafana) and 9090 (Prometheus) are fixed.

## Tools

From this repo's nix shell: `dashboard-linter` and `promtool` (declared in `nix/env.nix`), `jq`, `curl` and `file` (from its atomiutils bundle), and the `docker` CLI with `docker compose` (from its infrautils bundle). You also need the Docker daemon running on the host, and `bun`: Bun-based repos have it in their shell; otherwise install it.

## Files

Everything lives in `.claude/skills/grafana-dashboards/sandbox/`:

| File                     | What it is                                                                                        |
| ------------------------ | ------------------------------------------------------------------------------------------------- |
| `compose.yaml`           | The three containers, pinned by digest, bound to `127.0.0.1` only                                 |
| `provisioning/`          | Adds the Prometheus datasource (uid `prometheus`) and loads `dashboards/`                         |
| `generate-metrics.ts`    | Writes 6 hours of a counter by outcome, a histogram and a gauge, two landscapes, with an incident |
| `dashboards/sample.json` | A small dashboard that passes strict lint and renders with that data                              |
| `dashboards/.lint`       | Example `dashboard-linter` exclusions, each with a reason                                         |

After you copy the sandbox (below), edit the config block at the top of `$sb/generate-metrics.ts`, not the skill's copy: metric names, label values and outcomes, so it covers every metric and label value your dashboard queries, including error series, so threshold colors show.

## Run it

From the repo root:

```bash
dashboard=observability/dashboards/overview.json
jq empty "$dashboard"
dashboard-linter lint "$dashboard" --strict

sb="$(mktemp -d)"
cp -r .claude/skills/grafana-dashboards/sandbox/. "$sb"
cp "$dashboard" "$sb/dashboards/"
# now edit "$sb/generate-metrics.ts"
mkdir "$sb/prom-data"
bun "$sb/generate-metrics.ts" > "$sb/metrics.om"
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

- `dashboard-linter` reads `.lint` from the dashboard's own folder, so justified exclusions go in `observability/dashboards/.lint`.
- `SANDBOX_UID`/`SANDBOX_GID` make Prometheus run as you, so it can write `prom-data`.
- The unique project name keeps the containers and volumes apart from other stacks; the ports are still shared.
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
