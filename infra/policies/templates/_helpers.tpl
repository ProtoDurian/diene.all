{{/* The exemptions shared by every policy here: Helm test hooks and the named Alloy operator objects. */}}
{{- define "policies.exemptions" -}}
# Helm test hooks (helm.sh/hook: test, test-success, test-failure) are exempt: they run only on
# `helm test`, never in a deploy, and several upstream charts cannot label their test Pods.
- name: not-a-helm-test-hook
  expression: >-
    !(has(object.metadata.annotations) &&
    'helm.sh/hook' in object.metadata.annotations &&
    object.metadata.annotations['helm.sh/hook'].split(',')
    .exists(h, h.trim() in ['test', 'test-success', 'test-failure']))
- name: not-an-alloy-operator-object
  expression: >-
    !([{{ range .Values.alloyOperator }}['{{ .kind }}', '{{ .name }}'], {{ end }}]
    .exists(e, object.kind == e[0] && object.metadata.name == e[1]))
{{- end }}

{{- define "policies.workloadRules" -}}
- apiGroups: ['']
  apiVersions: ['*']
  operations: [CREATE, UPDATE]
  resources: [pods]
- apiGroups: [apps]
  apiVersions: ['*']
  operations: [CREATE, UPDATE]
  resources: [deployments, statefulsets, daemonsets, replicasets]
- apiGroups: [batch]
  apiVersions: ['*']
  operations: [CREATE, UPDATE]
  resources: [jobs, cronjobs]
{{- end }}

{{- define "policies.podMeta" -}}
- name: podMeta
  expression: >-
    object.kind == 'Pod' ? object.metadata :
    object.kind == 'CronJob' ? object.spec.jobTemplate.spec.template.metadata :
    object.spec.template.metadata
- name: podSpec
  expression: >-
    object.kind == 'Pod' ? object.spec :
    object.kind == 'CronJob' ? object.spec.jobTemplate.spec.template.spec :
    object.spec.template.spec
{{- end }}
