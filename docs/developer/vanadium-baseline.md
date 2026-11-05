# Vanadium baseline

Vanadium is the fleet's single admission-policy layer: native `ValidatingAdmissionPolicy` (VAP)
objects plus one `ValidatingAdmissionPolicyBinding` each, GA in Kubernetes 1.30+. It has no
controller, webhook, CRD or running component. It replaces argon (the Kyverno engine) and sodium
(the kyverno-policies set). There are no PSA namespace labels anywhere in the fleet, and there is no
Kyverno fallback. The Kyverno CLI is used only offline, in CI, to evaluate these definitions.

## Values

Render values in two independent dimensions, like every wrapper:

1. `chart/values.yaml` — prefix, fullname, the four-slot service tree, `enforcement`,
   `exemptionLabel`, and per-policy `enabled` / `actions` / params.
2. `chart/values.<landscape>.yaml` — the landscape (`serviceTree.landscape`, also the value the
   `landscapeMatch` CEL accepts) and its posture (`enforcement`).
3. `chart/values.<cluster>.yaml` — cluster identity only.

`values.example.yaml` is an audit landscape, `values.serving.yaml` an enforcing one, and
`values.lapras.yaml` the local cluster. A render with no landscape overlay is refused. The release
namespace must equal `serviceTree.platform` (`admission`).

## Policies

Each enabled policy renders one VAP named `vanadium-<lowercased key>` and one binding with the same
name. Every CEL expression is object-only (no `oldObject`, `authorizer` or `paramKind`), and every
resource rule lists `CREATE` and `UPDATE`. Params are rendered into the CEL as literals, so the
definitions evaluate offline with `kyverno apply`.

- **LPSM policies** match Deployments, StatefulSets, DaemonSets, Jobs, CronJobs and Services.
  A missing key is only `requireLabels` / `requireAnnotations`'s concern, so each policy fails on
  its own.
- **Pod-security policies** (PSS baseline + the restricted escalation, non-root and volume rules) match Pods (including `pods/ephemeralcontainers`), ReplicaSets and the
  same controllers. They read the pod spec from `spec`, `spec.template.spec` or
  `spec.jobTemplate.spec.template.spec`. They cover init containers and, where the PSS check
  applies to them, ephemeral containers. `requireResources` skips ephemeral containers because the
  API forbids resources on them.

## Audit to enforce

`enforcement: audit` (the default) binds every policy `[Warn, Audit]`. Nothing is blocked; Audit
writes to the API-server audit log and Warn returns a warning to the applying client (the ArgoCD
compliance feed). A landscape overlay sets `enforcement: deny` to bind every policy `[Deny]`.

A per-policy `actions` list overrides the landscape posture for that policy. In an audit landscape
an override can never include `Deny`: the render is refused. `Deny` with `Warn` is refused
everywhere (the API rejects it).

## Exemptions

Exemptions are labels, never name lists. Every binding has
`matchResources.namespaceSelector: {key: <prefix>/<exemptionLabel>, operator: NotIn, values: ["true"]}`,
so a namespace labeled `atomi.cloud/policy-exempt: "true"` is skipped by every policy.

The one non-namespace allowance is the alloy container-logs carve-out in `restrictVolumeTypes`:
hostPath is allowed only for the exact paths in `hostPathCarveOut.paths` (`/var/log`), only for the
ServiceAccount `hostPathCarveOut.serviceAccount` (`aluminium-alloy-logs`), and only in
`hostPathCarveOut.namespace` (`telemetry`). These defaults match the aluminium chart.
k8s-monitoring's `podLogsViaKubernetesApi` is the documented hostPath-free alternative. It is not
chosen because it loads the API server.

## Workload escape hatch

Exemptions are namespace-level in v1. A workload that needs its own exemption (the former sodium
name-glob excludes) runs in its own namespace, and that namespace gets the exemption label. No
workload uses it today. If one needs a per-object exemption, add an `objectSelector` on the same
label to the bindings; that change is not part of v1.

## Sodium parity

Every sodium policy maps to a vanadium policy or a documented drop. Every sodium exclude maps to a
label-based exemption.

| sodium                                            | vanadium                                                   | status                |
| ------------------------------------------------- | ---------------------------------------------------------- | --------------------- |
| require LPSM labels                               | `requireLabels`                                            | implemented           |
| require LPSM annotations                          | `requireAnnotations`                                       | implemented           |
| landscape label/annotation == cluster landscape   | `landscapeMatch`                                           | implemented           |
| layer in 0-2                                      | `layerRange`                                               | implemented           |
| platform in the accepted list                     | `platformAccepted`                                         | implemented           |
| disallow `:latest` image tags                     | `disallowLatest`                                           | implemented           |
| require requests and limits                       | `requireResources`                                         | implemented           |
| disallow NodePort services                        | `disallowNodePort`                                         | implemented           |
| non-root enforcement (PSS require-run-as-nonroot) | `requireNonRoot`                                           | implemented           |
| PSS restricted disallow-privilege-escalation      | `disallowPrivEscalation`                                   | implemented           |
| PSS restricted restrict-volume-types              | `restrictVolumeTypes`                                      | implemented           |
| exclude namespace `kube-system`                   | label `kube-system` with `atomi.cloud/policy-exempt: true` | label exemption       |
| exclude `*-cleanup-controller-*` workloads        | own namespace + exemption label (escape hatch above)       | workload escape hatch |
| exclude `*-container-logs-collector*` workloads   | alloy-logs hostPath carve-out; else escape hatch above     | workload escape hatch |
| Kyverno engine (argon) and policy reports         | native VAP; apiserver VAP metrics + Warn feed              | dropped (replaced)    |
| PSS baseline disallow-host-process                | `disallowHostProcess`                                      | implemented           |
| PSS baseline disallow-host-namespaces             | `disallowHostNamespaces`                                   | implemented           |
| PSS baseline disallow-privileged-containers       | `disallowPrivileged`                                       | implemented           |
| PSS baseline disallow-capabilities                | `disallowCapabilities`                                     | implemented           |
| PSS baseline disallow-host-ports                  | `disallowHostPorts`                                        | implemented           |
| PSS baseline disallow-host-path                   | `restrictVolumeTypes`                                      | implemented           |
| PSS baseline restrict-apparmor-profiles           | `restrictAppArmor`                                         | implemented           |
| PSS baseline disallow-selinux                     | `restrictSELinux`                                          | implemented           |
| PSS baseline disallow-proc-mount                  | `disallowProcMount`                                        | implemented           |
| PSS baseline restrict-seccomp                     | `restrictSeccomp`                                          | implemented           |
| PSS baseline restrict-sysctls                     | `restrictSysctls`                                          | implemented           |
| sodium Audit `validationFailureAction`            | `enforcement: audit` → `[Warn, Audit]`                     | implemented           |
| per-policy `validationFailureActionByPolicy`      | `policies.<key>.actions`                                   | implemented           |

The `*-cleanup-controller-*` exclude existed for Kyverno's own cleanup jobs; those workloads leave the
fleet with argon.

## Compliance view

1. apiserver per-policy VAP metrics (`apiserver_validating_admission_policy_check_total`) →
   VictoriaMetrics → Grafana.
2. Per-object detail through the Warn channel: applies flow through ArgoCD, its logs ship through
   aluminium to Gigapipe, and Grafana shows them with LogQL.

The integration tier proves the local half (warning returned, metric incremented). The cross-stack
dashboards are not this chart's to prove. trivy-operator stays dropped and is not a fallback.

## Tests

- `task test:unit` (`scripts/ci/vanadium.sh`): schema, lint, render, LPSM labels, names, parity,
  the inherited rendered-manifest stage, per-policy conformance over `tests/vap/`, audit/enforce,
  the exemption pair, and the publish dry-runs.
- `task test:int` (`scripts/ci/vanadium-k3d.sh`): k3d install, Warn + metric, Deny, exempt namespace.
- `tests/vap/good/*.yaml` must pass every policy. Each `tests/vap/bad/<policy key>/*.yaml` must fail
  exactly that policy, which keeps every policy independently regressable.

## Tokenization surface

Chart and release name, `fullnameOverride`, the service tree, `labelPrefix`, `exemptionLabel`, the
landscape/cluster overlay names, per-policy params (platforms, layers, carve-out), the k3d cluster
and registry names, the OCI path, and the package name in `scripts/ci/publish.sh`.
