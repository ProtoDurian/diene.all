{{- define "diene-helm-wrapper.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "diene-helm-wrapper.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "diene-helm-wrapper.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "diene-helm-wrapper.instanceLabel" -}}
{{- $original := required "physical instance id is required" . -}}
{{- $normalized := regexReplaceAll "[^a-z0-9-]+" (lower $original) "-" -}}
{{- $normalized = regexReplaceAll "-+" $normalized "-" | trimAll "-" -}}
{{- if eq $normalized "" -}}
{{- fail "physical instance id normalizes to an empty label" -}}
{{- end -}}
{{- if le (len $normalized) 63 -}}
{{- $normalized -}}
{{- else -}}
{{- $hash := sha256sum $original | trunc 8 -}}
{{- $prefix := trunc 54 $normalized | trimSuffix "-" -}}
{{- printf "%s-%s" $prefix $hash -}}
{{- end -}}
{{- end -}}

{{- define "diene-helm-wrapper.resourceName" -}}
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

{{- define "diene-helm-wrapper.problemName" -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service | lower -}}
{{- $version := .Values.primordial.problem.version -}}
{{- if not (regexMatch "^v[0-9]+$" $version) -}}
{{- fail (printf "primordial.problem.version %q must be v<N>" $version) -}}
{{- end -}}
{{- printf "%s-%s-%s" $service (required "primordial.targetLandscape is required" .Values.primordial.targetLandscape) $version -}}
{{- end -}}

{{- define "diene-helm-wrapper.primaryName" -}}
{{- $expected := include "diene-helm-wrapper.resourceName" (dict "root" . "token" (required "serviceTree.module is required" .Values.serviceTree.module)) -}}
{{- if ne .Values.fullnameOverride $expected -}}
{{- fail (printf "fullnameOverride must be %q, got %q" $expected .Values.fullnameOverride) -}}
{{- end -}}
{{- $expected -}}
{{- end -}}

{{- define "diene-helm-wrapper.selectorLabels" -}}
app.kubernetes.io/name: {{ include "diene-helm-wrapper.primaryName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "diene-helm-wrapper.labels" -}}
{{- $prefix := include "diene-helm-wrapper.labelPrefix" . -}}
helm.sh/chart: {{ include "diene-helm-wrapper.chart" . }}
{{ include "diene-helm-wrapper.selectorLabels" . }}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "diene-helm-wrapper.annotations" -}}
{{- $prefix := include "diene-helm-wrapper.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- with .Values.instance.physicalId }}
{{ printf "%s/instance-original" $prefix }}: {{ . | quote }}
{{ printf "%s/instance-label" $prefix }}: {{ include "diene-helm-wrapper.instanceLabel" . | quote }}
{{- end }}
{{- end -}}

{{- define "diene-helm-wrapper.reloaderAnnotations" -}}
{{- if .enabled }}
reloader.stakater.com/auto: 'true'
{{- end }}
{{- end -}}

{{- define "diene-helm-wrapper.hostname" -}}
{{- $root := .root -}}
{{- $module := required "hostname module is required" .module | lower -}}
{{- $service := required "hostname service is required" .service | lower -}}
{{- $landscape := required "hostname landscape is required" .landscape | lower -}}
{{- $zone := required "hostname zone is required" .zone | lower | trimPrefix "." -}}
{{- $platform := $root.Release.Namespace | lower -}}
{{- range $label := list $module $service $platform $landscape }}
{{- include "diene-helm-wrapper.dnsLabel" $label -}}
{{- end -}}
{{- if hasKey . "instance" -}}
{{- $instance := .instance -}}
{{- if not (and (kindIs "string" $instance) (le (len $instance) 63) (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $instance)) -}}
{{- fail (printf "hostname instance %q must be one lowercase DNS-1123 label of at most 63 bytes" (toString $instance)) -}}
{{- end -}}
{{- printf "%s.%s.%s.%s.%s.%s" $module $service $platform $instance $landscape $zone -}}
{{- else -}}
{{- printf "%s.%s.%s.%s.%s" $module $service $platform $landscape $zone -}}
{{- end -}}
{{- end -}}

{{- define "diene-helm-wrapper.identityIssuer" -}}
{{- $landscape := required "identity landscape is required" .landscape -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $landscape) -}}
{{- fail (printf "identity landscape %q must be one lowercase DNS-1123 label" $landscape) -}}
{{- end -}}
{{- if eq $landscape .root.Release.Namespace -}}
{{- fail (printf "identity landscape %q is the consumer platform; only a concrete landscape selects an issuer" $landscape) -}}
{{- end -}}
{{- if eq $landscape (toString .root.Values.primordial.vlandscape) -}}
{{- fail (printf "identity landscape %q is a virtual landscape; only a concrete landscape selects an issuer" $landscape) -}}
{{- end -}}
{{- if not (has $landscape (default list .root.Values.primordial.identity.concreteLandscapes)) -}}
{{- fail (printf "identity landscape %q is not listed in primordial.identity.concreteLandscapes; only a concrete landscape selects an issuer" $landscape) -}}
{{- end -}}
{{- printf "api.lithium.aldehyde.%s.cluster.atomi.cloud" $landscape -}}
{{- end -}}

{{- define "diene-helm-wrapper.parseHostname" -}}
{{- $hostname := required "hostname is required" .hostname | lower -}}
{{- $zone := required "zone is required" .zone | lower | trimPrefix "." -}}
{{- $suffix := printf ".%s" $zone -}}
{{- if not (hasSuffix $suffix $hostname) -}}
{{- fail (printf "hostname %q does not end with configured zone %q" $hostname $zone) -}}
{{- end -}}
{{- $prefix := trimSuffix $suffix $hostname -}}
{{- $parts := splitList "." $prefix -}}
{{- if not (or (eq (len $parts) 4) (eq (len $parts) 5)) -}}
{{- fail (printf "hostname %q must use the canonical dotted LPSM form" $hostname) -}}
{{- end -}}
{{- range $label := $parts }}
{{- include "diene-helm-wrapper.dnsLabel" $label -}}
{{- end -}}
{{- if eq (len $parts) 4 -}}
{{- toJson (dict "landscape" (index $parts 3) "platform" (index $parts 2) "service" (index $parts 1) "module" (index $parts 0) "instance" "") -}}
{{- else if eq (len $parts) 5 -}}
{{- toJson (dict "landscape" (index $parts 4) "platform" (index $parts 2) "service" (index $parts 1) "module" (index $parts 0) "instance" (index $parts 3)) -}}
{{- end -}}
{{- end -}}

{{- define "diene-helm-wrapper.dnsLabel" -}}
{{- if not (and (le (len .) 63) (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" .)) -}}
{{- fail (printf "hostname label %q must be one lowercase DNS-1123 label of at most 63 bytes" .) -}}
{{- end -}}
{{- end -}}

{{- define "diene-helm-wrapper.secretPrefix" -}}
{{- $folder := required "secret folder is required" . | trimPrefix "/" -}}
{{- $prefix := regexReplaceAll "[^A-Za-z0-9]" $folder "_" | upper -}}
{{- if eq $prefix "" -}}
{{- fail (printf "secret folder %q yields an empty key prefix" .) -}}
{{- end -}}
{{- printf "%s_" $prefix -}}
{{- end -}}
