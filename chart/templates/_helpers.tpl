{{- define "zinc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "zinc.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "zinc.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "zinc.resourceName" -}}
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

{{- define "zinc.serviceTreeLabels" -}}
{{- $prefix := include "zinc.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "zinc.labels" -}}
helm.sh/chart: {{ include "zinc.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- include "zinc.serviceTreeLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "zinc.annotations" -}}
{{- include "zinc.serviceTreeLabels" . | trim }}
{{- end -}}

{{- define "zinc.secretPrefix" -}}
{{- $folder := required "secret folder is required" . | trimPrefix "/" -}}
{{- $prefix := regexReplaceAll "[^A-Za-z0-9]" $folder "_" | upper -}}
{{- if eq $prefix "" -}}
{{- fail (printf "secret folder %q yields an empty key prefix" .) -}}
{{- end -}}
{{- printf "%s_" $prefix -}}
{{- end -}}

{{- define "zinc.secretName" -}}
{{- include "zinc.resourceName" (dict "root" . "token" "secrets") -}}
{{- end -}}

{{- define "zinc.validateIssuer" -}}
{{- $issuer := required "issuer is required" .Values.issuer -}}
{{- $refs := $issuer.refs | default list -}}
{{- if eq (len $refs) 0 -}}
{{- fail "issuer.refs must name at least one ClusterIssuer" -}}
{{- end -}}
{{- $tokens := list -}}
{{- $directories := list -}}
{{- range $ref := $refs -}}
{{- $token := required "issuer.refs[].token is required" $ref.token -}}
{{- $directory := required "issuer.refs[].directory is required" $ref.directory -}}
{{- if not (hasKey $issuer.directories $directory) -}}
{{- fail (printf "issuer.refs %q selects unknown ACME directory %q" $token $directory) -}}
{{- end -}}
{{- if or (has $token $tokens) (has $directory $directories) -}}
{{- fail (printf "issuer.refs repeats token %q or directory %q (one ref per directory)" $token $directory) -}}
{{- end -}}
{{- $tokens = append $tokens $token -}}
{{- $directories = append $directories $directory -}}
{{- end -}}
{{- end -}}
