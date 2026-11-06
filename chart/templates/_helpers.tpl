{{- define "platinum.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "platinum.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "platinum.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "platinum.resourceName" -}}
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

{{- define "platinum.primaryName" -}}
{{- $expected := include "platinum.resourceName" (dict "root" . "token" (required "serviceTree.module is required" .Values.serviceTree.module)) -}}
{{- if ne .Values.fullnameOverride $expected -}}
{{- fail (printf "fullnameOverride must be %q, got %q" $expected .Values.fullnameOverride) -}}
{{- end -}}
{{- $expected -}}
{{- end -}}

{{- define "platinum.gatewayName" -}}
{{- include "platinum.resourceName" (dict "root" . "token" "shared") -}}
{{- end -}}

{{/* The LPSM label set every rendered object carries, as a dict. */}}
{{- define "platinum.lpsm" -}}
{{- $prefix := include "platinum.labelPrefix" . -}}
{{- $out := dict -}}
{{- range $key, $value := .Values.serviceTree }}
{{- $_ := set $out (printf "%s/%s" $prefix $key) (toString $value) -}}
{{- end }}
{{- toJson $out -}}
{{- end -}}

{{- define "platinum.labels" -}}
helm.sh/chart: {{ include "platinum.chart" . }}
app.kubernetes.io/name: {{ include "platinum.primaryName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- range $key, $value := include "platinum.lpsm" . | fromJson }}
{{ $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "platinum.annotations" -}}
{{- range $key, $value := include "platinum.lpsm" . | fromJson }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "platinum.metadata" -}}
labels:
  {{- include "platinum.labels" . | nindent 2 }}
annotations:
  {{- include "platinum.annotations" . | nindent 2 }}
{{- end -}}

{{- define "platinum.listeners" -}}
- name: http
  protocol: HTTP
  port: {{ .Values.gateway.port }}
  allowedRoutes:
    namespaces:
      from: {{ ternary "Same" "All" .Values.devHost.enabled }}
{{- if .Values.registeredCertificates.enabled }}
{{- range $slot := list "primary" "backup" }}
- name: https-{{ $slot }}
  hostname: {{ (index $.Values.registeredCertificates $slot).domain | quote }}
  protocol: HTTPS
  port: {{ $.Values.gateway.tlsPort }}
  tls:
    mode: Terminate
    certificateRefs:
      - kind: Secret
        name: {{ include "platinum.resourceName" (dict "root" $ "token" (printf "cert%s" $slot)) }}
  allowedRoutes:
    namespaces:
      from: All
{{- end }}
{{- end }}
{{- if and .Values.devHost.enabled .Values.devHost.emergencyListeners.enabled }}
{{- with .Values.devHost.emergencyListeners.listeners }}
{{ toYaml . }}
{{- end }}
{{- end }}
{{- end -}}
