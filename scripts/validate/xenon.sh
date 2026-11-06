#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs are single-quoted on purpose
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-xenon}"
namespace="${NAMESPACE:-metrics}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export HELM_REPOSITORY_CONFIG="${tmp}/repositories.yaml" HELM_REPOSITORY_CACHE="${tmp}/repository-cache"

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

landscapes='["primordial","lapras","ditto","rotom","absol","eevee","castform","serving"]'
expected='{"primordial":"ON","lapras":"OFF","ditto":"OFF","rotom":"OFF","absol":"OFF","eevee":"ON","castform":"ON","serving":"per-cluster"}'
substrates='[{"substrate":"EKS classic","builtInMetricsProvider":false,"xenon":"ON"},{"substrate":"EKS Auto","builtInMetricsProvider":false,"xenon":"ON"},{"substrate":"DOKS","builtInMetricsProvider":false,"xenon":"ON"},{"substrate":"on-prem","builtInMetricsProvider":false,"xenon":"ON"}]'
# Pinned so ON renders never depend on the helm build's default Kubernetes version.
kube_version=1.31.0
stacks=("")
for l in $(jq -r '.[]' <<<"${landscapes}"); do stacks+=("--values chart/values.${l}.yaml"); done
full=(--values chart/values.serving.yaml --values chart/values.canary.yaml)
stacks+=("${full[*]}")
objects='["APIService/v1beta1.metrics.k8s.io","ClusterRole/system:metrics-server-aggregated-reader","ClusterRole/system:xenon-metrics","ClusterRoleBinding/system:xenon-metrics","ClusterRoleBinding/xenon-metrics:system:auth-delegator","Deployment/xenon-metrics","RoleBinding/xenon-metrics-auth-reader","Service/xenon-metrics","ServiceAccount/xenon-metrics"]'

render() {
  local chart="$1"
  shift
  helm template "${release}" "${chart}" --namespace "${namespace}" --kube-version "${kube_version}" "$@"
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

state_of() {
  local file="$1" deployments
  deployments="$(json "${file}" | jq '[.[] | select(.kind == "Deployment")] | length')"
  if [ "${deployments}" = 1 ]; then
    json "${file}" | need_jq 'an ON render is not exactly the metrics-server object set' --argjson want "${objects}" '(map(.kind + "/" + .metadata.name) | sort) == $want' || return 1
    echo ON
  elif [ "$(json "${file}" | jq length)" = 0 ]; then
    echo OFF
  else
    echo "❌ ${file} renders objects but no single metrics-server Deployment" >&2 && return 1
  fi
}

# Toggle map (chart/toggle-map.yaml) == goal baseline == overlays' real render == README matrix.
toggle_check() {
  local dir="$1" map overlays l state fact enabled
  map="$(yq -o=json '.' "${dir}/toggle-map.yaml")"
  need_jq 'toggle map landscapes are not exactly the eight defined landscapes' --argjson want "${landscapes}" '[.landscapes[].landscape] == $want' <<<"${map}" || return 1
  need_jq 'toggle map differs from the expected baseline (OFF lapras/ditto/rotom/absol, ON primordial/eevee/castform, serving per cluster)' --argjson want "${expected}" '(.landscapes | map({(.landscape): .xenon}) | add) == $want' <<<"${map}" || return 1
  need_jq 'a toggle map row is not ON exactly when no built-in provider is declared' '
    all(.landscapes[] | select(.landscape != "serving"); (.builtInMetricsProvider | type) == "boolean" and .xenon == (if .builtInMetricsProvider then "OFF" else "ON" end))' <<<"${map}" || return 1
  need_jq 'an enabled serving substrate declares a built-in provider (duplicate provider)' '
    (.servingSubstrates | length) > 0 and
    all(.servingSubstrates[]; (.builtInMetricsProvider | type) == "boolean" and .xenon == (if .builtInMetricsProvider then "OFF" else "ON" end))' <<<"${map}" || return 1
  need_jq 'toggle map serving substrates differ from the expected baseline (EKS classic, EKS Auto, DOKS, on-prem: no built-in provider, ON)' --argjson want "${substrates}" '.servingSubstrates == $want' <<<"${map}" || return 1
  overlays="$(for f in "${dir}"/values.*.yaml; do yq -r '.serviceTree.landscape // ""' "${f}"; done | rg -v '^$' | jq -Rsc 'split("\n") | map(select(. != "")) | sort')"
  [ "${overlays}" = "$(jq -c sort <<<"${landscapes}")" ] || { echo "❌ landscape overlays ${overlays} are not exactly the eight defined landscapes" >&2 && return 1; }
  for l in $(jq -r '.[]' <<<"${landscapes}"); do
    [ "$(yq -r '.serviceTree.landscape' "${dir}/values.${l}.yaml")" = "${l}" ] || { echo "❌ values.${l}.yaml is not the ${l} overlay" >&2 && return 1; }
    [ "$(jq -r --arg l "${l}" '.landscapes[] | select(.landscape == $l) | .overlay' <<<"${map}")" = "values.${l}.yaml" ] || { echo "❌ toggle map row ${l} does not name values.${l}.yaml" >&2 && return 1; }
    if [ "${l}" = serving ]; then
      while IFS=$'\t' read -r sub fact want; do
        enabled=false
        [ "${want}" = ON ] && enabled=true
        render "${dir}" --values "${dir}/values.serving.yaml" --set "builtInMetricsProvider=${fact}" --set "upstream.enabled=${enabled}" >"${tmp}/toggle.yaml" || return 1
        state="$(state_of "${tmp}/toggle.yaml")" || return 1
        [ "${state}" = "${want}" ] || { echo "❌ serving substrate ${sub} renders ${state}, expected ${want}" >&2 && return 1; }
      done < <(jq -r '.servingSubstrates[] | [.substrate, .builtInMetricsProvider, .xenon] | @tsv' <<<"${map}")
      [ "$(yq -r '.builtInMetricsProvider' "${dir}/values.serving.yaml")" = false ] || { echo "❌ values.serving.yaml does not declare the serving default builtInMetricsProvider=false" >&2 && return 1; }
      continue
    fi
    render "${dir}" --values "${dir}/values.${l}.yaml" >"${tmp}/toggle.yaml" || return 1
    state="$(state_of "${tmp}/toggle.yaml")" || return 1
    want="$(jq -r --arg l "${l}" '.[$l]' <<<"${expected}")"
    [ "${state}" = "${want}" ] || { echo "❌ ${l} renders xenon ${state}, expected ${want}" >&2 && return 1; }
    fact="$(yq -r '.builtInMetricsProvider' "${dir}/values.${l}.yaml")"
    [ "${fact}" = null ] && fact="$(yq -r '.builtInMetricsProvider' "${dir}/values.yaml")"
    [ "${fact}" = "$(jq -r --arg l "${l}" '.landscapes[] | select(.landscape == $l) | .builtInMetricsProvider' <<<"${map}")" ] ||
      { echo "❌ ${l} overlay declares builtInMetricsProvider=${fact}, the toggle map disagrees" >&2 && return 1; }
  done
  rows="$(rg -o '^\| ([a-z]+) \| [^|]+ \| [^|]+ \| (ON|OFF|per cluster) \|' -r '$1 $2' "${dir}/README.md" | jq -Rsc 'split("\n") | map(select(. != "") | split(" ") | {(.[0]): (if .[1] == "per" then "per-cluster" else .[1] end)}) | add')"
  [ "${rows}" = "$(jq -c . <<<"${expected}")" ] || { echo "❌ README needed/provided matrix rows ${rows} differ from the toggle map" >&2 && return 1; }
  subs="$(rg -o '^\| ([A-Za-z -]+) \| [^|]+ \| (ON|OFF) \|$' -r '$1|$2' "${dir}/README.md" | jq -Rsc 'split("\n") | map(select(. != "") | split("|") | {substrate: .[0], xenon: .[1]})')"
  [ "${subs}" = "$(jq -c '.servingSubstrates | map({substrate, xenon})' <<<"${map}")" ] || { echo "❌ README serving substrate rows ${subs} differ from the toggle map" >&2 && return 1; }
}

assert_lpsm() {
  local prefix="$1" file="$2"
  json "${file}" | need_jq 'metrics-server labels differ from the LPSM set' --arg p "${prefix}" '
    ({($p + "/platform"): "metrics", ($p + "/service"): "xenon", ($p + "/module"): "metrics", ($p + "/layer"): "1",
      ($p + "/landscape"): "serving", ($p + "/cluster"): "canary"}) as $want |
    def has_lpsm: . as $l | all($want | to_entries[]; $l[.key] == .value);
    length == 9 and all(.[]; .metadata.labels | has_lpsm) and
    all(.[] | select(.kind == "Deployment"); .spec.template.metadata.labels | has_lpsm)'
}

assert_reloader() {
  json "$1" | need_jq "the metrics-server Deployment does not carry reloader.stakater.com/auto=$2" --arg want "$2" '
    map(select(.kind == "Deployment")) as $d | ($d | length) == 1 and $d[0].metadata.annotations["reloader.stakater.com/auto"] == $want'
}

vap_stage() {
  kubeconform -strict -summary -schema-location default "$1"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "$1" >"$1.vap.yaml"
  json "$1.vap.yaml" | need_jq "the metrics-server workload is not in the VAP input ($2)" '(map(.kind + "/" + .metadata.name) | sort) == ["Deployment/xenon-metrics","Service/xenon-metrics"]' || return 1
  kyverno apply policies/vap --resource "$1.vap.yaml" --detailed-results --remove-color >"$1.vap.txt" 2>&1 ||
    { cat "$1.vap.txt" >&2 && echo "❌ the metrics-server workload or Service fails the VAP ($2)" >&2 && return 1; }
  rg -q '^pass: [1-9][0-9]*, fail: 0, warn: 0, error: 0' "$1.vap.txt" || { cat "$1.vap.txt" >&2 && echo "❌ the VAP stage evaluated nothing ($2)" >&2 && return 1; }
}

case "${mode}" in
schema)
  expect_red 'layer is not numeric' "serviceTree/layer.*does not match pattern|at '/serviceTree/layer'" helm lint chart --kube-version "${kube_version}" --namespace "${namespace}" --set-string serviceTree.layer=one
  expect_red 'dashed platform' "serviceTree/platform.*does not match pattern|at '/serviceTree/platform'" helm lint chart --kube-version "${kube_version}" --namespace metrics-server --set serviceTree.platform=metrics-server
  expect_red 'non-boolean provider fact' "builtInMetricsProvider" helm lint chart --kube-version "${kube_version}" --namespace "${namespace}" --set-string builtInMetricsProvider=maybe
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --kube-version "${kube_version}" --namespace "${namespace}" ${stack} >"${tmp}/schema.txt" 2>&1 ||
      { echo "❌ schema rejected the stack '${stack:-values.yaml}'" >&2 && cat "${tmp}/schema.txt" >&2 && exit 1; }
  done
  ;;
render)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >/dev/null
  done
  expect_refusal 'must equal release namespace' "${full[@]}" --namespace other
  ;;
toggle-map)
  toggle_check chart
  copy_tree "${tmp}/lapras-on"
  yq -i '.builtInMetricsProvider = false | .upstream.enabled = true | .upstream.commonLabels["atomi.cloud/landscape"] = "lapras" | .upstream.podLabels["atomi.cloud/landscape"] = "lapras"' "${tmp}/lapras-on/chart/values.lapras.yaml"
  expect_red 'lapras overlay flipped OFF -> ON' 'lapras renders xenon ON, expected OFF' toggle_check "${tmp}/lapras-on/chart"
  copy_tree "${tmp}/lapras-map"
  yq -i '(.landscapes[] | select(.landscape == "lapras")) |= (.xenon = "ON" | .builtInMetricsProvider = false)' "${tmp}/lapras-map/chart/toggle-map.yaml"
  expect_red 'toggle map lapras flipped OFF -> ON' 'differs from the expected baseline' toggle_check "${tmp}/lapras-map/chart"
  copy_tree "${tmp}/serving-dup"
  yq -i '.servingSubstrates += [{"substrate": "k3s", "builtInMetricsProvider": true, "xenon": "ON"}]' "${tmp}/serving-dup/chart/toggle-map.yaml"
  expect_red 'an enabled serving substrate with a built-in provider' 'enabled serving substrate declares a built-in provider' toggle_check "${tmp}/serving-dup/chart"
  copy_tree "${tmp}/serving-drift"
  yq -i '(.servingSubstrates[] | select(.substrate == "DOKS")) |= (.builtInMetricsProvider = true | .xenon = "OFF")' "${tmp}/serving-drift/chart/toggle-map.yaml"
  expect_red 'a serving substrate fact and toggle flipped together' 'serving substrates differ from the expected baseline' toggle_check "${tmp}/serving-drift/chart"
  expect_refusal 'duplicate provider' --values chart/values.serving.yaml --set builtInMetricsProvider=true
  expect_refusal 'duplicate provider' --values chart/values.lapras.yaml --set upstream.enabled=true
  expect_refusal 'missing provider' --values chart/values.eevee.yaml --set upstream.enabled=false
  copy_tree "${tmp}/onprem"
  printf 'serviceTree:\n  landscape: onprem\n' >"${tmp}/onprem/chart/values.onprem.yaml"
  expect_red 'an extra onprem landscape overlay' 'landscape overlays .* are not exactly the eight' toggle_check "${tmp}/onprem/chart"
  copy_tree "${tmp}/onprem-map"
  yq -i '.landscapes += [{"landscape": "onprem", "overlay": "values.onprem.yaml", "builtInMetricsProvider": false, "xenon": "ON"}]' "${tmp}/onprem-map/chart/toggle-map.yaml"
  expect_red 'an extra onprem toggle map key' 'not exactly the eight defined landscapes' toggle_check "${tmp}/onprem-map/chart"
  copy_tree "${tmp}/missing"
  yq -i 'del(.landscapes[] | select(.landscape == "castform"))' "${tmp}/missing/chart/toggle-map.yaml"
  expect_red 'a missing castform toggle map key' 'not exactly the eight defined landscapes' toggle_check "${tmp}/missing/chart"
  copy_tree "${tmp}/readme"
  sed -i 's/^| rotom \(.*\) | OFF |/| rotom \1 | ON |/' "${tmp}/readme/chart/README.md"
  expect_red 'README matrix row drift' 'README needed/provided matrix rows' toggle_check "${tmp}/readme/chart"
  copy_tree "${tmp}/readme-sub"
  sed -i '/^| DOKS |/d' "${tmp}/readme-sub/chart/README.md"
  expect_red 'README serving substrate row missing' 'README serving substrate rows' toggle_check "${tmp}/readme-sub/chart"
  ;;
kube-floor)
  render chart "${full[@]}" --kube-version 1.31.0 >/dev/null
  expect_refusal 'needs Kubernetes 1.31\+' "${full[@]}" --kube-version 1.30.0
  for l in lapras ditto rotom absol; do
    [ "$(render chart --values "chart/values.${l}.yaml" --kube-version 1.30.0 | yq eval-all -o=json '.' | jq -s 'map(select(.kind != null)) | length')" = 0 ] ||
      { echo "❌ OFF landscape ${l} does not install cleanly on Kubernetes 1.30" >&2 && exit 1; }
  done
  ;;
lpsm-labels)
  render chart "${full[@]}" >"${tmp}/lpsm.yaml"
  assert_lpsm atomi.cloud "${tmp}/lpsm.yaml"
  expect_refusal 'upstream.commonLabels must equal' "${full[@]}" --set labelPrefix=example.dev
  expect_refusal 'upstream.commonLabels must equal' "${full[@]}" --set serviceTree.cluster=other
  expect_refusal 'upstream.podLabels must equal' "${full[@]}" --set-string 'upstream.podLabels.atomi\.cloud/cluster=other'
  copy_tree "${tmp}/nolabels"
  yq -i 'del(.upstream.commonLabels) | del(.upstream.podLabels)' "${tmp}/nolabels/chart/values.yaml" "${tmp}/nolabels/chart/values.serving.yaml" "${tmp}/nolabels/chart/values.canary.yaml"
  sed -i '/include "xenon.validateUpstreamLabels"/d' "${tmp}/nolabels/chart/templates/validate.yaml"
  render "${tmp}/nolabels/chart" "${full[@]}" >"${tmp}/nolabels.yaml"
  expect_red 'LPSM labels dropped' 'labels differ from the LPSM set' assert_lpsm atomi.cloud "${tmp}/nolabels.yaml"
  ;;
reloader)
  for stack in "--values chart/values.primordial.yaml" "${full[*]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/reloader.yaml"
    assert_reloader "${tmp}/reloader.yaml" true
  done
  render chart "${full[@]}" --set-string 'upstream.deploymentAnnotations.reloader\.stakater\.com/auto=false' >"${tmp}/optout.yaml"
  assert_reloader "${tmp}/optout.yaml" false
  copy_tree "${tmp}/noreloader"
  yq -i 'del(.upstream.deploymentAnnotations)' "${tmp}/noreloader/chart/values.yaml"
  render "${tmp}/noreloader/chart" "${full[@]}" >"${tmp}/noreloader.yaml"
  expect_red 'Reloader annotation dropped' 'reloader.stakater.com/auto=true' assert_reloader "${tmp}/noreloader.yaml" true
  ;;
rendered-manifests)
  index=0
  for stack in "" "--values chart/values.primordial.yaml" "--values chart/values.eevee.yaml" "--values chart/values.castform.yaml" "${full[*]}"; do
    index=$((index + 1))
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/rendered-${index}.yaml"
    vap_stage "${tmp}/rendered-${index}.yaml" "stack ${stack:-values.yaml}"
  done
  render chart "${full[@]}" --set upstream.image.tag=latest >"${tmp}/latest.yaml"
  expect_red 'a :latest metrics-server image' 'explicit non-latest tag' vap_stage "${tmp}/latest.yaml" latest
  ;;
pin)
  dep="$(yq -o=json '.dependencies[] | select(.name == "metrics-server")' chart/Chart.yaml)"
  version="$(jq -r .version <<<"${dep}")"
  [[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ metrics-server chart ${version} is not an exact pin" >&2 && exit 1; }
  [ "$(jq -r .alias <<<"${dep}")" = upstream ] || { echo "❌ metrics-server is not aliased upstream" >&2 && exit 1; }
  [ "$(jq -r .condition <<<"${dep}")" = upstream.enabled ] || { echo "❌ metrics-server is not gated by upstream.enabled" >&2 && exit 1; }
  [ "$(yq -r '.dependencies[] | select(.name == "metrics-server") | .version' chart/Chart.lock)" = "${version}" ] || { echo "❌ Chart.lock differs from Chart.yaml" >&2 && exit 1; }
  [ "$(git ls-files 'chart/charts/*.tgz')" = "chart/charts/metrics-server-${version}.tgz" ] || { echo "❌ the vendored archive is not metrics-server-${version}.tgz" >&2 && exit 1; }
  app="$(tar -xzOf "chart/charts/metrics-server-${version}.tgz" metrics-server/Chart.yaml | yq -r .appVersion)"
  [ "$(yq -r .appVersion chart/Chart.yaml)" = "${app}" ] || { echo "❌ appVersion differs from the vendored chart's app ${app}" >&2 && exit 1; }
  image="$(render chart "${full[@]}" | yq -N eval-all 'select(.kind == "Deployment") | .spec.template.spec.containers[].image')"
  [ "${image}" = "registry.k8s.io/metrics-server/metrics-server:v${app}" ] || { echo "❌ image ${image} is not registry.k8s.io/metrics-server/metrics-server:v${app}" >&2 && exit 1; }
  ;;
task-surface)
  task --list-all --json | jq -e '[.tasks[].name] as $names | ["debug", "template", "install", "remove"] | all(("serving:canary:" + .) | IN($names[]))' >/dev/null ||
    { echo "❌ serving:canary is missing a debug/template/install/remove task" >&2 && exit 1; }
  task --silent serving:canary:template >"${tmp}/task-template.yaml"
  rg -q '^kind: Deployment$' "${tmp}/task-template.yaml" || { echo "❌ serving:canary:template rendered no Deployment" >&2 && exit 1; }
  rg -q 'atomi.cloud/cluster: canary' "${tmp}/task-template.yaml" || { echo "❌ serving:canary:template did not stack values.canary.yaml" >&2 && exit 1; }
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/xenon-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/xenon-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'a tag that differs from Chart.yaml' 'does not match tag 9.9.9' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh
  ;;
presence)
  test -s docs/developer/xenon-baseline.md
  test -s .claude/skills/xenon/SKILL.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ xenon ${mode} validation passed"
