{{- define "aluminium.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "aluminium.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "aluminium.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "aluminium.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- $token = regexReplaceAll "[^a-z0-9]+" $token "" -}}
{{- if not (regexMatch "^[a-z0-9]+$" $service) -}}
{{- fail (printf "service %q must be dash-less lowercase alphanumeric" $service) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "token %q must normalize to a dash-less lowercase token" .token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token -}}
{{- end -}}

{{- define "aluminium.serviceTreeLabels" -}}
{{- $prefix := include "aluminium.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "aluminium.labels" -}}
helm.sh/chart: {{ include "aluminium.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- include "aluminium.serviceTreeLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "aluminium.annotations" -}}
{{- include "aluminium.serviceTreeLabels" . | trim }}
{{- end -}}

{{- /* Upstream collector labels are literal values; refuse any drift from labelPrefix + serviceTree. */ -}}
{{- define "aluminium.validateCollectorLabels" -}}
{{- $want := include "aluminium.serviceTreeLabels" . | fromYaml -}}
{{- $common := .Values.upstream.collectorCommon.alloy -}}
{{- if not (deepEqual $want (dig "labels" dict $common)) -}}
{{- fail (printf "upstream.collectorCommon.alloy.labels must equal %s" (toJson $want)) -}}
{{- end -}}
{{- if not (deepEqual $want (dig "controller" "podLabels" dict $common)) -}}
{{- fail (printf "upstream.collectorCommon.alloy.controller.podLabels must equal %s" (toJson $want)) -}}
{{- end -}}
{{- end -}}

{{- define "aluminium.secretPrefix" -}}
{{- $folder := required "secret folder is required" . | trimPrefix "/" -}}
{{- $prefix := regexReplaceAll "[^A-Za-z0-9]" $folder "_" | upper -}}
{{- if eq $prefix "" -}}
{{- fail (printf "secret folder %q yields an empty key prefix" .) -}}
{{- end -}}
{{- printf "%s_" $prefix -}}
{{- end -}}
