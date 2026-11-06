# Sulfur baseline

`sulfur` is the certificate engine: a pure passthrough of the vendored `jetstack/cert-manager` chart (v1.20.3) with its
controller, cainjector and webhook. It is a materialized helm-wrapper instance: an ordinary unit + integration
testing pyramid, no `probes/`.

## What the chart renders

- cert-manager with upstream defaults. The chart's own templates render nothing. They only run the service-tree and
  label guards.
- The only overrides, kept minimal:
  - `nameOverride: cert-manager`, so objects are `sulfur-cert-manager*`;
  - `crds.enabled: true` and `crds.keep: true`;
  - `config.enableGatewayAPI: true`, for Gateway/HTTPRoute TLS (kgateway);
  - LPSM `global.commonLabels`;
  - the Reloader annotation on the three Deployments;
  - container `runAsNonRoot` (upstream sets it only on the pod);
  - CPU/memory requests and limits for the controller, cainjector, webhook and startupapicheck.
- No Issuer or ClusterIssuer. The engine/issuer split is an invariant: zinc owns the issuer set.
- No credentials and no cloud IAM. Cloudflare API-token auth is zinc's issuer concern. cert-manager reads a ClusterIssuer's
  Secret from its cluster resource namespace, which is the release namespace `certs`. So zinc's token Secret must land there.
- Prerequisite: the Gateway API CRDs must be in the cluster before sulfur. With `enableGatewayAPI: true`, the v1.20
  controller exits when they are absent. Sulfur does not ship them. The k3d tier applies the pinned Gateway API v1.7.0
  standard bundle (`tests/fixtures/`, the same bytes as charts/kgateway) as a test fixture.
- The dead `ExperimentalGatewayAPISupport` feature gate (a no-op since v1.15) is never set.
- ListenerSet support (`enableGatewayAPIListenerSet` + `featureGates.ListenerSets`) stays off and untested until it is needed.

## Values

1. `chart/values.yaml`: serviceTree (`certs` / `sulfur` / `certs` / layer `1`) and the upstream overrides.
2. `chart/values.<landscape>.yaml`: `serviceTree.landscape` and its LPSM label.
3. `chart/values.<cluster>.yaml`: `serviceTree.cluster` and its LPSM label.

`upstream.global.commonLabels` are literal values, and the chart refuses any drift from `labelPrefix` + `serviceTree`.
Release namespace = `serviceTree.platform` = `certs`.

Reloader: `deploymentAnnotations` opts all three Deployments in (`reloader.stakater.com/auto: "true"`). To opt out, set the
same key to `"false"` under `upstream`, `upstream.webhook` and `upstream.cainjector`.

## CRDs

- The six CRDs are normal Helm templates (`crds.enabled`), so `helm upgrade` carries CRD updates. There is no
  `skipCrds`/`crds/` path and no CRD-apply step.
- They carry `helm.sh/resource-policy: keep`, so an uninstall or prune never deletes every Certificate in the cluster.
- No ServerSideApply annotation. The largest CRD (`clusterissuers`) is about 142 KB, under the 262,144-byte client-side
  apply annotation limit. `crd-lifecycle` reddens if a bump pushes one past it without `ServerSideApply=true`.
- The CRDs come only from the pinned dependency. So the CRD upgrade path is the chart's sequential-minor path.

## Version bumps

- Bump with `dep(cert-manager): from vX to vY`.
- Q-G22: from v1.15 on, a bump may move cert-manager by at most one minor.
  - `scripts/validate/check-sequential-minor.sh` walks every first-parent commit of the push (or PR) range.
  - It reddens any step that skips a minor, downgrades, or changes major.
- A bump refreshes `Chart.lock` and the vendored archive (`task update`). The `pin` mode checks that they agree.

## Tests

- Unit: `scripts/ci/sulfur.sh` runs every `scripts/validate/sulfur.sh` mode. Each contract has negative fixtures in the same
  mode, and they must fail for the expected reason.
  - `rendered-manifests` is the inherited stage: `helm template` → kubeconform → `kyverno apply policies/vap`.
  - Its input is the three Deployments, the startupapicheck Job and the Services.
- Integration: `scripts/ci/sulfur-k3d.sh` runs one plain `helm install --wait` on a fresh k3d cluster.
  - It applies the Gateway API CRD fixture, then checks that the three pods are healthy and never restart, the CRDs are
    kept, and Gateway API is enabled in the live config.
  - A self-signed Issuer + Certificate (test fixtures, not chart templates) must reach `Ready=True`.
  - Then `helm upgrade`, then a round-trip of the chart through a local OCI registry.
- `task latest` prints the newest upstream chart and image tags (quay.io/jetstack).

## Publishing

OCI is the default mode and git is secondary (inherited `scripts/ci/publish.sh`). The package is `sulfur-<version>.tgz`.
