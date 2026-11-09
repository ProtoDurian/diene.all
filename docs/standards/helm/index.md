# Helm

Helm conventions for Kubernetes chart packaging and deployment. Charts live under
`infra/`, and there may be several — each chart directory is its own chart with its
own task set and its own caller job.

## Structure

Each chart directory under `infra/` follows the standard Helm layout:

- `Chart.yaml` — chart metadata
- `values.yaml` — default values
- `templates/` — Kubernetes manifest templates

## Local development

Local work uses Taskfile one-liners (these never call the CI scripts). The
authoritative list is `tasks/Taskfile.helm.yaml`: it holds one `deps`, `lint`,
`template`, and `debug` task per chart, namespaced by the chart directory's own
name — `infra/root_chart` is `root_chart:<verb>`. Read the task `desc` to see which
chart a task acts on, or run `task --list`.

Pass extra `helm template` arguments after `--`. Chart linting is available
directly and also runs in `task lint`. Generated chart docs are produced by
`helm-docs` from each chart's own values; no commit-time gate enforces them.

Adding a chart means adding its own task set under its own key. Never generalize
the existing tasks into one `lint` that switches on a shared chart variable.

## Render and chart checks

The chart is the only artifact: rendered YAML is never committed. `scripts/local/helm-render.sh <chart>`
renders every values stack of a chart into the gitignored `infra/rendered/<chart>/<stack>.yaml` —
`values.yaml` is the `default` stack and each `values.<name>.yaml` overlay is the stack `<name>`.
`scripts/local/helm-check.sh <chart>` renders fresh, then runs `chart-checks check` (the AtomiCloud
nix-registry tool, configured by the root `chart-checks.yaml`) on the result. It always runs two stages:

1. **Schemas** — the Kubernetes core schemas for the version in `chart-checks.yaml`
   (`kubernetes:`), unknown fields refused. A kind with no schema fails, so a chart that ships CRDs
   must list them under `crds:` in `chart-checks.yaml`.
2. **Policies** — every `policies:` entry is rendered with `helm template` and its
   `ValidatingAdmissionPolicy` objects are evaluated against each rendered object. Workspace lists one
   local entry, the chart `infra/policies`, whose `require-lpsm-labels` policy needs the four LPSM
   labels. The full cluster policy set is the vanadium chart; workspace never depends on it, so
   downstream repos add their own `policies:` entries.

### Label prefix

Labels are `<labelPrefix>/landscape`, `/platform`, `/service` and `/module`, taken from the root
chart's `serviceTree:` values. `labelPrefix` (default `durian.cloud`) is one value in
`infra/root_chart/values.yaml`, and the policy chart reads the same key in
`infra/policies/values.yaml`. Change both together: if they differ, the check fails.

### Where it runs

The `a-helm-check` pre-commit hook runs the check script, and CI runs it through the pre-commit job,
so the same render is checked on every commit. Locally use `task helm:root_chart:render` to inspect
the YAML and `task helm:root_chart:check` to run the checks. `helm lint` and `helm template` keep
running as before (`a-helm-lint`, `scripts/ci/helm.sh`).

`.chart-checks/` (the tool's install folder) is gitignored. With only `path` policies and no `crds:`
nothing is fetched, so CI needs no cache for it. The day `chart-checks.yaml` gains an `oci`, `url`
or `git` entry, add an `actions/cache` step on `.chart-checks/` keyed on
`hashFiles('chart-checks.yaml')` to the pre-commit job.

## CI/CD release structure

Publishing is driven by the `⚡reusable-helm.yaml` reusable workflow, called from `ci.yaml`
(every commit) and `cd.yaml` (release tag):

1. The reusable workflow uses `AtomiCloud/actions.setup-nix` and runs inside `nix develop .#cd`,
   so `helm`/`yq` come from the Nix store. The store is restored from the shared Nix cache —
   one cache for all Nix jobs, no per-service keys (see
   [the service-tree standard](../service-tree/index.md)).
2. It runs [`./scripts/ci/helm.sh`](../../../scripts/ci/helm.sh), which reads the chart path
   and release version from the environment the reusable workflow sets. That script owns the
   published version and destination: read its version assignment to see what a commit build
   versus a release tag publishes, and its push command for where charts land.

In CI, Helm linting and the render checks run through the pre-commit hooks (not a separate job).

### Adding more charts

Each chart is one caller job — there is **no cap**. Add a job to both `ci.yaml`
and `cd.yaml`, pointing `chart_path` at a chart that exists in that descendant:

```yaml
jobs:
  worker-chart:
    uses: ./.github/workflows/⚡reusable-helm.yaml
    secrets: inherit
    with:
      chart_path: ./infra/<chart>
      version: ${{ github.ref_name }} # cd.yaml only
```

### Configuration

The reusable workflow's inputs are declared in its own `on.workflow_call.inputs`
block in [`.github/workflows/⚡reusable-helm.yaml`](../../../.github/workflows/⚡reusable-helm.yaml).
Read that block for the current set: each entry names the input, whether it is
`required`, and its `default`.

## Out of Scope

Per-landscape values files (e.g. `values.<landscape>.yaml`) are deferred and not part of
the generated scaffold.
