#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq and Alloy programs are single-quoted on purpose
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-aluminium}"
namespace="${NAMESPACE:-telemetry}"
operator_chart="${OPERATOR_CHART:-tests/fixtures/alloy-1.14.4.tgz}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

stacks=("" "--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")
full=(--values chart/values.example.yaml --values chart/values.lapras.yaml)

render() {
  local chart="$1"
  shift
  helm template "${release}" "${chart}" --namespace "${namespace}" "$@"
}

# What the Alloy Operator installs for each Alloy CR: the alloy chart with the CR spec as values.
render_collectors() {
  local name
  for name in $(yq -N eval-all 'select(.kind == "Alloy") | .metadata.name' "$1"); do
    yq eval-all "select(.kind == \"Alloy\" and .metadata.name == \"${name}\") | .spec" "$1" >"${tmp}/spec-${name}.yaml"
    helm template "${name}" "${operator_chart}" --namespace "${namespace}" --values "${tmp}/spec-${name}.yaml"
    echo '---'
  done
}

json() { yq eval-all -o=json '.' "$1" | jq -s 'map(select(.kind != null))'; }

config_text() { json "$1" | jq -r '[.[] | select(.kind == "ConfigMap") | (.data // {})[]] | join("\n")' >"$2"; }

# need <reason> <cmd...>: a failed check names its reason so negative fixtures can match it.
need() {
  local reason="$1"
  shift
  "$@" >/dev/null 2>&1 || { echo "❌ ${reason}" >&2 && return 1; }
}

need_jq() {
  local reason="$1"
  shift
  jq -e "$@" >/dev/null || { echo "❌ ${reason}" >&2 && return 1; }
}

# expect_red <label> <pattern> <cmd...>: the check must fail, and fail for the expected reason.
expect_red() {
  local label="$1" pattern="$2"
  shift 2
  if "$@" >"${tmp}/red.txt" 2>&1; then
    echo "❌ negative fixture '${label}' was not caught" >&2 && exit 1
  fi
  rg -q -- "${pattern}" "${tmp}/red.txt" || { echo "❌ negative fixture '${label}' failed for the wrong reason" >&2 && cat "${tmp}/red.txt" >&2 && exit 1; }
}

expect_refusal() {
  local pattern="$1"
  shift
  expect_red "refusal: $*" "${pattern}" render chart "$@"
}

copy_chart() {
  mkdir -p "$1"
  cp -a chart "$1/chart"
}

merged_values() {
  local dir="$1"
  shift
  yq eval-all -o=json '. as $item ireduce ({}; . * $item)' "${dir}/values.yaml" "$@"
}

assert_topology() {
  json "$1" | need_jq 'alloy-metrics is not a clustered StatefulSet or alloy-logs is not an unclustered DaemonSet' '
    [.[] | select(.kind == "Alloy")] as $a |
    ($a | map(.metadata.name) | sort) == ["aluminium-alloy-logs", "aluminium-alloy-metrics"] and
    ($a[] | select(.metadata.name == "aluminium-alloy-metrics") |
      .spec.controller.type == "statefulset" and .spec.alloy.clustering.enabled == true) and
    ($a[] | select(.metadata.name == "aluminium-alloy-logs") |
      .spec.controller.type == "daemonset" and (.spec.alloy.clustering.enabled // false) == false and
      .spec.alloy.mounts.varlog == true)' || return 1
  render_collectors "$1" >"${tmp}/collectors.yaml"
  json "${tmp}/collectors.yaml" >"${tmp}/collectors.json"
  need 'operator workloads are not exactly one clustered StatefulSet and one unclustered DaemonSet' jq -e '
    def args($n): [.[] | select(.metadata.name == $n and (.kind == "StatefulSet" or .kind == "DaemonSet")) | .spec.template.spec.containers[] | select(.name == "alloy") | .args[]];
    (map(select(.kind == "StatefulSet" or .kind == "DaemonSet") | .kind + "/" + .metadata.name) | sort) == ["DaemonSet/aluminium-alloy-logs", "StatefulSet/aluminium-alloy-metrics"] and
    (args("aluminium-alloy-metrics") | any(. == "--cluster.enabled=true")) and
    (args("aluminium-alloy-logs") | all(. != "--cluster.enabled=true"))' "${tmp}/collectors.json"
}

assert_otlp_receiver() {
  json "$1" | need_jq 'otlp-http 4318 is not exposed by alloy-metrics alone' '
    [.[] | select(.kind == "Alloy")] as $a |
    ($a[] | select(.metadata.name == "aluminium-alloy-metrics") | [.spec.alloy.extraPorts[]? | select(.port == 4318)]) ==
      [{"appProtocol": "http", "name": "otlp-http", "port": 4318, "protocol": "TCP", "targetPort": 4318}] and
    ($a[] | select(.metadata.name == "aluminium-alloy-metrics") | [.spec.alloy.extraPorts[]? | select(.port == 4317)] | length) == 0 and
    ($a[] | select(.metadata.name == "aluminium-alloy-logs") | [.spec.alloy.extraPorts[]?] | length) == 0' || return 1
  json "$1" | jq -r '.[] | select(.kind == "ConfigMap" and .metadata.name == "aluminium-alloy-metrics") | .data[]' >"${tmp}/metrics.alloy"
  json "$1" | jq -r '.[] | select(.kind == "ConfigMap" and .metadata.name == "aluminium-alloy-logs") | .data[]' >"${tmp}/logs.alloy"
  need 'alloy-metrics does not listen for OTLP/HTTP on 0.0.0.0:4318' rg -q 'endpoint = "0\.0\.0\.0:4318"' "${tmp}/metrics.alloy" || return 1
  if rg -q 'otelcol\.receiver\.otlp|grpc \{' "${tmp}/logs.alloy" || rg -q 'grpc \{' "${tmp}/metrics.alloy"; then
    echo "❌ an OTLP receiver is on alloy-logs or gRPC is enabled" >&2 && return 1
  fi
}

assert_features_off() {
  local features
  config_text "$1" "${tmp}/features.alloy"
  features="$(rg -o '^\s*// Feature: .*' "${tmp}/features.alloy" | sed 's/^ *//' | LC_ALL=C sort -u)"
  [ "${features}" = $'// Feature: Application Observability\n// Feature: Cluster Metrics\n// Feature: Pod Logs (OpenTelemetry)' ] ||
    { echo "❌ enabled features differ: ${features//$'\n'/, }" >&2 && return 1; }
  if rg -qi '// Self Reporting|kubernetes_monitoring_telemetry' "${tmp}/features.alloy"; then
    echo "❌ self-reporting is on" >&2 && return 1
  fi
  json "$1" | need_jq 'a beyla/opencost/kepler/pyroscope resource renders' 'all(.[]; (.metadata.labels["app.kubernetes.io/name"] // "" | test("beyla|opencost|kepler|pyroscope"; "i") | not) and (.metadata.name | test("beyla|opencost|kepler"; "i") | not))'
}

assert_naming() {
  if rg -n -i --glob '!chart/charts/**' 'q[r]yn' "$1/chart" "$1/Taskfile.yaml" "$1/scripts" "$1/.github/workflows" "$1/docs/developer" "$1/README.md" "$1/CLAUDE.md" "$1/infra" "$1/tasks" >&2; then
    echo "❌ a legacy destination name is referenced" >&2 && return 1
  fi
  yq -o=json '.upstream.destinations' "$1/chart/values.yaml" |
    need_jq 'gigapipe is not the OTLP logs+traces destination' '.gigapipe.type == "otlp" and .gigapipe.logs.enabled == true and .gigapipe.traces.enabled == true'
}

assert_no_literal_secrets() {
  yq eval-all -o=json '.' "$1"/values*.yaml | need_jq 'a literal credential is in a values file' -s '
    def credential_key: test("^(password|passphrase|token|bearertoken|apikey|api[_-]key|clientsecret|client[_-]secret|secretkey|accesskey|privatekey|credentials?|authorization)$"; "i")
      or (test("token"; "i") and (test("(Key|From|File)$") | not));
    [.[] | .. | objects | to_entries[] | select((.key | credential_key) and .value != null and .value != "")] +
    [.[] | .. | strings | select(test("://[^/@\\s]+:[^/@\\s]+@"))] | length == 0'
}

assert_no_rendered_secret() { json "$1" | need_jq 'the chart renders a Secret' 'map(select(.kind == "Secret")) | length == 0'; }

assert_auth_via_eso() {
  local dir="$1" stack values=()
  for stack in "" "values.example.yaml" "values.example.yaml values.lapras.yaml"; do
    values=()
    for f in ${stack}; do values+=("${dir}/${f}"); done
    merged_values "${dir}" "${values[@]}" | need_jq "a destination authenticates without the ExternalSecret target (stack '${stack:-values.yaml}')" '
      .secret.enabled as $eso | (.serviceTree.service + "-secrets") as $target |
      all(.upstream.destinations[]; (.auth.type // "none") as $t |
        if $t == "none" or $t == "" then .secret.embed == true or $eso
        else $eso and .secret.create == false and .secret.name == $target end)' || return 1
  done
  merged_values "${dir}" | need_jq 'base destinations are not all authenticated through the ExternalSecret' '
    all(.upstream.destinations[]; .auth.type == "basic" or .auth.type == "bearerToken")'
}

assert_values_otlp() {
  yq eval-all -o=json '.' "$1"/values*.yaml | need_jq 'a destination is not OTLP/HTTP or a signal block carries more than enabled' -s '
    map(.upstream.destinations // {}) | reduce .[] as $d ({}; . * $d) |
    length > 0 and all(.[];
      .type == "otlp" and .protocol == "http" and
      all(.metrics, .logs, .traces; (. // {}) | keys - ["enabled"] == []))'
}

assert_no_raw_river() {
  yq eval-all -o=json '.' "$1"/values*.yaml | need_jq 'raw Alloy config is set in a values file' -s '
    [.[] | paths(type != "null") | select((.[-1] == "extraConfig") or (.[-1] == "replaceComponent") or (.[-2:] == ["configMap", "content"]))] | length == 0'
}

assert_rendered_otlp() {
  config_text "$1" "${tmp}/otlp.alloy"
  need 'no OTLP/HTTP exporter renders' rg -q '^otelcol\.exporter\.otlphttp "' "${tmp}/otlp.alloy" || return 1
  if rg -q '^\s*(otelcol\.exporter\.otlp |prometheus\.remote_write |loki\.write |pyroscope\.write )' "${tmp}/otlp.alloy"; then
    echo "❌ a non-OTLP/HTTP writer renders" >&2 && return 1
  fi
}

assert_lpsm() {
  local prefix="$1" file="$2" landscape="$3" cluster="$4"
  json "${file}" | need_jq 'collector or ExternalSecret labels differ from the LPSM set' --arg p "${prefix}" --arg l "${landscape}" --arg c "${cluster}" '
    ({($p + "/platform"): "telemetry", ($p + "/service"): "aluminium", ($p + "/module"): "telemetry", ($p + "/layer"): "1"}
      + (if $l == "" then {} else {($p + "/landscape"): $l} end)
      + (if $c == "" then {} else {($p + "/cluster"): $c} end)) as $want |
    [.[] | select(.kind == "Alloy")] as $a |
    ($a | length) == 2 and
    all($a[]; .metadata.labels == $want and .spec.controller.podLabels == $want) and
    all(.[] | select(.kind == "ExternalSecret"); .metadata.labels as $l | all($want | to_entries[]; $l[.key] == .value))'
}

# vap_stage <render> <label>: the inherited stage over the chart render plus the operator-created collectors.
# alloy-logs is the one known denial (root for /var/log/pods); anything else, or any other deviation, is red.
vap_stage() {
  local root_rule='Workloads must run non-root with baseline-plus container hardening\.'
  render_collectors "$1" >"$1.collectors.yaml"
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "$1" "$1.collectors.yaml"
  yq eval-all 'select((.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service") and .metadata.name != "aluminium-alloy-logs")' "$1" "$1.collectors.yaml" >"$1.vap.yaml"
  yq eval-all 'select(.kind == "DaemonSet" and .metadata.name == "aluminium-alloy-logs")' "$1.collectors.yaml" >"$1.logs.yaml"
  need "alloy-metrics is missing from the VAP input ($2)" yq -e 'select(.kind == "StatefulSet" and .metadata.name == "aluminium-alloy-metrics") | .kind' "$1.vap.yaml" || return 1
  need "alloy-logs is missing from the VAP input ($2)" yq -e '.kind == "DaemonSet"' "$1.logs.yaml" || return 1
  kyverno apply policies/vap --resource "$1.vap.yaml" --detailed-results --remove-color || { echo "❌ a workload other than alloy-logs fails the VAP ($2)" >&2 && return 1; }
  kyverno apply policies/vap --resource "$1.logs.yaml" --remove-color >"$1.logs.txt" 2>&1 || true
  need "alloy-logs is not denied exactly once, by the non-root rule ($2)" rg -q "^pass: 0, fail: 1, warn: 0, error: 0, skip: 0" "$1.logs.txt" || return 1
  if [ "$(rg -c '^1 - ' "$1.logs.txt")" != 1 ] || ! rg -q "^1 - diene-wrapper-workload-baseline ${root_rule}$" "$1.logs.txt"; then
    echo "❌ alloy-logs is denied for something other than root ($2)" >&2 && cat "$1.logs.txt" >&2 && return 1
  fi
  yq '.spec.template.spec.securityContext.runAsNonRoot = true | del(.spec.template.spec.securityContext.runAsUser) |
    .spec.template.spec.containers[].securityContext.runAsNonRoot = true | del(.spec.template.spec.containers[].securityContext.runAsUser)' "$1.logs.yaml" >"$1.logs-nonroot.yaml"
  kyverno apply policies/vap --resource "$1.logs-nonroot.yaml" --remove-color >"$1.logs-nonroot.txt" 2>&1 ||
    { echo "❌ alloy-logs deviates from the VAP beyond running as root ($2)" >&2 && cat "$1.logs-nonroot.txt" >&2 && return 1; }
}

case "${mode}" in
schema)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack} >"${tmp}/schema.txt" 2>&1 ||
      { echo "❌ schema rejected the stack '${stack:-values.yaml}'" >&2 && cat "${tmp}/schema.txt" >&2 && exit 1; }
  done
  expect_red 'layer is not numeric' "serviceTree/layer.*does not match pattern|at '/serviceTree/layer'" helm lint chart --namespace "${namespace}" --set-string serviceTree.layer=one
  expect_red 'unknown secret store kind' "secret/store/kind.*value must be one of|at '/secret/store/kind'" helm lint chart --namespace "${namespace}" --set secret.store.kind=Vault
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml
  ;;
render)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >/dev/null
  done
  ;;
topology)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/topology.yaml"
    assert_topology "${tmp}/topology.yaml"
  done
  render chart "${full[@]}" --set 'upstream.collectors.alloy-metrics.presets={statefulset}' >"${tmp}/unclustered.yaml"
  expect_red 'alloy-metrics without clustering' 'not a clustered StatefulSet' assert_topology "${tmp}/unclustered.yaml"
  render chart "${full[@]}" --set 'upstream.collectors.alloy-logs.presets={daemonset,clustered}' >"${tmp}/clustered-logs.yaml"
  expect_red 'alloy-logs with clustering' 'not an unclustered DaemonSet' assert_topology "${tmp}/clustered-logs.yaml"
  ;;
otlp-contract)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/otlp.yaml"
    assert_otlp_receiver "${tmp}/otlp.yaml"
  done
  render chart "${full[@]}" --set upstream.applicationObservability.receivers.otlp.http.port=4319 >"${tmp}/port.yaml"
  expect_red 'receiver moved off 4318' 'otlp-http 4318 is not exposed' assert_otlp_receiver "${tmp}/port.yaml"
  render chart "${full[@]}" --set upstream.applicationObservability.collector=alloy-logs >"${tmp}/assignment.yaml"
  expect_red 'receiver assigned to alloy-logs' 'otlp-http 4318 is not exposed' assert_otlp_receiver "${tmp}/assignment.yaml"
  render chart "${full[@]}" --set upstream.applicationObservability.receivers.otlp.grpc.enabled=true >"${tmp}/grpc.yaml"
  expect_red 'grpc receiver enabled' 'otlp-http 4318 is not exposed|gRPC is enabled' assert_otlp_receiver "${tmp}/grpc.yaml"
  ;;
features-off)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/features.yaml"
    assert_features_off "${tmp}/features.yaml"
  done
  render chart "${full[@]}" --set upstream.selfReporting.enabled=true >"${tmp}/self.yaml"
  expect_red 'selfReporting on' 'self-reporting is on' assert_features_off "${tmp}/self.yaml"
  render chart "${full[@]}" --set upstream.telemetryServices.beyla.deploy=true >"${tmp}/beyla.yaml"
  expect_red 'beyla on' 'beyla/opencost/kepler/pyroscope resource renders' assert_features_off "${tmp}/beyla.yaml"
  render chart "${full[@]}" --set upstream.costMetrics.enabled=true --set upstream.costMetrics.collector=alloy-metrics \
    --set upstream.telemetryServices.opencost.deploy=true --set upstream.telemetryServices.opencost.metricsSource=custom \
    --set upstream.telemetryServices.opencost.opencost.exporter.defaultClusterId=lapras >"${tmp}/cost.yaml"
  expect_red 'costMetrics on' 'enabled features differ: .*Cost Metrics' assert_features_off "${tmp}/cost.yaml"
  render chart "${full[@]}" --set upstream.clusterEvents.enabled=true --set upstream.clusterEvents.collector=alloy-metrics >"${tmp}/events.yaml"
  expect_red 'clusterEvents on' 'enabled features differ: .*Cluster Events' assert_features_off "${tmp}/events.yaml"
  ;;
gigapipe-naming)
  assert_naming .
  mkdir -p "${tmp}/legacy"
  cp -a chart Taskfile.yaml README.md CLAUDE.md infra tasks scripts docs .github "${tmp}/legacy/"
  yq -i '.upstream.destinations.gigapipe.url = "http://q" + "ryn.telemetry.svc:3100"' "${tmp}/legacy/chart/values.yaml"
  expect_red 'a legacy destination ref' 'legacy destination name' assert_naming "${tmp}/legacy"
  ;;
secret)
  assert_auth_via_eso chart
  assert_no_literal_secrets chart
  render chart --values chart/values.example.yaml >"${tmp}/secret.yaml"
  json "${tmp}/secret.yaml" | need_jq 'ExternalSecret shape or folder-derived prefixes are wrong' '
    map(select(.kind == "ExternalSecret")) as $es | ($es | length) == 1 and $es[0].spec.data == null and
    $es[0].metadata.name == "aluminium-secrets" and $es[0].spec.target.name == "aluminium-secrets" and
    ($es[0].spec.dataFrom | map(.find.path)) == ["/shared", "/aluminium"] and
    ($es[0].spec.dataFrom | map(.rewrite[0].regexp.target)) == ["SHARED_$1", "ALUMINIUM_$1"]'
  config_text "${tmp}/secret.yaml" "${tmp}/secret.alloy"
  need 'destination credentials are not read from the aluminium-secrets ExternalSecret target' rg -q 'name += "aluminium-secrets"' "${tmp}/secret.alloy"
  expect_refusal 'collide' --set secret.serviceFolder=/shared
  expect_refusal 'yields an empty key prefix' --set secret.serviceFolder=/
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/secrets.yaml"
    assert_no_rendered_secret "${tmp}/secrets.yaml"
  done
  copy_chart "${tmp}/create"
  yq -i '.upstream.destinations.gigapipe.secret.create = true' "${tmp}/create/chart/values.yaml"
  expect_red 'destination creates its own Secret' 'authenticates without the ExternalSecret target' assert_auth_via_eso "${tmp}/create/chart"
  copy_chart "${tmp}/other"
  yq -i '.upstream.destinations.victoriametrics.secret.name = "other-secret"' "${tmp}/other/chart/values.yaml"
  expect_red 'destination reads another Secret' 'authenticates without the ExternalSecret target' assert_auth_via_eso "${tmp}/other/chart"
  copy_chart "${tmp}/literal"
  yq -i '.upstream.destinations.gigapipe.auth.password = "fixture-literal"' "${tmp}/literal/chart/values.yaml"
  expect_red 'a literal password' 'literal credential' assert_no_literal_secrets "${tmp}/literal/chart"
  copy_chart "${tmp}/userinfo"
  yq -i '.upstream.destinations.gigapipe.url = "http://telemetry:fixture@gigapipe.telemetry.svc:3100"' "${tmp}/userinfo/chart/values.yaml"
  expect_red 'URL userinfo' 'literal credential' assert_no_literal_secrets "${tmp}/userinfo/chart"
  copy_chart "${tmp}/header"
  yq -i '.upstream.destinations.gigapipe.extraHeaders = {"Authorization": "Bearer fixture"}' "${tmp}/header/chart/values.yaml"
  expect_red 'an Authorization header' 'literal credential' assert_no_literal_secrets "${tmp}/header/chart"
  copy_chart "${tmp}/token-header"
  yq -i '.upstream.destinations.victoriametrics.extraHeaders = {"X-Access-Token": "fixture"}' "${tmp}/token-header/chart/values.yaml"
  expect_red 'a token header' 'literal credential' assert_no_literal_secrets "${tmp}/token-header/chart"
  render "${tmp}/literal/chart" "${full[@]}" --set upstream.destinations.gigapipe.auth.type=basic --set upstream.destinations.gigapipe.auth.username=telemetry --set upstream.destinations.gigapipe.secret.embed=false --set upstream.destinations.gigapipe.secret.create=true >"${tmp}/literal.yaml"
  expect_red 'a chart-rendered credential Secret' 'renders a Secret' assert_no_rendered_secret "${tmp}/literal.yaml"
  ;;
otlp-everywhere)
  assert_values_otlp chart
  assert_no_raw_river chart
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/otlp-render.yaml"
    assert_rendered_otlp "${tmp}/otlp-render.yaml"
  done
  copy_chart "${tmp}/knob"
  yq -i '.upstream.destinations.gigapipe.logs.protocol = "grpc"' "${tmp}/knob/chart/values.yaml"
  expect_red 'a per-signal protocol knob' 'signal block carries more than enabled' assert_values_otlp "${tmp}/knob/chart"
  copy_chart "${tmp}/remote-write"
  yq -i '.upstream.destinations.victoriametrics = {"type": "prometheus", "url": "http://victoriametrics.telemetry.svc:8428/api/v1/write"}' "${tmp}/remote-write/chart/values.yaml"
  expect_red 'a non-OTLP destination' 'is not OTLP/HTTP' assert_values_otlp "${tmp}/remote-write/chart"
  render chart "${full[@]}" --set-string 'upstream.collectors.alloy-metrics.extraConfig=prometheus.remote_write "x" {}' >"${tmp}/raw-writer.yaml"
  expect_red 'a raw non-OTLP writer in the render' 'non-OTLP/HTTP writer renders' assert_rendered_otlp "${tmp}/raw-writer.yaml"
  copy_chart "${tmp}/raw"
  yq -i '.upstream.collectors.alloy-logs.extraConfig = "logging { level = \"debug\" }"' "${tmp}/raw/chart/values.yaml"
  expect_red 'raw Alloy config in values' 'raw Alloy config' assert_no_raw_river "${tmp}/raw/chart"
  ;;
lpsm-labels)
  render chart >"${tmp}/lpsm-base.yaml"
  assert_lpsm atomi.cloud "${tmp}/lpsm-base.yaml" "" ""
  render chart --values chart/values.example.yaml >"${tmp}/lpsm-example.yaml"
  assert_lpsm atomi.cloud "${tmp}/lpsm-example.yaml" example ""
  render chart "${full[@]}" --set secret.enabled=true >"${tmp}/lpsm-full.yaml"
  assert_lpsm atomi.cloud "${tmp}/lpsm-full.yaml" example lapras
  expect_refusal 'collectorCommon.alloy.labels must equal' "${full[@]}" --set labelPrefix=example.dev
  expect_refusal 'collectorCommon.alloy.labels must equal' "${full[@]}" --set serviceTree.cluster=other
  expect_refusal 'must equal release namespace' --namespace other
  render chart "${full[@]}" --set 'upstream.collectors.alloy-logs.labels.atomi\.cloud/service=drift' >"${tmp}/lpsm-drift.yaml"
  expect_red 'a per-collector label override' 'labels differ from the LPSM set' assert_lpsm atomi.cloud "${tmp}/lpsm-drift.yaml" example lapras
  ;;
rendered-manifests)
  index=0
  for stack in "${stacks[@]}"; do
    index=$((index + 1))
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/rendered-${index}.yaml"
    vap_stage "${tmp}/rendered-${index}.yaml" "stack ${stack:-values.yaml}"
  done
  render chart "${full[@]}" --set upstream.alloy-operator.image.tag=latest >"${tmp}/latest.yaml"
  expect_red 'a :latest operator image' 'explicit non-latest tag' vap_stage "${tmp}/latest.yaml" latest
  render chart "${full[@]}" --set upstream.collectors.alloy-metrics.image.tag=latest >"${tmp}/latest-collector.yaml"
  expect_red 'a :latest collector image' 'StatefulSet/aluminium-alloy-metrics failed' vap_stage "${tmp}/latest-collector.yaml" latest-collector
  render chart "${full[@]}" --set upstream.collectors.alloy-metrics.alloy.securityContext.readOnlyRootFilesystem=false >"${tmp}/writable.yaml"
  expect_red 'a writable alloy-metrics root filesystem' 'StatefulSet/aluminium-alloy-metrics failed' vap_stage "${tmp}/writable.yaml" writable
  render chart "${full[@]}" --set upstream.collectors.alloy-logs.alloy.securityContext.readOnlyRootFilesystem=false >"${tmp}/writable-logs.yaml"
  expect_red 'a writable alloy-logs root filesystem' 'alloy-logs deviates from the VAP beyond running as root' vap_stage "${tmp}/writable-logs.yaml" writable-logs
  render chart "${full[@]}" --set upstream.collectors.alloy-logs.configReloader.enabled=true --set upstream.collectors.alloy-logs.configReloader.resources=null >"${tmp}/unbounded-logs.yaml"
  expect_red 'alloy-logs without container limits' 'denied for something other than root' vap_stage "${tmp}/unbounded-logs.yaml" unbounded-logs
  ;;
pin)
  dep="$(yq -o=json '.dependencies[] | select(.name == "k8s-monitoring")' chart/Chart.yaml)"
  version="$(jq -r .version <<<"${dep}")"
  [[ ${version} =~ ^4\.[0-9]+\.[0-9]+$ ]] || { echo "❌ k8s-monitoring ${version} is not a pinned 4.x" >&2 && exit 1; }
  [ "$(jq -r .alias <<<"${dep}")" = upstream ] || { echo "❌ k8s-monitoring is not aliased upstream" >&2 && exit 1; }
  [ "$(yq -r '.dependencies[] | select(.name == "k8s-monitoring") | .version' chart/Chart.lock)" = "${version}" ] || { echo "❌ Chart.lock differs from Chart.yaml" >&2 && exit 1; }
  [ "$(git ls-files 'chart/charts/*.tgz')" = "chart/charts/k8s-monitoring-${version}.tgz" ] || { echo "❌ the vendored archive is not k8s-monitoring-${version}.tgz" >&2 && exit 1; }
  [ "$(yq -r .appVersion chart/Chart.yaml)" = "${version}" ] || { echo "❌ appVersion differs from the k8s-monitoring version" >&2 && exit 1; }
  operator="$(tar -xzOf "chart/charts/k8s-monitoring-${version}.tgz" k8s-monitoring/charts/alloy-operator/Chart.yaml | yq -r .appVersion)"
  # The operator image embeds the alloy chart of its own version (checked in alloy-operator:1.14.4).
  [ "$(tar -xzOf "${operator_chart}" alloy/Chart.yaml | yq -r .version)" = "${operator}" ] || { echo "❌ ${operator_chart} is not the alloy chart embedded by alloy-operator ${operator}" >&2 && exit 1; }
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/aluminium-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/aluminium-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'a tag that differs from Chart.yaml' 'does not match tag 9.9.9' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh
  ;;
presence)
  test -s docs/developer/aluminium-baseline.md
  test -s .claude/skills/aluminium/SKILL.md
  test -s policies/vap/workload-baseline.yaml
  test -s schemas/alloy.json
  test -s "${operator_chart}"
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ aluminium ${mode} validation passed"
