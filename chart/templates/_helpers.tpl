{{- define "sulfur.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "sulfur.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "sulfur.serviceTreeLabels" -}}
{{- $prefix := include "sulfur.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- /* upstream.global.commonLabels are literal values; refuse any drift from labelPrefix + serviceTree. */ -}}
{{- define "sulfur.validateUpstreamLabels" -}}
{{- $want := include "sulfur.serviceTreeLabels" . | fromYaml -}}
{{- if not (deepEqual $want (.Values.upstream.global.commonLabels | default dict)) -}}
{{- fail (printf "upstream.global.commonLabels must equal %s" (toJson $want)) -}}
{{- end -}}
{{- end -}}
