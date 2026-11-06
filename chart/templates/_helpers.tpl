{{- define "xenon.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "xenon.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "xenon.validateToggle" -}}
{{- $builtIn := .Values.builtInMetricsProvider -}}
{{- $enabled := .Values.upstream.enabled -}}
{{- if not (kindIs "bool" $builtIn) -}}
{{- fail "builtInMetricsProvider must be declared true or false" -}}
{{- end -}}
{{- if and $builtIn $enabled -}}
{{- fail "duplicate provider: the cluster declares a built-in Resource Metrics API provider (builtInMetricsProvider=true), so xenon must be OFF (upstream.enabled=false)" -}}
{{- end -}}
{{- if not (or $builtIn $enabled) -}}
{{- fail "missing provider: no built-in Resource Metrics API provider is declared (builtInMetricsProvider=false), so xenon must be ON (upstream.enabled=true)" -}}
{{- end -}}
{{- if and $enabled (not (semverCompare ">=1.34.0-0" .Capabilities.KubeVersion.Version)) -}}
{{- fail (printf "metrics-server 0.9 needs Kubernetes 1.34+, the cluster is %s" .Capabilities.KubeVersion.Version) -}}
{{- end -}}
{{- end -}}

{{- define "xenon.serviceTreeLabels" -}}
{{- $prefix := include "xenon.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- /* upstream commonLabels/podLabels are literal values; refuse any drift from labelPrefix + serviceTree. */ -}}
{{- define "xenon.validateUpstreamLabels" -}}
{{- $want := include "xenon.serviceTreeLabels" . | fromYaml -}}
{{- range $key := list "commonLabels" "podLabels" -}}
{{- if not (deepEqual $want (index $.Values.upstream $key | default dict)) -}}
{{- fail (printf "upstream.%s must equal %s" $key (toJson $want)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
