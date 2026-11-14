{{/*
root.reload.*: one value, live or restart, decides the pod label and the Reloader annotations.
  restart -> Reloader restarts the workload when any ConfigMap or Secret it uses changes.
  live    -> the app re-reads its whole-folder config in place; Reloader restarts the workload only for the start-only
             inputs listed in `restartOnlyConfigs` ({kind: secret|configmap, name, via: env|envFrom|subPath}).
Every helper takes a dict: root (the chart context $) and podSpec (the workload's pod .spec).
  pod template labels:      include "root.reload.label"
  pod template annotations: include "root.reload.podAnnotations"
  workload annotations:     include "root.reload.annotations"
  pod template volumes:     include "root.reload.podinfoVolume" (and "root.reload.podinfoMount" on each container)
The default, `restart`, is set once here (root.reload.mode). A values file may override it with `reload`; a value that is
not live|restart fails the render.
*/}}
{{- define "root.reload.mode" -}}
{{- $r := "restart" -}}
{{- if hasKey .root.Values "reload" -}}{{- $r = .root.Values.reload -}}{{- end -}}
{{- if not (has $r (list "live" "restart")) -}}
{{- fail (printf "values.reload must be \"live\" or \"restart\" (it becomes pod label %s/reload); got %q" .root.Values.labelPrefix (toString $r)) -}}
{{- end -}}
{{- $r -}}
{{- end }}

{{- define "root.reload.validate" -}}
{{- $mode := include "root.reload.mode" . -}}
{{- $allowed := list -}}
{{- range $o := (.root.Values.restartOnlyConfigs | default list) -}}
{{- if not (has $o.kind (list "secret" "configmap")) -}}{{- fail (printf "restartOnlyConfigs[%s].kind must be secret or configmap" $o.name) -}}{{- end -}}
{{- if not (has $o.via (list "env" "envFrom" "subPath")) -}}{{- fail (printf "restartOnlyConfigs[%s].via must be env, envFrom or subPath (a whole-folder mount is never start-only)" $o.name) -}}{{- end -}}
{{- $allowed = append $allowed (printf "%s/%s" $o.kind $o.name) -}}
{{- end -}}
{{- if eq $mode "live" -}}
{{- $spec := .podSpec -}}
{{- $volumes := ($spec.volumes | default list) -}}
{{- range $c := concat ($spec.containers | default list) ($spec.initContainers | default list) -}}
{{- range $f := ($c.envFrom | default list) -}}
{{- $key := ternary (printf "configmap/%s" (($f.configMapRef | default dict).name | default "")) (printf "secret/%s" (($f.secretRef | default dict).name | default "")) (hasKey $f "configMapRef") -}}
{{- if not (has $key $allowed) }}{{ fail (printf "reload=live: container %q takes %s through envFrom, which never updates in a running pod. Mount it as a whole folder, or list it in restartOnlyConfigs" $c.name $key) }}{{ end -}}
{{- end -}}
{{- range $e := ($c.env | default list) -}}
{{- if and (hasPrefix "ATOMI_" (upper $e.name)) }}{{ fail (printf "reload=live: container %q sets config env var %s, which never updates in a running pod" $c.name $e.name) }}{{ end -}}
{{- $ref := (($e.valueFrom | default dict).configMapKeyRef | default (($e.valueFrom | default dict).secretKeyRef | default dict)) -}}
{{- if $ref -}}
{{- $key := ternary (printf "configmap/%s" $ref.name) (printf "secret/%s" $ref.name) (hasKey ($e.valueFrom | default dict) "configMapKeyRef") -}}
{{- if not (has $key $allowed) }}{{ fail (printf "reload=live: container %q reads %s into env %q, which never updates in a running pod. Mount it as a whole folder, or list it in restartOnlyConfigs" $c.name $key $e.name) }}{{ end -}}
{{- end -}}
{{- end -}}
{{- range $m := ($c.volumeMounts | default list) -}}
{{- if $m.subPath -}}
{{- range $v := $volumes -}}
{{- if eq $v.name $m.name -}}
{{- if $v.projected }}{{ fail (printf "reload=live: container %q mounts projected volume %q with a subPath, which never updates in a running pod" $c.name $m.name) }}{{ end -}}
{{- $key := "" -}}
{{- if $v.configMap }}{{ $key = printf "configmap/%s" $v.configMap.name }}{{ else if $v.secret }}{{ $key = printf "secret/%s" $v.secret.secretName }}{{ end -}}
{{- if and $key (not (has $key $allowed)) }}{{ fail (printf "reload=live: container %q mounts %s with a subPath, which never updates in a running pod. Mount the whole folder, or list it in restartOnlyConfigs" $c.name $key) }}{{ end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* Pod template label: selectable and checked by the admission policy. */}}
{{- define "root.reload.label" -}}
{{ .root.Values.labelPrefix }}/reload: {{ include "root.reload.mode" . | quote }}
{{- end }}

{{/* Pod template annotation: the start-only inputs of a live pod, checked by the admission policy. */}}
{{- define "root.reload.podAnnotations" -}}
{{- $l := list -}}
{{- range $o := (.root.Values.restartOnlyConfigs | default list) -}}
{{- $l = append $l (printf "%s/%s" $o.kind $o.name) -}}
{{- end -}}
{{- if $l }}
{{ .root.Values.labelPrefix }}/restart-configs: {{ join "," (uniq $l) | quote }}
{{- end -}}
{{- end }}

{{/* Workload annotations read by Stakater Reloader. Never `auto` on a live pod. Validates the render rules. */}}
{{- define "root.reload.annotations" -}}
{{- include "root.reload.validate" . -}}
{{- if eq (include "root.reload.mode" .) "restart" }}
reloader.stakater.com/auto: "true"
{{- else -}}
{{- $s := list -}}{{- $c := list -}}
{{- range $o := (.root.Values.restartOnlyConfigs | default list) -}}
{{- if eq $o.kind "secret" }}{{ $s = append $s $o.name }}{{ else }}{{ $c = append $c $o.name }}{{ end -}}
{{- end -}}
{{- if $s }}
secret.reloader.stakater.com/reload: {{ join "," (uniq $s) | quote }}
{{- end -}}
{{- if $c }}
configmap.reloader.stakater.com/reload: {{ join "," (uniq $c) | quote }}
{{- end -}}
{{- end -}}
{{- end }}

{{/* The podinfo downward-API volume: the app reads its label and annotations here. */}}
{{- define "root.reload.podinfoVolume" -}}
- name: podinfo
  downwardAPI:
    items:
      - {path: labels, fieldRef: {fieldPath: metadata.labels}}
      - {path: annotations, fieldRef: {fieldPath: metadata.annotations}}
{{- end }}

{{- define "root.reload.podinfoMount" -}}
- {name: podinfo, mountPath: /etc/podinfo, readOnly: true}
{{- end }}
