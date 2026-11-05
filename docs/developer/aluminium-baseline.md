# Aluminium baseline

`aluminium` is the materialized Helm wrapper around [grafana/k8s-monitoring](https://github.com/grafana/k8s-monitoring-helm) 4.6.0 (pinned as the `upstream` dependency from `oci://ghcr.io/grafana/helm-charts`). It ships one telemetry stack — the Alloy Operator plus two Alloy collectors — and serves the fleet OTLP contract. It replaces silicon's collector fleet and the OpenTelemetry Operator. The collector runtime is `grafana/alloy` v1.21.3, the tag k8s-monitoring 4.6.0 pins.

It inherits the helm-wrapper shape (layout, stacked values, LPSM labels, ESO wiring, rendered-manifest stage, publishing) but not its probe matrix: evidence is an ordinary testing pyramid.

## Topology

- **alloy-metrics** — StatefulSet (`statefulset` + `clustered` presets). Runs `clusterMetrics` and `applicationObservability`, so it hosts the OTLP/HTTP receiver on `:4318`.
- **alloy-logs** — DaemonSet (`daemonset` preset), no clustering, `/var/log` mounted. Runs `podLogsViaOpenTelemetry`.
- alloy-logs sets `stabilityLevel: public-preview` because `podLogsViaOpenTelemetry` (`otelcol.receiver.filelog`) is the only pod-log path that keeps logs on OTLP; `podLogsViaLoki` would write with `loki.write`.
- alloy-logs needs root to read `/var/log/pods`; the scoped VAP allowance for its ServiceAccount is pending `charts/vap-policies`. Everything else (alloy-metrics uid 473, read-only root, no privilege escalation, drop ALL, limits) stays hardened.
- Both collectors are `Alloy` CRs; the operator materializes the workloads at runtime from the grafana/alloy chart it embeds (1.14.4 in alloy-operator 1.14.4). The unit tier renders that same chart, vendored at `tests/fixtures/alloy-1.14.4.tgz`, with each CR spec as values.
- Every other feature stays off: cluster events, Beyla, profiling, cost metrics, self-reporting.
- The upstream `waitForAlloyRemoval` hook Jobs are off: they expose no pod security context, so they cannot meet the workload VAP.

## Destinations

- OTLP/HTTP for every outbound signal (Q-I28). Each destination sets `type: otlp` and `protocol: http` once; signal blocks carry only `enabled`.
- `victoriametrics` — metrics. `gigapipe` — logs and traces (Grafana reads it through the standard Loki and Tempo datasources).
- The name is always `gigapipe`.
- Base values point at the emulated in-cluster stack. Prod endpoints come from Primordial through landscape overlays.

## Identity and secrets

- `labelPrefix` and `serviceTree` (`telemetry` / `aluminium` / `telemetry` / `1`) drive every LPSM label. Overlays add `landscape` and `cluster`.
- Upstream collector labels are literal values in `upstream.collectorCommon.alloy` (`labels` and `controller.podLabels`). The chart refuses to render when they differ from `labelPrefix` + `serviceTree`, so each overlay sets both.
- Backend credentials come only through the ExternalSecret (`/shared` → `SHARED_`, `/aluminium` → `ALUMINIUM_`) from the platform SecretStore. Destinations read their credentials from that target (`secret.create: false`, `secret.name: aluminium-secrets`, `*Key` fields): VictoriaMetrics with a bearer token, Gigapipe with basic auth. Values files never carry a credential and the chart never renders a `Secret`.
- The `lapras` k3d overlay turns auth and the ExternalSecret off (`auth.type: none`, `secret.embed: true`): the emulated stack is unauthenticated and k3d has no ExternalSecret CRD.

## Testing pyramid

Unit tier — `scripts/ci/aluminium.sh` runs `scripts/validate/aluminium.sh <mode>`; every contract mode also proves its negative fixture is caught:

| Mode                                       | Asserts                                                                                                                                        | Negative fixture                                                                                               |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `schema`, `lint`, `render`, `schema-drift` | lint + `values.schema.json` over base, `+example`, `+example+lapras`                                                                           | non-numeric layer, unknown store kind                                                                          |
| `topology`                                 | metrics StatefulSet clustered, logs DaemonSet unclustered                                                                                      | clustering removed / added                                                                                     |
| `otlp-contract`                            | `otlp-http` 4318 on alloy-metrics only, HTTP receiver, no gRPC                                                                                 | port 4319, assigned to alloy-logs, gRPC on                                                                     |
| `features-off`                             | only the three selected features render                                                                                                        | selfReporting, Beyla, cost, cluster events on                                                                  |
| `gigapipe-naming`                          | no legacy name in chart, scripts, tasks, workflows                                                                                             | a legacy-named endpoint                                                                                        |
| `secret`                                   | ExternalSecret shape and prefixes; destination auth via its target; no literal credential; no rendered `Secret`                                | own Secret, other Secret, literal password, URL userinfo, `Authorization`/token header                         |
| `otlp-everywhere`                          | OTLP/HTTP only, endpoints-only signal blocks, no raw Alloy config in values                                                                    | a per-signal protocol, a remote-write destination, a raw writer in the render, `extraConfig` in values         |
| `lpsm-labels`                              | both collectors and the ExternalSecret carry the LPSM set                                                                                      | prefix or service-tree drift, per-collector override                                                           |
| `rendered-manifests`                       | template + operator-created collector workloads → kubeconform (`schemas/`) → Kyverno over `policies/vap`; alloy-logs is the only denial (root) | `:latest` operator or collector image, writable root on alloy-metrics or alloy-logs, alloy-logs without limits |
| `pin`                                      | k8s-monitoring 4.x pinned in Chart.yaml, Chart.lock and the vendored archive; the alloy fixture matches the operator version                   | —                                                                                                              |

Integration tier — `scripts/ci/aluminium-k3d.sh` installs the stack on k3d, waits for both collectors, checks clustering, checks alloy-logs tails pod logs, POSTs one protobuf span and one log to `:4318`, then round-trips the chart through the cluster's local OCI registry.

Absent surfaces (pre-sync hook Job, config vendoring, docker axis, bromine/Doppler) and branch ancestry are named checks in `.github/named-checks/aluminium/`.

## Publishing

OCI is the default. `scripts/ci/publish.sh` packages `aluminium-<version>.tgz`. `task latest` lists the newest k8s-monitoring chart and `grafana/alloy` tags; bump with `task update`.
