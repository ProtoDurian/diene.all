# Xenon baseline

`xenon` is the Resource Metrics API (`v1beta1.metrics.k8s.io`) for HPA and `kubectl top`: a passthrough of the vendored
`kubernetes-sigs/metrics-server` chart (3.14.0, app 0.9.0). It is a materialized helm-wrapper instance and an edge
chart: an ordinary unit + integration testing pyramid, no `probes/`.

## The toggle is the surface

Xenon is ON exactly where the cluster has no built-in provider, and OFF where one is already present. It is never dropped:
an OFF stack renders nothing, so the chart installs on every landscape.

- Every overlay declares the fact `builtInMetricsProvider`. The chart refuses `upstream.enabled` unless it is the
  opposite of that fact (`duplicate provider` / `missing provider`).
- `chart/toggle-map.yaml` holds one row per defined landscape (exactly eight: primordial, lapras, ditto, rotom, absol,
  eevee, castform, serving) and the serving substrates. The chart README matrix is its human form.
- Serving is decided per registered serving cluster. `values.serving.yaml` declares the serving default (no built-in
  provider: EKS classic, EKS Auto, DOKS and on-prem do not preinstall metrics-server). A serving cluster whose substrate
  bundles a provider sets `builtInMetricsProvider: true` and `upstream.enabled: false` in its own overlay.
- There is no `onprem` landscape and no serving-row (`pichu`/`pikachu`/`raichu`/`ampharos`) landscape key.

## Values

1. `chart/values.yaml`: serviceTree (`metrics` / `xenon` / `metrics` / layer `1`), the provider fact and the upstream
   overrides.
2. `chart/values.<landscape>.yaml` (eight): `serviceTree.landscape`, its LPSM label, and the substrate deltas. The k3d/k3s
   landscapes declare the bundled provider and turn xenon OFF. The vcluster landscapes (eevee, castform) add
   `--kubelet-insecure-tls`, because the in-vcluster kubelet endpoint serves a self-signed certificate.
3. `chart/values.canary.yaml`: the cluster overlay of the `canary-xenon` fixture cluster.

The only upstream overrides (minimal delta): `fullnameOverride: xenon-metrics`, LPSM `commonLabels` + `podLabels`, the
Reloader annotation on the Deployment, pod `runAsNonRoot`, and CPU/memory limits. Upstream keeps `serviceMonitor` and
`metrics` off: xenon ships no observability objects. `commonLabels`/`podLabels` are literal values, and the chart refuses
any drift from `labelPrefix` + `serviceTree`. Release namespace = `serviceTree.platform` = `metrics`.

Reloader: `upstream.deploymentAnnotations` opts the Deployment in (`reloader.stakater.com/auto: "true"`). Set the key to
`"false"` to opt out.

Kubernetes floor: metrics-server 0.9 supports Kubernetes 1.34+. The chart refuses an ON render below 1.34; OFF renders
have no floor.

## Version bumps

- Bump with `dep(<patch|minor|major>): metrics-server from X to Y` (the releaser allows no `dep(metrics-server)` scope).
- `task update` refreshes `Chart.lock` and the vendored archive. `task latest` prints the newest chart (the
  kubernetes-sigs index) and image (`registry.k8s.io/metrics-server/metrics-server`, skopeo).
- The `pin` mode checks that Chart.yaml, Chart.lock, the archive, appVersion and the rendered image agree.

## Tests

- Unit: `scripts/ci/xenon.sh` runs every `scripts/validate/xenon.sh` mode. Each contract has negative fixtures in the same
  mode, and they must fail for the expected reason.
  - `toggle-map`: map == expected baseline == the real render of every overlay == README matrix.
  - `rendered-manifests` is the inherited stage: `helm template` → kubeconform → `kyverno apply policies/vap`.
- Integration: `scripts/ci/xenon-k3d.sh` creates `canary-xenon` (`infra/k3d.canary-xenon.yaml`: k3s 1.34 with
  `--disable=metrics-server`). It proves the metrics API is absent, runs one plain `helm install --wait`, waits (bounded)
  until `kubectl top nodes` answers, then round-trips the chart through a local OCI registry.
- The parent `start:cluster` profile is lapras (k3s bundles metrics-server, xenon OFF). Use `task test:int` for an ON
  cluster.

## Publishing

OCI is the default mode and git is secondary (inherited `scripts/ci/publish.sh`). The package is `xenon-<version>.tgz`.
`task build` runs `helm dependency build` through `scripts/local/with-chart-repos.sh`, which registers
the https repositories named in `chart/Chart.yaml` in a throwaway Helm repo config (metrics-server has no OCI chart).
