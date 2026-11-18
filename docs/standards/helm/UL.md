# helm

durian.cloud > engineering > standards > helm

How Helm charts are packaged, checked and published, one task set and one caller job per chart

| Word | Means | Also called | See |
|---|---|---|---|
| chart-checks | The registry tool that renders every values stack of a chart and checks it against the Kubernetes schemas and the policies. |  | [values stack](#values-stack), [policy chart](#policy-chart) |
| label prefix | The prefix of the four LPSM labels, from labelPrefix in the root chart values; default durian.cloud. |  | [policy chart](#policy-chart), [reload label](#reload-label) |
| policy chart | The chart of ValidatingAdmissionPolicy objects that chart-checks evaluates against each rendered object. |  | [chart-checks](#chart-checks), [label prefix](#label-prefix) |
| reload label | The pod label labelPrefix/reload; live means the app re-reads its config in place, restart means Reloader restarts the workload. Default restart. |  | [label prefix](#label-prefix) |
| values stack | One rendered set of values; values.yaml is the default stack and each values.name.yaml overlay is the stack name. |  | [chart-checks](#chart-checks) |

## chart-checks

**Meaning**

The nix registry tool, configured by the root `chart-checks.yaml`. `chart-checks render <chart>` renders every values stack of a chart into the gitignored `infra/rendered/<chart>/<stack>.yaml`. `chart-checks check-chart <chart>` renders fresh, runs `helm lint`, then checks every rendered stack against the Kubernetes schemas and the policies, and reports every failing step in one run.

**Examples**

The command in the `a-helm-check` hook of `nix/pre-commit.nix`:

```text
chart-checks check-chart infra/root_chart
```

From `chart-checks.yaml`: `kubernetes: '1.35'`.

## label prefix

**Meaning**

The prefix of the four LPSM labels, taken from `labelPrefix` in the root chart values. Every object carries `<labelPrefix>/<key>` labels. The default is `durian.cloud`; the `cluster-policies` chart gets it from `chart-checks.yaml`.

**Examples**

From `infra/root_chart/values.yaml`:

```yaml
labelPrefix: durian.cloud
```

## policy chart

**Meaning**

A chart of `ValidatingAdmissionPolicy` objects that chart-checks evaluates against each rendered object. It is listed in `chart-checks.yaml` as one git entry, and it takes the label prefix from the chart values.

**Examples**

From `chart-checks.yaml`:

```yaml
policies:
  - name: cluster-policies
    git: https://github.com/ProtoDurian/cluster-policies-standin
    commit: 560e7fc4ee8aae51cae8a00aa68aa4e4fe6af3e1
    chartValues:
      labelPrefix: .labelPrefix
    subpath: chart
```

## reload label

**Meaning**

The pod label `<labelPrefix>/reload`. `restart` means Reloader restarts the workload when any ConfigMap or Secret it uses changes; `live` means the app re-reads its whole-folder config in place. The default, `restart`, is set once in `templates/_helpers.tpl`; override it only in the chart values. Anything else fails the render.

**Examples**

From `infra/root_chart/values.yaml`:

```yaml
# reload: live
```

It is commented out, so this chart uses the default `restart`.

## values stack

**Meaning**

One rendered set of values for a chart. `values.yaml` is the `default` stack, and each `values.<name>.yaml` overlay is the stack `<name>`. chart-checks checks every stack.

**Examples**

`infra/root_chart/values.yaml`, the `default` stack of `infra/root_chart`; it renders to `infra/rendered/root_chart/default.yaml`. This chart has no overlay.
