#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-aluminium}"
namespace="${NAMESPACE:-telemetry}"
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

json() { yq eval-all -o=json '.' "$1" | jq -s 'map(select(.kind != null))'; }

config_text() { json "$1" | jq -r '[.[] | select(.kind == "ConfigMap") | (.data // {})[]] | join("\n")'; }

# Runs a check that must fail on a sabotaged input; a pass means the check is blind.
expect_red() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "❌ negative fixture '${label}' was not caught" >&2 && exit 1
  fi
}

expect_refusal() {
  local pattern="$1"
  shift
  if render chart "$@" >/dev/null 2>"${tmp}/refusal.txt"; then
    echo "❌ accepted: $*" >&2 && exit 1
  fi
  rg -q -- "${pattern}" "${tmp}/refusal.txt" || { echo "❌ wrong refusal for $*" >&2 && cat "${tmp}/refusal.txt" >&2 && exit 1; }
}

copy_chart() {
  mkdir -p "$1"
  cp -a chart "$1/chart"
}

assert_topology() {
  json "$1" | jq -e '
    [.[] | select(.kind == "Alloy")] as $a |
    ($a | map(.metadata.name) | sort) == ["aluminium-alloy-logs", "aluminium-alloy-metrics"] and
    ($a[] | select(.metadata.name == "aluminium-alloy-metrics") |
      .spec.controller.type == "statefulset" and .spec.alloy.clustering.enabled == true) and
    ($a[] | select(.metadata.name == "aluminium-alloy-logs") |
      .spec.controller.type == "daemonset" and (.spec.alloy.clustering.enabled // false) == false and
      .spec.alloy.mounts.varlog == true)' >/dev/null
}

assert_otlp_receiver() {
  json "$1" | jq -e '
    [.[] | select(.kind == "Alloy")] as $a |
    ($a[] | select(.metadata.name == "aluminium-alloy-metrics") | [.spec.alloy.extraPorts[]? | select(.port == 4318)]) ==
      [{"appProtocol": "http", "name": "otlp-http", "port": 4318, "protocol": "TCP", "targetPort": 4318}] and
    ($a[] | select(.metadata.name == "aluminium-alloy-metrics") | [.spec.alloy.extraPorts[]? | select(.port == 4317)] | length) == 0 and
    ($a[] | select(.metadata.name == "aluminium-alloy-logs") | [.spec.alloy.extraPorts[]?] | length) == 0' >/dev/null || return 1
  json "$1" | jq -r '.[] | select(.kind == "ConfigMap" and .metadata.name == "aluminium-alloy-metrics") | .data[]' >"${tmp}/metrics.alloy"
  json "$1" | jq -r '.[] | select(.kind == "ConfigMap" and .metadata.name == "aluminium-alloy-logs") | .data[]' >"${tmp}/logs.alloy"
  rg -q 'endpoint = "0\.0\.0\.0:4318"' "${tmp}/metrics.alloy" || return 1
  if rg -q 'otelcol\.receiver\.otlp|grpc \{' "${tmp}/logs.alloy" || rg -q 'grpc \{' "${tmp}/metrics.alloy"; then return 1; fi
}

assert_features_off() {
  local features
  features="$(config_text "$1" | rg -o '^\s*// Feature: .*' | sed 's/^ *//' | LC_ALL=C sort -u)"
  [ "${features}" = $'// Feature: Application Observability\n// Feature: Cluster Metrics\n// Feature: Pod Logs (OpenTelemetry)' ] || return 1
  if config_text "$1" | rg -qi '// Self Reporting|kubernetes_monitoring_telemetry'; then return 1; fi
  json "$1" | jq -e 'all(.[]; (.metadata.labels["app.kubernetes.io/name"] // "" | test("beyla|opencost|kepler|pyroscope"; "i") | not) and (.metadata.name | test("beyla|opencost|kepler"; "i") | not))' >/dev/null
}

assert_naming() {
  if rg -n -i --glob '!chart/charts/**' 'q[r]yn' "$1/chart" "$1/Taskfile.yaml" "$1/scripts" "$1/.github/workflows" "$1/docs/developer" >&2; then return 1; fi
  yq -o=json '.upstream.destinations' "$1/chart/values.yaml" |
    jq -e '.gigapipe.type == "otlp" and .gigapipe.logs.enabled == true and .gigapipe.traces.enabled == true' >/dev/null
}

credential_keys='^(password|passphrase|token|bearerToken|apiKey|api[_-]?key|clientSecret|client[_-]?secret|secretKey|accessKey|privateKey|credentials?)$'

assert_no_literal_secrets() {
  yq eval-all -o=json '.' "$1"/values*.yaml | jq -s -e --arg keys "${credential_keys}" '
    [.[] | .. | objects | to_entries[] | select((.key | test($keys; "i")) and .value != null and .value != "")] | length == 0' >/dev/null
}

assert_no_rendered_secret() { json "$1" | jq -e 'map(select(.kind == "Secret")) | length == 0' >/dev/null; }

assert_otlp_everywhere() {
  yq eval-all -o=json '.' "$1"/values*.yaml | jq -s -e '
    map(.upstream.destinations // {}) | reduce .[] as $d ({}; . * $d) |
    length > 0 and all(.[];
      .type == "otlp" and .protocol == "http" and
      all(.metrics, .logs, .traces; (. // {}) | keys - ["enabled"] == []))' >/dev/null || return 1
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render "$1" ${stack} >"${tmp}/otlp-render.yaml" || return 1
    config_text "${tmp}/otlp-render.yaml" >"${tmp}/otlp.alloy"
    rg -q '^otelcol\.exporter\.otlphttp "' "${tmp}/otlp.alloy" || return 1
    if rg -q '^(otelcol\.exporter\.otlp |prometheus\.remote_write |loki\.write |pyroscope\.write )' "${tmp}/otlp.alloy"; then return 1; fi
  done
}

assert_lpsm() {
  local prefix="$1" file="$2" landscape="$3" cluster="$4"
  json "${file}" | jq -e --arg p "${prefix}" --arg l "${landscape}" --arg c "${cluster}" '
    ({($p + "/platform"): "telemetry", ($p + "/service"): "aluminium", ($p + "/module"): "telemetry", ($p + "/layer"): "1"}
      + (if $l == "" then {} else {($p + "/landscape"): $l} end)
      + (if $c == "" then {} else {($p + "/cluster"): $c} end)) as $want |
    [.[] | select(.kind == "Alloy")] as $a |
    ($a | length) == 2 and
    all($a[]; .metadata.labels == $want and .spec.controller.podLabels == $want) and
    all(.[] | select(.kind == "ExternalSecret"); .metadata.labels as $l | all($want | to_entries[]; $l[.key] == .value))' >/dev/null
}

case "${mode}" in
schema)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack} >"${tmp}/schema.txt" 2>&1 ||
      { echo "❌ schema rejected the stack '${stack:-values.yaml}'" >&2 && cat "${tmp}/schema.txt" >&2 && exit 1; }
  done
  expect_red 'layer is not numeric' helm lint chart --namespace "${namespace}" --set-string serviceTree.layer=one
  expect_red 'unknown secret store kind' helm lint chart --namespace "${namespace}" --set secret.store.kind=Vault
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
  expect_red 'alloy-metrics without clustering' assert_topology "${tmp}/unclustered.yaml"
  render chart "${full[@]}" --set 'upstream.collectors.alloy-logs.presets={daemonset,clustered}' >"${tmp}/clustered-logs.yaml"
  expect_red 'alloy-logs with clustering' assert_topology "${tmp}/clustered-logs.yaml"
  ;;
otlp-contract)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/otlp.yaml"
    assert_otlp_receiver "${tmp}/otlp.yaml"
  done
  render chart "${full[@]}" --set upstream.applicationObservability.receivers.otlp.http.port=4319 >"${tmp}/port.yaml"
  expect_red 'receiver moved off 4318' assert_otlp_receiver "${tmp}/port.yaml"
  render chart "${full[@]}" --set upstream.applicationObservability.collector=alloy-logs >"${tmp}/assignment.yaml"
  expect_red 'receiver assigned to alloy-logs' assert_otlp_receiver "${tmp}/assignment.yaml"
  render chart "${full[@]}" --set upstream.applicationObservability.receivers.otlp.grpc.enabled=true >"${tmp}/grpc.yaml"
  expect_red 'grpc receiver enabled' assert_otlp_receiver "${tmp}/grpc.yaml"
  ;;
features-off)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/features.yaml"
    assert_features_off "${tmp}/features.yaml"
  done
  render chart "${full[@]}" --set upstream.selfReporting.enabled=true >"${tmp}/self.yaml"
  expect_red 'selfReporting on' assert_features_off "${tmp}/self.yaml"
  render chart "${full[@]}" --set upstream.telemetryServices.beyla.deploy=true >"${tmp}/beyla.yaml"
  expect_red 'beyla on' assert_features_off "${tmp}/beyla.yaml"
  render chart "${full[@]}" --set upstream.costMetrics.enabled=true --set upstream.costMetrics.collector=alloy-metrics \
    --set upstream.telemetryServices.opencost.deploy=true --set upstream.telemetryServices.opencost.metricsSource=custom \
    --set upstream.telemetryServices.opencost.opencost.exporter.defaultClusterId=lapras >"${tmp}/cost.yaml"
  expect_red 'costMetrics on' assert_features_off "${tmp}/cost.yaml"
  render chart "${full[@]}" --set upstream.clusterEvents.enabled=true --set upstream.clusterEvents.collector=alloy-metrics >"${tmp}/events.yaml"
  expect_red 'clusterEvents on' assert_features_off "${tmp}/events.yaml"
  ;;
gigapipe-naming)
  assert_naming .
  mkdir -p "${tmp}/legacy"
  cp -a chart Taskfile.yaml scripts docs .github "${tmp}/legacy/"
  yq -i '.upstream.destinations.gigapipe.url = "http://q" + "ryn.telemetry.svc:3100"' "${tmp}/legacy/chart/values.yaml"
  expect_red 'a legacy destination ref' assert_naming "${tmp}/legacy"
  ;;
secret)
  render chart --values chart/values.example.yaml >"${tmp}/secret.yaml"
  json "${tmp}/secret.yaml" | jq -e '
    map(select(.kind == "ExternalSecret")) as $es | ($es | length) == 1 and $es[0].spec.data == null and
    $es[0].metadata.name == "aluminium-secrets" and $es[0].spec.target.name == "aluminium-secrets" and
    ($es[0].spec.dataFrom | map(.find.path)) == ["/shared", "/aluminium"] and
    ($es[0].spec.dataFrom | map(.rewrite[0].regexp.target)) == ["SHARED_$1", "ALUMINIUM_$1"]' >/dev/null ||
    { echo "❌ ExternalSecret shape or folder-derived prefixes are wrong" >&2 && exit 1; }
  expect_refusal 'collide' --set secret.serviceFolder=/shared
  expect_refusal 'yields an empty key prefix' --set secret.serviceFolder=/
  assert_no_literal_secrets chart
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/secrets.yaml"
    assert_no_rendered_secret "${tmp}/secrets.yaml"
  done
  copy_chart "${tmp}/literal"
  yq -i '.upstream.destinations.gigapipe.auth = {"type": "basic", "username": "telemetry", "password": "fixture-literal"}' "${tmp}/literal/chart/values.yaml"
  expect_red 'a literal credential in values' assert_no_literal_secrets "${tmp}/literal/chart"
  render "${tmp}/literal/chart" "${full[@]}" >"${tmp}/literal.yaml"
  expect_red 'a chart-rendered credential Secret' assert_no_rendered_secret "${tmp}/literal.yaml"
  ;;
otlp-everywhere)
  assert_otlp_everywhere chart
  copy_chart "${tmp}/knob"
  yq -i '.upstream.destinations.gigapipe.logs.protocol = "grpc"' "${tmp}/knob/chart/values.yaml"
  expect_red 'a per-signal protocol knob' assert_otlp_everywhere "${tmp}/knob/chart"
  copy_chart "${tmp}/remote-write"
  yq -i '.upstream.destinations.victoriametrics = {"type": "prometheus", "url": "http://victoriametrics.telemetry.svc:8428/api/v1/write"}' "${tmp}/remote-write/chart/values.yaml"
  expect_red 'a non-OTLP destination' assert_otlp_everywhere "${tmp}/remote-write/chart"
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
  expect_red 'a per-collector label override' assert_lpsm atomi.cloud "${tmp}/lpsm-drift.yaml" example lapras
  ;;
rendered-manifests)
  index=0
  for stack in "${stacks[@]}"; do
    index=$((index + 1))
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/rendered-${index}.yaml"
    kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/rendered-${index}.yaml"
    yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered-${index}.yaml" >"${tmp}/vap-resources-${index}.yaml"
    kyverno apply policies/vap --resource "${tmp}/vap-resources-${index}.yaml" --detailed-results --remove-color
  done
  render chart "${full[@]}" --set upstream.alloy-operator.image.tag=latest >"${tmp}/latest.yaml"
  yq eval-all 'select(.kind == "Deployment")' "${tmp}/latest.yaml" >"${tmp}/vap-latest.yaml"
  if kyverno apply policies/vap --resource "${tmp}/vap-latest.yaml" --remove-color >"${tmp}/kyverno-latest.txt" 2>&1; then
    echo "❌ the :latest wiring sabotage passed the VAP stage" >&2 && exit 1
  fi
  rg -q 'explicit non-latest tag' "${tmp}/kyverno-latest.txt"
  ;;
pin)
  dep="$(yq -o=json '.dependencies[] | select(.name == "k8s-monitoring")' chart/Chart.yaml)"
  version="$(jq -r .version <<<"${dep}")"
  [[ ${version} =~ ^4\.[0-9]+\.[0-9]+$ ]] || { echo "❌ k8s-monitoring ${version} is not a pinned 4.x" >&2 && exit 1; }
  [ "$(jq -r .alias <<<"${dep}")" = upstream ]
  [ "$(yq -r '.dependencies[] | select(.name == "k8s-monitoring") | .version' chart/Chart.lock)" = "${version}" ]
  [ "$(git ls-files 'chart/charts/*.tgz')" = "chart/charts/k8s-monitoring-${version}.tgz" ]
  [ "$(yq -r .appVersion chart/Chart.yaml)" = "${version}" ]
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
  if PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null 2>&1; then
    echo "❌ publish accepted a tag that differs from Chart.yaml" >&2 && exit 1
  fi
  ;;
presence)
  test -s docs/developer/aluminium-baseline.md
  test -s .claude/skills/aluminium/SKILL.md
  test -s policies/vap/workload-baseline.yaml
  test -s schemas/alloy.json
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ aluminium ${mode} validation passed"
