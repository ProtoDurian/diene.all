{{- range list "require-lpsm-labels" "reload-label-required" "reload-live-inputs" }}
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: {{ . }}
spec:
  policyName: {{ . }}
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - { key: kubernetes.io/metadata.name, operator: NotIn, values: {{ toJson $.Values.exemptNamespaces }} }
{{- end }}
