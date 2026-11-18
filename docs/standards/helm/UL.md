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

## label prefix

## policy chart

## reload label

## values stack
