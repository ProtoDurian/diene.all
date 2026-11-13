{{- $k := printf "%s/reload" .Values.labelPrefix }}
{{- $rc := printf "%s/restart-configs" .Values.labelPrefix }}
# 1. Every pod, and every workload's pod template, carries <labelPrefix>/reload: live or restart.
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: reload-label-required
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      {{- include "policies.workloadRules" . | nindent 6 }}
  matchConditions:
    {{- include "policies.exemptions" . | nindent 4 }}
  variables:
    {{- include "policies.podMeta" . | nindent 4 }}
  validations:
    - expression: >-
        has(variables.podMeta.labels) && '{{ $k }}' in variables.podMeta.labels &&
        variables.podMeta.labels['{{ $k }}'] in ['live', 'restart']
      messageExpression: >-
        object.kind + ' ' + object.metadata.name + ': every pod must carry the label {{ $k }} with the value live or restart'
      reason: Invalid
---
# 2. A live pod must not read a ConfigMap or Secret through env, envFrom or a subPath file (they never change in a
#    running pod), unless that object is listed in the pod annotation <labelPrefix>/restart-configs ("secret/x,configmap/y"),
#    so Reloader restarts the pod when it changes. Init containers included.
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: reload-live-inputs
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      {{- include "policies.workloadRules" . | nindent 6 }}
  matchConditions:
    {{- include "policies.exemptions" . | nindent 4 }}
    - name: is-live
      expression: >-
        (object.kind == 'Pod' ? object.metadata :
        object.kind == 'CronJob' ? object.spec.jobTemplate.spec.template.metadata :
        object.spec.template.metadata).?labels.orValue({})[?'{{ $k }}'].orValue('') == 'live'
  variables:
    {{- include "policies.podMeta" . | nindent 4 }}
    - name: allowed
      expression: >-
        variables.podMeta.?annotations.orValue({})[?'{{ $rc }}'].orValue('').split(',')
    - name: containers
      expression: >-
        variables.podSpec.containers + variables.podSpec.?initContainers.orValue([])
  validations:
    - expression: >-
        variables.containers.all(c, c.?envFrom.orValue([]).all(e,
        (has(e.configMapRef) && ('configmap/' + e.configMapRef.name) in variables.allowed) ||
        (has(e.secretRef) && ('secret/' + e.secretRef.name) in variables.allowed)))
      messageExpression: >-
        object.kind + ' ' + object.metadata.name + ' is {{ $k }}=live but takes a ConfigMap or Secret by envFrom: mount it as a whole folder, or list it in restartOnlyConfigs'
      reason: Invalid
    - expression: >-
        variables.containers.all(c, c.?env.orValue([]).all(e,
        !has(e.valueFrom) || (!has(e.valueFrom.configMapKeyRef) && !has(e.valueFrom.secretKeyRef)) ||
        (has(e.valueFrom.configMapKeyRef) && ('configmap/' + e.valueFrom.configMapKeyRef.name) in variables.allowed) ||
        (has(e.valueFrom.secretKeyRef) && ('secret/' + e.valueFrom.secretKeyRef.name) in variables.allowed)))
      messageExpression: >-
        object.kind + ' ' + object.metadata.name + ' is {{ $k }}=live but reads a ConfigMap or Secret key into env: mount it as a whole folder, or list it in restartOnlyConfigs'
      reason: Invalid
    - expression: >-
        variables.containers.all(c, c.?volumeMounts.orValue([]).all(m, m.?subPath.orValue('') == '' ||
        variables.podSpec.?volumes.orValue([]).all(v, v.name != m.name ||
        (!has(v.configMap) && !has(v.secret) && !has(v.projected)) ||
        (has(v.configMap) && ('configmap/' + v.configMap.name) in variables.allowed) ||
        (has(v.secret) && ('secret/' + v.secret.secretName) in variables.allowed))))
      messageExpression: >-
        object.kind + ' ' + object.metadata.name + ' is {{ $k }}=live but mounts a ConfigMap or Secret file by subPath: mount the whole folder, or list it in restartOnlyConfigs'
      reason: Invalid
