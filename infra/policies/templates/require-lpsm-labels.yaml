# Workspace-level admission policy for the root chart's rendered objects.
# chart-checks renders this chart and evaluates its ValidatingAdmissionPolicy objects offline against
# infra/rendered/. The cluster-side policy set is the vanadium chart (charts/vap-policies);
# workspace must not depend on it, so this is the smallest policy that still proves the VAP
# wiring under the same labelPrefix as the root chart.
#
# Scope: workloads only (exemptions in _helpers.tpl). Every Pod and every workload (object AND its pod template)
# carries all four LPSM labels. Upstream non-workload objects (RBAC, CRDs, hooks, ...) are not asked for
# them: in a cluster this policy also admits upstream charts, and most cannot label those.
# The root chart's own objects of any kind are checked by scripts/local/helm-check.sh instead.
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-lpsm-labels
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      {{- include "policies.workloadRules" . | nindent 6 }}
  matchConditions:
    {{- include "policies.exemptions" . | nindent 4 }}
  variables:
    - name: keys
      expression: >-
        ['landscape', 'platform', 'service', 'module'].map(k, '{{ .Values.labelPrefix }}/' + k)
    {{- include "policies.podMeta" . | nindent 4 }}
  validations:
    - expression: >-
        has(object.metadata.labels) &&
        variables.keys.all(k, k in object.metadata.labels)
      message: Every workload must carry the LPSM labels {{ .Values.labelPrefix }}/landscape, platform, service and module.
    - expression: >-
        has(variables.podMeta.labels) &&
        variables.keys.all(k, k in variables.podMeta.labels)
      message: Every pod template must carry the LPSM labels {{ .Values.labelPrefix }}/landscape, platform, service and module.
