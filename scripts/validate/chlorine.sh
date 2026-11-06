#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs are single-quoted on purpose
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-chlorine}"
namespace="${NAMESPACE:-reloader}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

stacks=("" "--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")
full=(--values chart/values.example.yaml --values chart/values.lapras.yaml)
labelled='["ClusterRole/chlorine-reloader-role","ClusterRoleBinding/chlorine-reloader-role-binding","Deployment/chlorine-reloader","Role/chlorine-reloader-metadata-role","RoleBinding/chlorine-reloader-metadata-role-binding","ServiceAccount/chlorine-reloader"]'

render() {
  local chart="$1"
  shift
  helm template "${release}" "${chart}" --namespace "${namespace}" "$@"
}

json() { yq eval-all -o=json '.' "$1" | jq -s 'map(select(.kind != null))'; }

need_jq() {
  local reason="$1"
  shift
  jq -e "$@" >/dev/null || { echo "❌ ${reason}" >&2 && return 1; }
}

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

copy_tree() {
  mkdir -p "$1"
  cp -a chart "$1/"
}

want_lpsm() {
  local chart="$1"
  shift
  local files=("${chart}/values.yaml")
  while [ "$#" -gt 0 ]; do
    files+=("${2/chart\//${chart}/}")
    shift 2
  done
  yq eval-all -o=json '. as $item ireduce ({}; . * $item) | .labelPrefix as $p | .serviceTree | with_entries(.key = $p + "/" + .key)' "${files[@]}"
}

assert_lpsm() {
  local file="$1" want="$2"
  json "${file}" | need_jq 'Reloader objects differ from the LPSM label set' --argjson want "${want}" --argjson objs "${labelled}" '
    def has_lpsm: . as $l | ($want | length) >= 4 and all($want | to_entries[]; $l[.key] == .value);
    (map(.kind + "/" + .metadata.name) | sort) == $objs and
    all(.[]; .metadata.labels | has_lpsm) and
    all(.[] | select(.kind == "Deployment"); .spec.template.metadata.labels | has_lpsm)'
}

controller() { json "$1" | jq '[.[] | select(.kind == "Deployment")] | if length == 1 then .[0] else error("expected exactly one Deployment") end'; }

assert_opt_in() {
  controller "$1" | need_jq 'Reloader is not annotation opt-in (auto-reload-all is on)' '
    (.spec.template.spec.containers[0].args // []) as $a |
    all($a[]; test("^--auto-reload-all") | not)' || return 1
  controller "$1" | need_jq 'Reloader does not use the default rolling-restart strategy' '
    all((.spec.template.spec.containers[0].args // [])[]; test("^--reload-strategy") | not)'
}

assert_self_opt_in() {
  controller "$1" | need_jq "the chlorine Deployment does not carry reloader.stakater.com/auto=$2" --arg want "$2" '
    .metadata.annotations["reloader.stakater.com/auto"] == $want'
}

assert_payload_pure() {
  json "$1" | need_jq 'the render ships a monitoring object (ServiceMonitor/PodMonitor/PrometheusRule/dashboard)' '
    all(.[]; (.kind | IN("ServiceMonitor", "PodMonitor", "PrometheusRule", "GrafanaDashboard")) | not) and
    all(.[] | select(.kind == "ConfigMap"); (.metadata.labels // {}) | has("grafana_dashboard") | not)'
}

vap_stage() {
  kubeconform -strict -summary -schema-location default "$1"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "$1" >"$1.vap.yaml"
  json "$1.vap.yaml" | need_jq "the Reloader Deployment is not the VAP input ($2)" '(map(.kind + "/" + .metadata.name)) == ["Deployment/chlorine-reloader"]' || return 1
  kyverno apply policies/vap --resource "$1.vap.yaml" --detailed-results --remove-color >"$1.vap.txt" 2>&1 ||
    { cat "$1.vap.txt" >&2 && echo "❌ the Reloader workload fails the VAP ($2)" >&2 && return 1; }
  rg -q '^pass: [1-9][0-9]*, fail: 0, warn: 0, error: 0' "$1.vap.txt" || { cat "$1.vap.txt" >&2 && echo "❌ the VAP stage evaluated nothing ($2)" >&2 && return 1; }
}

assert_pin() {
  local chart="$1" dep version
  dep="$(yq -o=json '.dependencies[] | select(.name == "reloader")' "${chart}/Chart.yaml")"
  version="$(jq -r .version <<<"${dep}")"
  [[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ reloader ${version} is not an exact pin" >&2 && return 1; }
  [ "$(jq -r .alias <<<"${dep}")" = upstream ] || { echo "❌ reloader is not aliased upstream" >&2 && return 1; }
  [ "$(yq -r '.dependencies[] | select(.name == "reloader") | .version' "${chart}/Chart.lock")" = "${version}" ] || { echo "❌ Chart.lock differs from Chart.yaml" >&2 && return 1; }
  [ "$(cd "${chart}/charts" && printf '%s\n' *.tgz)" = "reloader-${version}.tgz" ] || { echo "❌ the vendored archive is not reloader-${version}.tgz" >&2 && return 1; }
  app="$(yq -r .appVersion "${chart}/Chart.yaml")"
  [ "$(tar -xzOf "${chart}/charts/reloader-${version}.tgz" reloader/Chart.yaml | yq -r .version)" = "${version}" ] || { echo "❌ the vendored archive is not chart ${version}" >&2 && return 1; }
  [ "$(tar -xzOf "${chart}/charts/reloader-${version}.tgz" reloader/Chart.yaml | yq -r .appVersion)" = "${app}" ] || { echo "❌ appVersion ${app} is not the vendored chart's appVersion" >&2 && return 1; }
  [ "$(render "${chart}" "${full[@]/chart\//${chart}/}" | yq -N 'select(.kind == "Deployment") | .spec.template.spec.containers[].image')" = "ghcr.io/stakater/reloader:${app}" ] ||
    { echo "❌ the controller image is not ghcr.io/stakater/reloader:${app}" >&2 && return 1; }
  mkdir -p "${tmp}/pull"
  helm pull "$(jq -r .repository <<<"${dep}")/reloader" --version "${version}" --destination "${tmp}/pull" >/dev/null
  cmp -s "${tmp}/pull/reloader-${version}.tgz" "${chart}/charts/reloader-${version}.tgz" ||
    { echo "❌ the vendored archive sha256 $(sha256sum "${chart}/charts/reloader-${version}.tgz" | cut -c1-64) is not upstream's $(sha256sum "${tmp}/pull/reloader-${version}.tgz" | cut -c1-64)" >&2 && return 1; }
  rm -rf "${tmp}/pull"
}

case "${mode}" in
schema)
  expect_red 'layer is not numeric' "serviceTree/layer.*does not match pattern|at '/serviceTree/layer'" helm lint chart --namespace "${namespace}" --set-string serviceTree.layer=one
  expect_red 'dashed platform' "serviceTree/platform.*does not match pattern|at '/serviceTree/platform'" helm lint chart --namespace stakater-reloader --set serviceTree.platform=stakater-reloader
  expect_red 'autoReloadAll is not a boolean' "autoReloadAll" helm lint chart --namespace "${namespace}" --set-string upstream.reloader.autoReloadAll=yes
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack} >"${tmp}/lint.txt" 2>&1 ||
      { echo "❌ helm lint rejected the stack '${stack:-values.yaml}'" >&2 && cat "${tmp}/lint.txt" >&2 && exit 1; }
  done
  ;;
render)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/render.yaml"
    json "${tmp}/render.yaml" | need_jq "stack '${stack:-values.yaml}' renders no Reloader controller" 'map(select(.kind == "Deployment")) | length == 1'
  done
  expect_refusal 'must equal release namespace' "${full[@]}" --namespace other
  ;;
lpsm-labels)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/lpsm.yaml"
    # shellcheck disable=SC2086
    assert_lpsm "${tmp}/lpsm.yaml" "$(want_lpsm chart ${stack})"
  done
  render chart "${full[@]}" --set serviceTree.cluster=other >"${tmp}/drift.yaml"
  expect_red 'serviceTree changed without its labels' 'differ from the LPSM label set' assert_lpsm "${tmp}/drift.yaml" "$(want_lpsm chart "${full[@]}" | jq -c '.["atomi.cloud/cluster"] = "other"')"
  render chart "${full[@]}" --set labelPrefix=example.dev >"${tmp}/prefix.yaml"
  expect_red 'labelPrefix changed without its labels' 'differ from the LPSM label set' assert_lpsm "${tmp}/prefix.yaml" "$(want_lpsm chart "${full[@]}" | jq -c 'with_entries(.key |= sub("^atomi.cloud/"; "example.dev/"))')"
  copy_tree "${tmp}/nolabels"
  yq -i 'del(.upstream.reloader.serviceAccount.labels)' "${tmp}/nolabels/chart/values.yaml" "${tmp}/nolabels/chart/values.example.yaml" "${tmp}/nolabels/chart/values.lapras.yaml"
  render "${tmp}/nolabels/chart" "${full[@]}" >"${tmp}/nolabels.yaml"
  expect_red 'ServiceAccount LPSM labels dropped' 'differ from the LPSM label set' assert_lpsm "${tmp}/nolabels.yaml" "$(want_lpsm chart "${full[@]}")"
  ;;
reload-stance)
  [ "$(yq -r '.upstream.reloader.autoReloadAll' chart/values.yaml)" = false ] || { echo "❌ values.yaml does not pin autoReloadAll: false" >&2 && exit 1; }
  for f in chart/values.*.yaml; do
    [ "$(yq -r '.upstream.reloader.autoReloadAll == null' "${f}")" = true ] || { echo "❌ ${f} overrides autoReloadAll" >&2 && exit 1; }
  done
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/stance.yaml"
    assert_opt_in "${tmp}/stance.yaml"
    assert_self_opt_in "${tmp}/stance.yaml" true
  done
  render chart "${full[@]}" --set upstream.reloader.autoReloadAll=true >"${tmp}/all.yaml"
  expect_red 'a values flip to auto-reload-all' 'not annotation opt-in' assert_opt_in "${tmp}/all.yaml"
  render chart "${full[@]}" --set upstream.reloader.reloadStrategy=annotations >"${tmp}/env.yaml"
  expect_red 'a non-default reload strategy' 'default rolling-restart strategy' assert_opt_in "${tmp}/env.yaml"
  render chart "${full[@]}" --set-string 'upstream.reloader.deployment.annotations.reloader\.stakater\.com/auto=false' >"${tmp}/optout.yaml"
  assert_self_opt_in "${tmp}/optout.yaml" false
  copy_tree "${tmp}/noself"
  yq -i 'del(.upstream.reloader.deployment.annotations)' "${tmp}/noself/chart/values.yaml"
  render "${tmp}/noself/chart" "${full[@]}" >"${tmp}/noself.yaml"
  expect_red 'Reloader self opt-in dropped' 'reloader.stakater.com/auto=true' assert_self_opt_in "${tmp}/noself.yaml" true
  ;;
payload-purity)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/payload.yaml"
    assert_payload_pure "${tmp}/payload.yaml"
  done
  for kind in serviceMonitor podMonitor; do
    render chart "${full[@]}" --api-versions monitoring.coreos.com/v1 --set "upstream.reloader.${kind}.enabled=true" >"${tmp}/${kind}.yaml"
    expect_red "upstream ${kind} on" 'ships a monitoring object' assert_payload_pure "${tmp}/${kind}.yaml"
  done
  ;;
rendered-manifests)
  index=0
  for stack in "${stacks[@]}"; do
    index=$((index + 1))
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/rendered-${index}.yaml"
    vap_stage "${tmp}/rendered-${index}.yaml" "stack ${stack:-values.yaml}"
  done
  render chart "${full[@]}" --set upstream.image.tag=latest >"${tmp}/latest.yaml"
  expect_red 'a :latest controller image' 'explicit non-latest tag' vap_stage "${tmp}/latest.yaml" latest
  ;;
pin)
  assert_pin chart
  copy_tree "${tmp}/tamper"
  archive="$(cd "${tmp}/tamper/chart/charts" && printf '%s' reloader-*.tgz)"
  mkdir -p "${tmp}/repack" && tar -xzf "${tmp}/tamper/chart/charts/${archive}" -C "${tmp}/repack"
  printf '# tampered\n' >>"${tmp}/repack/reloader/values.yaml"
  tar -czf "${tmp}/tamper/chart/charts/${archive}" -C "${tmp}/repack" reloader
  expect_red 'a vendored archive that is not upstream bytes' 'is not upstream' assert_pin "${tmp}/tamper/chart"
  copy_tree "${tmp}/drift"
  yq -i '.appVersion = "v0.0.1"' "${tmp}/drift/chart/Chart.yaml"
  expect_red 'appVersion off the vendored chart' "appVersion v0.0.1 is not the vendored chart's appVersion" assert_pin "${tmp}/drift/chart"
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/chlorine-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/chlorine-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'a tag that differs from Chart.yaml' 'does not match tag 9.9.9' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh
  ;;
presence)
  test -s docs/developer/chlorine-baseline.md
  test -s .claude/skills/chlorine/SKILL.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ chlorine ${mode} validation passed"
