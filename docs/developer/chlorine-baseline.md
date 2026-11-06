# Chlorine baseline

`chlorine` is the secret-rotation restart engine: a pure passthrough of the vendored `stakater/reloader` chart. It is the
last hop of the rotation chain (Infisical rotate → ESO sync → Reloader restart). It is a materialized helm-wrapper
instance: an ordinary unit + integration testing pyramid, no `probes/`.

## What the chart renders

- Reloader with upstream defaults: one controller Deployment, its ServiceAccount, ClusterRole/Binding and the metadata
  Role/Binding. No CRDs, webhook, Service, hook or Job.
- The chart's own templates render nothing. `_helpers.tpl` holds only the skeleton's `validateServiceTree` guard, and
  `validate.yaml` runs it. The `passthrough-minimality` named check holds this.
- The only overrides:
  - `nameOverride: reloader` and `fullnameOverride: chlorine-reloader`;
  - `reloader.autoReloadAll: false` (stated, also the upstream default) and the default reload strategy;
  - LPSM labels on the Deployment (and pod), ServiceAccount and RBAC objects;
  - the Reloader annotation on its own Deployment;
  - `reloader.readOnlyRootFileSystem: true` (upstream mounts an emptyDir at `/tmp`), container non-root, no privilege
    escalation, all capabilities dropped;
  - CPU/memory requests and limits.
- No ServiceMonitor, PodMonitor, dashboard or alert. Upstream keeps them off by default.

## Reload stance

Annotation opt-in, never auto-reload-all. Reloader restarts only workloads that carry
`reloader.stakater.com/auto: "true"`, which every family chart sets by default through helm-wrapper. Stateful or unsafe
workloads omit it. A values flip to `autoReloadAll: true` fails the unit tier.

## Values

1. `chart/values.yaml`: serviceTree (`reloader` / `chlorine` / `reloader` / layer `1`) and the upstream overrides.
2. `chart/values.<landscape>.yaml`: `serviceTree.landscape` and its LPSM label.
3. `chart/values.<cluster>.yaml`: `serviceTree.cluster` and its LPSM label.

No template reads `labelPrefix` or the landscape/cluster slots: the upstream labels are literals. Every overlay must set
`serviceTree.<slot>` AND the matching label on all three upstream label maps (`deployment`, `serviceAccount`, `rbac`).
`lpsm-labels` checks this only for committed overlays (base, each `chart/values.*.yaml`, and the full stack); an overlay
kept outside this repo is not checked.
Release namespace = `serviceTree.platform` = `reloader`.

## Version bumps

- Bump with `dep(patch|minor|major): reloader from vX to vY` (`release.yaml` allows only these `dep` scopes).
- `task latest` prints the newest chart (`ghcr.io/stakater/charts/reloader`) and image (`ghcr.io/stakater/reloader`) tags.
- `task update` refreshes `Chart.lock` and the vendored archive. `pin` checks that Chart.yaml, the lock, the archive,
  `appVersion` and the rendered image agree, and that the archive is byte-identical to a fresh pull from upstream.

## Tests

- Unit: `scripts/ci/chlorine.sh` runs every `scripts/validate/chlorine.sh` mode. Each contract has negative fixtures in the
  same mode, and they must fail for the expected reason.
  - `rendered-manifests` is the inherited stage: `helm template` → kubeconform → `kyverno apply policies/vap` on the
    controller Deployment.
- Integration: `scripts/ci/chlorine-k3d.sh` runs one plain `helm install --wait` on a fresh k3d cluster.
  - It checks the controller pod is ready and runs without auto-reload-all.
  - Two fixture Deployments read a Secret each. Rotating both Secrets must restart the annotated one (new ReplicaSet and
    pod UID within 180 s) and leave the un-annotated one untouched.
  - Then a round-trip of the chart through a local OCI registry.

## Publishing

OCI is the default mode and git is secondary (inherited `scripts/ci/publish.sh`). The package is `chlorine-<version>.tgz`.
