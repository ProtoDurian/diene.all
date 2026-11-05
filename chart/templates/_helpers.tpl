{{- define "cobalt.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cobalt.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "cobalt.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- $landscape := required "serviceTree.landscape is required: the store is scoped to the cluster's landscape" .Values.serviceTree.landscape -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "cobalt.serviceTreeLabels" -}}
{{- $prefix := include "cobalt.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "cobalt.labels" -}}
helm.sh/chart: {{ include "cobalt.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- include "cobalt.serviceTreeLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "cobalt.annotations" -}}
{{- include "cobalt.serviceTreeLabels" . | trim }}
{{- end -}}

{{- /* upstream.commonLabels are literal values; refuse any drift from labelPrefix + serviceTree. */ -}}
{{- define "cobalt.validateUpstreamLabels" -}}
{{- $want := include "cobalt.serviceTreeLabels" . | fromYaml -}}
{{- if not (deepEqual $want (.Values.upstream.commonLabels | default dict)) -}}
{{- fail (printf "upstream.commonLabels must equal %s" (toJson $want)) -}}
{{- end -}}
{{- end -}}
