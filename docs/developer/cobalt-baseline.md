# Cobalt baseline

`cobalt` is the secrets gateway: the vendored External Secrets Operator (`external-secrets` 2.7.0) plus one chart-owned
`ClusterSecretStore` named `infisical`. It is a materialized helm-wrapper instance (S30): an ordinary unit + integration
testing pyramid, no `probes/`.

## What the chart renders

- ESO with upstream defaults. The only overrides: `fullnameOverride: cobalt-eso`, LPSM `commonLabels`, the Reloader pod
  annotation, pod-level `runAsNonRoot`, and CPU/memory requests and limits for the controller, webhook and cert-controller.
- The `infisical` `ClusterSecretStore` (`external-secrets.io/v1`):
  - provider Infisical, `hostAPI: https://secrets.atomi.cloud`;
  - `secretsScope`: `projectSlug: sos`, `environmentSlug` = `serviceTree.landscape`, `secretsPath: /`, `recursive: true`.
    It reads every SoS token of the cluster's landscape and nothing else.
  - `conditions`: only namespaces labelled `<labelPrefix>/sos-reader: "true"` (`store.readerLabel`) may use it. Carbon sets
    that label on its platform namespace.
  - auth: `universalAuthCredentials` that reference the SoS bootstrap Secret (`store.credentials`: name, namespace, keys).
    T3's cluster provisioning writes that Secret; cobalt never creates it and never holds a literal.
- No PushSecret, no ExternalSecret, no pre-sync hook or hook Job, no config vendoring, no docker axis. Cobalt is pull-only.

## Values

1. `chart/values.yaml` — serviceTree (`secrets` / `cobalt` / `sos` / layer `1`), the store block, ESO overrides.
2. `chart/values.<landscape>.yaml` — `serviceTree.landscape` (and its LPSM label). This sets the store's SoS environment and is
   the only per-landscape delta.
3. `chart/values.<cluster>.yaml` — `serviceTree.cluster` (and its LPSM label).

The base chart refuses to render without a landscape. `upstream.commonLabels` are literal values; the chart refuses any drift
from `labelPrefix` + `serviceTree`. Release namespace = `serviceTree.platform` = `secrets`.

Reloader: ESO's `global.podAnnotations` fallback opts all three workloads in (`reloader.stakater.com/auto: "true"`); set the
same key to `"false"` to opt out.

## CRDs and API version

- The ESO CRDs are normal Helm templates (`installCRDs: true`), so `helm upgrade` carries CRD updates. There is no CRD-apply
  step. They carry `helm.sh/resource-policy: keep` (an uninstall or prune never deletes every ExternalSecret in the cluster)
  and `argocd.argoproj.io/sync-options: ServerSideApply=true` (two CRDs exceed the client-side apply annotation limit).
- `scripts/validate/cobalt-expected-crds.txt` pins the rendered CRD set; refresh it on a dependency bump.
- Everything cobalt authors is `external-secrets.io/v1`. `crds.unsafeServeV1Beta1` stays upstream `false`.
- The store is a `post-install,post-upgrade` hook (`before-hook-creation`), so Helm builds it after the CRDs exist. One plain
  `helm install` works on a fresh cluster. ArgoCD maps it to PostSync; `SkipDryRunOnMissingResource=true` covers its dry run.

## Tests

- Unit: `scripts/ci/cobalt.sh` runs every `scripts/validate/cobalt.sh` mode. Each contract has negative fixtures in the same
  mode that must fail for the expected reason. `rendered-manifests` is the inherited stage: `helm template` → kubeconform (the
  store against its CRD's v1 schema) → `kyverno apply policies/vap` on the three ESO Deployments and the webhook Service.
- Integration: `scripts/ci/cobalt-k3d.sh` runs one plain `helm install` on a fresh k3d cluster. It checks that the ESO pods
  are healthy and the store is applied, then that `helm upgrade` re-applies it. It also checks that the API server rejects a
  malformed store and that `v1beta1` is not served. Then it round-trips the chart through a local OCI registry. Ready is not
  asserted, because it needs a live Infisical.
- `task latest` prints the newest upstream chart and image tags.

## Publishing

OCI is the default mode and git is secondary (inherited `scripts/ci/publish.sh`). The package is `cobalt-<version>.tgz`.
