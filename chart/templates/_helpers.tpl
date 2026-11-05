{{- define "vanadium.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vanadium.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "vanadium.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $_ := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $_ = required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $_ = required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- $_ = required "serviceTree.landscape is required; set it in the landscape overlay" .Values.serviceTree.landscape -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{- define "vanadium.resourceName" -}}
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

{{- define "vanadium.primaryName" -}}
{{- $expected := include "vanadium.resourceName" (dict "root" . "token" (required "serviceTree.module is required" .Values.serviceTree.module)) -}}
{{- if ne .Values.fullnameOverride $expected -}}
{{- fail (printf "fullnameOverride must be %q, got %q" $expected .Values.fullnameOverride) -}}
{{- end -}}
{{- $expected -}}
{{- end -}}

{{- define "vanadium.labels" -}}
{{- $prefix := include "vanadium.labelPrefix" . -}}
helm.sh/chart: {{ include "vanadium.chart" . }}
app.kubernetes.io/name: {{ include "vanadium.primaryName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "vanadium.annotations" -}}
{{- $prefix := include "vanadium.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "vanadium.actions" -}}
{{- $root := .root -}}
{{- $actions := .cfg.actions | default list -}}
{{- if not $actions -}}
{{- $actions = ternary (list "Deny") (list "Warn" "Audit") (eq $root.Values.enforcement "deny") -}}
{{- end -}}
{{- if and (has "Deny" $actions) (has "Warn" $actions) -}}
{{- fail (printf "policies.%s.actions cannot combine Deny and Warn" .name) -}}
{{- end -}}
{{- if and (has "Deny" $actions) (ne $root.Values.enforcement "deny") -}}
{{- fail (printf "policies.%s binds Deny in an audit landscape (enforcement %q)" .name $root.Values.enforcement) -}}
{{- end -}}
{{- toJson $actions -}}
{{- end -}}

{{- define "vanadium.rules" -}}
{{- if or (eq . "lpsm") (eq . "services") }}
- apiGroups: ['']
  apiVersions: [v1]
  operations: [CREATE, UPDATE]
  resources: [services]
{{- end }}
{{- if eq . "pods" }}
- apiGroups: ['']
  apiVersions: [v1]
  operations: [CREATE, UPDATE]
  resources: [pods, pods/ephemeralcontainers]
- apiGroups: [apps]
  apiVersions: [v1]
  operations: [CREATE, UPDATE]
  resources: [replicasets]
{{- end }}
{{- if ne . "services" }}
- apiGroups: [apps]
  apiVersions: [v1]
  operations: [CREATE, UPDATE]
  resources: [deployments, statefulsets, daemonsets]
- apiGroups: [batch]
  apiVersions: [v1]
  operations: [CREATE, UPDATE]
  resources: [jobs, cronjobs]
{{- end }}
{{- end -}}

{{- define "vanadium.podVariables" -}}
- name: spec
  expression: >-
    object.kind == 'Pod' ? object.spec :
    object.kind == 'CronJob' ? object.spec.jobTemplate.spec.template.spec :
    object.spec.template.spec
- name: containers
  expression: >-
    variables.spec.containers +
    (has(variables.spec.initContainers) ? variables.spec.initContainers : [])
- name: allContainers
  expression: >-
    variables.containers +
    (has(variables.spec.ephemeralContainers) ? variables.spec.ephemeralContainers : [])
{{- end -}}

{{- define "vanadium.lpsmKeys" -}}
{{- $p := include "vanadium.labelPrefix" . -}}
['{{ $p }}/landscape', '{{ $p }}/platform', '{{ $p }}/service', '{{ $p }}/module', '{{ $p }}/layer']
{{- end -}}

{{- /* metaValue <root> <key> <accepted CEL list>: label and annotation, where present, are in the list. */ -}}
{{- define "vanadium.metaValue" -}}
{{- $k := printf "%s/%s" (include "vanadium.labelPrefix" .root) .key -}}
(!has(object.metadata.labels) || !('{{ $k }}' in object.metadata.labels) || object.metadata.labels['{{ $k }}'] in {{ .list }}) &&
(!has(object.metadata.annotations) || !('{{ $k }}' in object.metadata.annotations) || object.metadata.annotations['{{ $k }}'] in {{ .list }})
{{- end -}}

{{- define "vanadium.policy.requireLabels" -}}
rules: lpsm
message: Workloads and services must carry every LPSM label (landscape, platform, service, module, layer).
expression: >-
  has(object.metadata.labels) &&
  {{ include "vanadium.lpsmKeys" . }}.all(k, k in object.metadata.labels)
{{- end -}}

{{- define "vanadium.policy.requireAnnotations" -}}
rules: lpsm
message: Workloads and services must carry every LPSM annotation (landscape, platform, service, module, layer).
expression: >-
  has(object.metadata.annotations) &&
  {{ include "vanadium.lpsmKeys" . }}.all(k, k in object.metadata.annotations)
{{- end -}}

{{- define "vanadium.policy.landscapeMatch" -}}
rules: lpsm
message: The LPSM landscape label and annotation must equal this cluster's landscape.
expression: >-
  {{- include "vanadium.metaValue" (dict "root" . "key" "landscape" "list" (list .Values.serviceTree.landscape | toJson | replace "\"" "'")) | nindent 2 }}
{{- end -}}

{{- define "vanadium.policy.layerRange" -}}
rules: lpsm
message: The LPSM layer must be one of the accepted layers.
expression: >-
  {{- include "vanadium.metaValue" (dict "root" . "key" "layer" "list" (.Values.policies.layerRange.layers | toJson | replace "\"" "'")) | nindent 2 }}
{{- end -}}

{{- define "vanadium.policy.platformAccepted" -}}
rules: lpsm
message: The LPSM platform must be in the accepted platform list.
expression: >-
  {{- include "vanadium.metaValue" (dict "root" . "key" "platform" "list" (.Values.policies.platformAccepted.platforms | toJson | replace "\"" "'")) | nindent 2 }}
{{- end -}}

{{- define "vanadium.policy.disallowLatest" -}}
rules: pods
message: Every container image must carry an explicit non-latest tag or a digest.
expression: >-
  variables.allContainers.all(c,
  (c.image.matches('^(.*/)?[^/@:]+:[^/@:]+$') ||
  c.image.matches('^[^@]+@[a-z0-9]+([+._-][a-z0-9]+)*:[a-fA-F0-9]{32,}$')) &&
  !c.image.endsWith(':latest'))
{{- end -}}

{{- define "vanadium.policy.requireResources" -}}
rules: pods
message: Every container and init container must declare CPU and memory requests and limits.
expression: >-
  variables.containers.all(c,
  has(c.resources) && has(c.resources.requests) && has(c.resources.limits) &&
  has(c.resources.requests.cpu) && has(c.resources.requests.memory) &&
  has(c.resources.limits.cpu) && has(c.resources.limits.memory))
{{- end -}}

{{- define "vanadium.policy.disallowNodePort" -}}
rules: services
message: NodePort services are forbidden; use ClusterIP or LoadBalancer.
expression: >-
  !has(object.spec.type) || object.spec.type != 'NodePort'
{{- end -}}

{{- define "vanadium.policy.requireNonRoot" -}}
rules: pods
message: Pods must run as non-root (runAsNonRoot true, no runAsUser 0) at the pod or every container level.
expression: >-
  variables.allContainers.all(c, !has(c.securityContext) ||
  ((!has(c.securityContext.runAsNonRoot) || c.securityContext.runAsNonRoot == true) &&
  (!has(c.securityContext.runAsUser) || c.securityContext.runAsUser != 0))) &&
  (!has(variables.spec.securityContext) || !has(variables.spec.securityContext.runAsUser) ||
  variables.spec.securityContext.runAsUser != 0) &&
  ((has(variables.spec.securityContext) && has(variables.spec.securityContext.runAsNonRoot) &&
  variables.spec.securityContext.runAsNonRoot == true) ||
  variables.allContainers.all(c, has(c.securityContext) &&
  has(c.securityContext.runAsNonRoot) && c.securityContext.runAsNonRoot == true))
{{- end -}}

{{- define "vanadium.policy.disallowPrivEscalation" -}}
rules: pods
message: Every container must set allowPrivilegeEscalation to false.
expression: >-
  variables.allContainers.all(c, has(c.securityContext) &&
  has(c.securityContext.allowPrivilegeEscalation) &&
  c.securityContext.allowPrivilegeEscalation == false)
{{- end -}}

{{- define "vanadium.policy.restrictVolumeTypes" -}}
{{- $carve := .Values.policies.restrictVolumeTypes.hostPathCarveOut -}}
{{- range $carve.paths }}
{{- if or (not (hasPrefix "/" .)) (contains ".." .) (contains "'" .) }}
{{- fail (printf "hostPathCarveOut path %q must be absolute with no .. or quote" .) -}}
{{- end }}
{{- end }}
rules: pods
message: Only PSS restricted volume types are allowed; hostPath only for the scoped alloy-logs carve-out.
expression: >-
  !has(variables.spec.volumes) || variables.spec.volumes.all(v,
  has(v.configMap) || has(v.csi) || has(v.downwardAPI) || has(v.emptyDir) ||
  has(v.ephemeral) || has(v.persistentVolumeClaim) || has(v.projected) || has(v.secret) ||
  {{- if and $carve.serviceAccount $carve.paths }}
  (has(v.hostPath) && has(object.metadata.namespace) &&
  object.metadata.namespace == '{{ required "hostPathCarveOut.namespace is required" $carve.namespace }}' &&
  has(variables.spec.serviceAccountName) &&
  variables.spec.serviceAccountName == '{{ $carve.serviceAccount }}' &&
  v.hostPath.path in {{ $carve.paths | toJson | replace "\"" "'" }}))
  {{- else }}
  false)
  {{- end }}
{{- end -}}

{{- define "vanadium.policy.disallowHostProcess" -}}
rules: pods
message: Windows HostProcess pods and containers are forbidden.
expression: >-
  ([variables.spec] + variables.allContainers).all(x, !has(x.securityContext) ||
  !has(x.securityContext.windowsOptions) || !has(x.securityContext.windowsOptions.hostProcess) ||
  x.securityContext.windowsOptions.hostProcess == false)
{{- end -}}

{{- define "vanadium.policy.disallowHostNamespaces" -}}
rules: pods
message: hostNetwork, hostPID and hostIPC are forbidden.
expression: >-
  (!has(variables.spec.hostNetwork) || variables.spec.hostNetwork == false) &&
  (!has(variables.spec.hostPID) || variables.spec.hostPID == false) &&
  (!has(variables.spec.hostIPC) || variables.spec.hostIPC == false)
{{- end -}}

{{- define "vanadium.policy.disallowPrivileged" -}}
rules: pods
message: Privileged containers are forbidden.
expression: >-
  variables.allContainers.all(c, !has(c.securityContext) ||
  !has(c.securityContext.privileged) || c.securityContext.privileged == false)
{{- end -}}

{{- define "vanadium.policy.disallowCapabilities" -}}
rules: pods
message: Containers may only add the PSS baseline capabilities.
expression: >-
  variables.allContainers.all(c, !has(c.securityContext) ||
  !has(c.securityContext.capabilities) || !has(c.securityContext.capabilities.add) ||
  c.securityContext.capabilities.add.all(cap, cap in ['AUDIT_WRITE', 'CHOWN', 'DAC_OVERRIDE',
  'FOWNER', 'FSETID', 'KILL', 'MKNOD', 'NET_BIND_SERVICE', 'SETFCAP', 'SETGID', 'SETPCAP',
  'SETUID', 'SYS_CHROOT']))
{{- end -}}

{{- define "vanadium.policy.disallowHostPorts" -}}
rules: pods
message: Container hostPorts are forbidden.
expression: >-
  variables.allContainers.all(c, !has(c.ports) ||
  c.ports.all(p, !has(p.hostPort) || p.hostPort == 0))
{{- end -}}

{{- define "vanadium.policy.restrictAppArmor" -}}
rules: pods
message: AppArmor profiles must be RuntimeDefault or Localhost.
expression: >-
  ([variables.spec] + variables.allContainers).all(x, !has(x.securityContext) ||
  !has(x.securityContext.appArmorProfile) ||
  x.securityContext.appArmorProfile.type in ['RuntimeDefault', 'Localhost'])
{{- end -}}

{{- define "vanadium.policy.restrictSELinux" -}}
rules: pods
message: SELinux type must be a container type, and user and role must be unset.
expression: >-
  ([variables.spec] + variables.allContainers).all(x, !has(x.securityContext) ||
  !has(x.securityContext.seLinuxOptions) ||
  ((!has(x.securityContext.seLinuxOptions.type) || x.securityContext.seLinuxOptions.type in
  ['', 'container_t', 'container_init_t', 'container_kvm_t', 'container_engine_t']) &&
  (!has(x.securityContext.seLinuxOptions.user) || x.securityContext.seLinuxOptions.user == '') &&
  (!has(x.securityContext.seLinuxOptions.role) || x.securityContext.seLinuxOptions.role == '')))
{{- end -}}

{{- define "vanadium.policy.disallowProcMount" -}}
rules: pods
message: procMount must be Default.
expression: >-
  variables.allContainers.all(c, !has(c.securityContext) ||
  !has(c.securityContext.procMount) || c.securityContext.procMount == 'Default')
{{- end -}}

{{- define "vanadium.policy.restrictSeccomp" -}}
rules: pods
message: seccomp profiles must not be Unconfined.
expression: >-
  ([variables.spec] + variables.allContainers).all(x, !has(x.securityContext) ||
  !has(x.securityContext.seccompProfile) || x.securityContext.seccompProfile.type != 'Unconfined')
{{- end -}}

{{- define "vanadium.policy.restrictSysctls" -}}
rules: pods
message: Only the PSS baseline safe sysctls are allowed.
expression: >-
  !has(variables.spec.securityContext) || !has(variables.spec.securityContext.sysctls) ||
  variables.spec.securityContext.sysctls.all(s, s.name in ['kernel.shm_rmid_forced',
  'net.ipv4.ip_local_port_range', 'net.ipv4.ip_unprivileged_port_start', 'net.ipv4.tcp_syncookies',
  'net.ipv4.ping_group_range', 'net.ipv4.ip_local_reserved_ports', 'net.ipv4.tcp_keepalive_time',
  'net.ipv4.tcp_fin_timeout', 'net.ipv4.tcp_keepalive_intvl', 'net.ipv4.tcp_keepalive_probes'])
{{- end -}}
