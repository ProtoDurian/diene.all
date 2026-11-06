#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs are single-quoted on purpose
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-sulfur}"
namespace="${NAMESPACE:-certs}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

stacks=("" "--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")
full=(--values chart/values.example.yaml --values chart/values.lapras.yaml)
workloads='["Deployment/sulfur-cert-manager","Deployment/sulfur-cert-manager-cainjector","Deployment/sulfur-cert-manager-webhook"]'
vap_input='["Deployment/sulfur-cert-manager","Deployment/sulfur-cert-manager-cainjector","Deployment/sulfur-cert-manager-webhook","Job/sulfur-cert-manager-startupapicheck"]'
crds='["certificaterequests.cert-manager.io","certificates.cert-manager.io","challenges.acme.cert-manager.io","clusterissuers.cert-manager.io","issuers.cert-manager.io","orders.acme.cert-manager.io"]'

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

assert_gateway_api() {
  json "$1" | jq -r '.[] | select(.kind == "ConfigMap" and .metadata.name == "sulfur-cert-manager") | .data["config.yaml"] // ""' | yq -e '.enableGatewayAPI == true' >/dev/null 2>&1 ||
    { echo "❌ the cert-manager controller config does not set enableGatewayAPI: true" >&2 && return 1; }
}

assert_no_dead_flag() {
  local hits
  hits="$(rg -n 'ExperimentalGatewayAPISupport' "$1" || true)"
  [ -z "${hits}" ] || { echo "❌ the dead ExperimentalGatewayAPISupport feature gate is set: ${hits}" >&2 && return 1; }
}

assert_no_issuers() {
  local hits
  hits="$(rg -n --glob '!charts/**' '^\s*kind:\s*(Cluster)?Issuer\b' "$1" || true)"
  [ -z "${hits}" ] || { echo "❌ the wrapper authors an Issuer/ClusterIssuer (zinc owns the issuer set): ${hits}" >&2 && return 1; }
}

assert_no_issuer_render() {
  json "$1" | need_jq 'the render contains an Issuer/ClusterIssuer (zinc owns the issuer set)' '
    all(.[]; (.kind == "Issuer" or .kind == "ClusterIssuer") | not)'
}

assert_crds() {
  json "$1" | need_jq 'the rendered cert-manager CRD lifecycle set differs from the expected six' --argjson want "${crds}" '
    (map(select(.kind == "CustomResourceDefinition") | .metadata.name) | sort) == $want' || return 1
  json "$1" | need_jq 'a cert-manager CRD is a hook, not a normal template' '
    all(.[] | select(.kind == "CustomResourceDefinition"); (.metadata.annotations // {}) | has("helm.sh/hook") | not)' || return 1
  json "$1" | need_jq 'a cert-manager CRD is not kept on uninstall' '
    all(.[] | select(.kind == "CustomResourceDefinition"); .metadata.annotations["helm.sh/resource-policy"] == "keep")' || return 1
  json "$1" | need_jq 'a cert-manager CRD is not from the pinned chart version' --arg v "$2" '
    all(.[] | select(.kind == "CustomResourceDefinition"); .metadata.labels["app.kubernetes.io/version"] == $v)' || return 1
  # ArgoCD client-side apply stores the object in a 262144-byte annotation; past that the CRD needs ServerSideApply.
  json "$1" | need_jq 'a cert-manager CRD exceeds the client-side apply annotation limit without ServerSideApply=true' '
    all(.[] | select(.kind == "CustomResourceDefinition");
      (tojson | utf8bytelength) < 262144 or .metadata.annotations["argocd.argoproj.io/sync-options"] == "ServerSideApply=true")'
}

assert_lpsm() {
  local prefix="$1" file="$2"
  json "${file}" | need_jq 'cert-manager workload labels differ from the LPSM set' --arg p "${prefix}" --argjson w "${vap_input}" '
    ({($p + "/platform"): "certs", ($p + "/service"): "sulfur", ($p + "/module"): "certs", ($p + "/layer"): "1",
      ($p + "/landscape"): "example", ($p + "/cluster"): "lapras"}) as $want |
    def has_lpsm: . as $l | all($want | to_entries[]; $l[.key] == .value);
    (map(select(.kind == "Deployment" or .kind == "Job") | .kind + "/" + .metadata.name) | sort) == $w and
    all(.[] | select(.kind == "Deployment" or .kind == "Job"); (.metadata.labels | has_lpsm) and (.spec.template.metadata.labels | has_lpsm)) and
    all(.[] | select(.kind == "Service" or .kind == "CustomResourceDefinition" or .kind == "ConfigMap"); .metadata.labels | has_lpsm)'
}

assert_reloader() {
  json "$1" | need_jq "cert-manager workloads do not carry reloader.stakater.com/auto=$2" --arg want "$2" --argjson w "${workloads}" '
    map(select(.kind == "Deployment")) as $d | ($d | map(.kind + "/" + .metadata.name) | sort) == $w and
    all($d[]; .metadata.annotations["reloader.stakater.com/auto"] == $want)'
}

vap_stage() {
  # The cert-manager CRDs are upstream bytes; kubeconform ships no schema for the CRD kind.
  kubeconform -strict -summary -skip CustomResourceDefinition -schema-location default "$1"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "$1" >"$1.vap.yaml"
  json "$1.vap.yaml" | need_jq "the cert-manager workloads are not all in the VAP input ($2)" --argjson w "${vap_input}" '(map(select(.kind == "Deployment" or .kind == "Job") | .kind + "/" + .metadata.name) | sort) == $w' || return 1
  kyverno apply policies/vap --resource "$1.vap.yaml" --detailed-results --remove-color >"$1.vap.txt" 2>&1 ||
    { cat "$1.vap.txt" >&2 && echo "❌ a cert-manager workload or Service fails the VAP ($2)" >&2 && return 1; }
  rg -q '^pass: [1-9][0-9]*, fail: 0, warn: 0, error: 0' "$1.vap.txt" || { cat "$1.vap.txt" >&2 && echo "❌ the VAP stage evaluated nothing ($2)" >&2 && return 1; }
}

seq_fixture() {
  local dir="$1"
  shift
  mkdir -p "${dir}/chart"
  git -C "${dir}" init --quiet
  for version in "$@"; do
    case "${version}" in
    none) printf 'dependencies: []\n' >"${dir}/chart/Chart.yaml" ;;
    broken) printf 'dependencies: [\n' >"${dir}/chart/Chart.yaml" ;;
    *) printf 'dependencies:\n  - name: cert-manager\n    version: %s\n' "${version}" >"${dir}/chart/Chart.yaml" ;;
    esac
    git -C "${dir}" add chart/Chart.yaml
    git -C "${dir}" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --quiet --no-verify -m "pin ${version}"
  done
}

seq_gate() { (cd "$1" && env -u GITHUB_EVENT_PATH SEQ_BASE="$(git rev-list --max-parents=0 HEAD)" bash "${OLDPWD}/scripts/validate/check-sequential-minor.sh"); }

case "${mode}" in
schema)
  expect_red 'layer is not numeric' "serviceTree/layer.*does not match pattern|at '/serviceTree/layer'" helm lint chart --namespace "${namespace}" --set-string serviceTree.layer=one
  expect_red 'dashed platform' "serviceTree/platform.*does not match pattern|at '/serviceTree/platform'" helm lint chart --namespace cert-manager --set serviceTree.platform=cert-manager
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack} >"${tmp}/schema.txt" 2>&1 ||
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
gateway-api)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/gw.yaml"
    assert_gateway_api "${tmp}/gw.yaml"
  done
  render chart "${full[@]}" --set upstream.config.enableGatewayAPI=false >"${tmp}/gw-off.yaml"
  expect_red 'enableGatewayAPI off' 'does not set enableGatewayAPI: true' assert_gateway_api "${tmp}/gw-off.yaml"
  copy_tree "${tmp}/noconfig"
  yq -i 'del(.upstream.config)' "${tmp}/noconfig/chart/values.yaml"
  render "${tmp}/noconfig/chart" "${full[@]}" >"${tmp}/noconfig.yaml"
  expect_red 'controller config removed' 'does not set enableGatewayAPI: true' assert_gateway_api "${tmp}/noconfig.yaml"
  ;;
dead-flag)
  assert_no_dead_flag chart/values.yaml
  for f in chart/values.*.yaml; do assert_no_dead_flag "${f}"; done
  render chart "${full[@]}" >"${tmp}/flags.yaml"
  assert_no_dead_flag "${tmp}/flags.yaml"
  copy_tree "${tmp}/dead"
  yq -i '.upstream.featureGates = "ExperimentalGatewayAPISupport=true"' "${tmp}/dead/chart/values.yaml"
  expect_red 'the dead flag in values' 'dead ExperimentalGatewayAPISupport feature gate is set' assert_no_dead_flag "${tmp}/dead/chart/values.yaml"
  render "${tmp}/dead/chart" "${full[@]}" >"${tmp}/dead.yaml"
  expect_red 'the dead flag in the render' 'dead ExperimentalGatewayAPISupport feature gate is set' assert_no_dead_flag "${tmp}/dead.yaml"
  ;;
issuer-boundary)
  assert_no_issuers chart
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/issuers.yaml"
    assert_no_issuer_render "${tmp}/issuers.yaml"
  done
  for kind in ClusterIssuer Issuer; do
    copy_tree "${tmp}/${kind}"
    printf 'apiVersion: cert-manager.io/v1\nkind: %s\nmetadata:\n  name: sulfur-selfsigned\nspec:\n  selfSigned: {}\n' "${kind}" >"${tmp}/${kind}/chart/templates/issuer.yaml"
    expect_red "a wrapper ${kind} template" 'authors an Issuer/ClusterIssuer' assert_no_issuers "${tmp}/${kind}/chart"
    render "${tmp}/${kind}/chart" "${full[@]}" >"${tmp}/${kind}.yaml"
    expect_red "a rendered wrapper ${kind}" 'render contains an Issuer/ClusterIssuer' assert_no_issuer_render "${tmp}/${kind}.yaml"
  done
  ;;
crd-lifecycle)
  version="$(yq -r .appVersion chart/Chart.yaml)"
  tar -tzf chart/charts/cert-manager-*.tgz | rg -q '^cert-manager/crds/' &&
    { echo "❌ the vendored chart ships install-only crds/" >&2 && exit 1; }
  [ ! -e chart/crds ] || { echo "❌ the wrapper ships its own crds/ (CRDs come only from the pinned dependency)" >&2 && exit 1; }
  ! rg -q --glob '!charts/**' '^\s*kind:\s*CustomResourceDefinition\b' chart ||
    { echo "❌ the wrapper authors a CRD (CRDs come only from the pinned dependency)" >&2 && exit 1; }
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/crds.yaml"
    assert_crds "${tmp}/crds.yaml" "${version}"
  done
  render chart "${full[@]}" --set upstream.crds.enabled=false >"${tmp}/no-crds.yaml"
  expect_red 'crds.enabled off' 'CRD lifecycle set differs' assert_crds "${tmp}/no-crds.yaml" "${version}"
  render chart "${full[@]}" --set upstream.crds.keep=false >"${tmp}/no-keep.yaml"
  expect_red 'crds.keep off' 'not kept on uninstall' assert_crds "${tmp}/no-keep.yaml" "${version}"
  render chart "${full[@]}" >"${tmp}/big.yaml"
  head -c 262144 /dev/zero | tr '\0' x >"${tmp}/pad.txt"
  yq -i '(select(.kind == "CustomResourceDefinition" and .metadata.name == "certificates.cert-manager.io") | .metadata.annotations.padding) = load_str("'"${tmp}/pad.txt"'")' "${tmp}/big.yaml"
  expect_red 'a CRD past the annotation limit without SSA' 'exceeds the client-side apply annotation limit' assert_crds "${tmp}/big.yaml" "${version}"
  ;;
sequential-minor)
  bash ./scripts/validate/check-sequential-minor.sh
  seq_fixture "${tmp}/seq-ok" v1.12.0 v1.14.0 v1.15.5 v1.16.5 none v1.16.6 v1.17.4
  seq_gate "${tmp}/seq-ok" >/dev/null
  seq_fixture "${tmp}/seq-skip" v1.20.3 v1.22.0
  expect_red 'a version-skip bump v1.20.3 -> v1.22.0' 'version-skip v1.20.3 -> v1.22.0 skips a cert-manager minor' seq_gate "${tmp}/seq-skip"
  seq_fixture "${tmp}/seq-skip-mid" v1.20.3 v1.21.0 v1.23.1 v1.23.2
  expect_red 'a skip hidden under a later commit' 'version-skip v1.21.0 -> v1.23.1' seq_gate "${tmp}/seq-skip-mid"
  seq_fixture "${tmp}/seq-gap" v1.20.3 none v1.22.0
  expect_red 'a skip across a commit with no cert-manager pin' 'version-skip v1.20.3 -> v1.22.0' seq_gate "${tmp}/seq-gap"
  seq_fixture "${tmp}/seq-broken" v1.20.3 broken v1.22.0
  expect_red 'a skip across a commit with an unreadable Chart.yaml' 'version-skip v1.20.3 -> v1.22.0' seq_gate "${tmp}/seq-broken"
  seq_fixture "${tmp}/seq-pre" v1.14.2 v1.22.0
  expect_red 'a jump from below v1.15 past v1.15' 'version-skip v1.14.2 -> v1.22.0' seq_gate "${tmp}/seq-pre"
  seq_fixture "${tmp}/seq-down" v1.20.3 v1.19.4
  expect_red 'a downgrade' 'downgrade v1.20.3 -> v1.19.4' seq_gate "${tmp}/seq-down"
  seq_fixture "${tmp}/seq-major" v1.20.3 v2.0.0
  expect_red 'a major change' 'major change v1.20.3 -> v2.0.0' seq_gate "${tmp}/seq-major"
  ;;
lpsm-labels)
  render chart "${full[@]}" >"${tmp}/lpsm.yaml"
  assert_lpsm atomi.cloud "${tmp}/lpsm.yaml"
  expect_refusal 'upstream.global.commonLabels must equal' "${full[@]}" --set labelPrefix=example.dev
  expect_refusal 'upstream.global.commonLabels must equal' "${full[@]}" --set serviceTree.cluster=other
  expect_refusal 'upstream.global.commonLabels must equal' --values chart/values.example.yaml --set serviceTree.cluster=lapras
  copy_tree "${tmp}/nolabels"
  yq -i 'del(.upstream.global.commonLabels)' "${tmp}/nolabels/chart/values.yaml" "${tmp}/nolabels/chart/values.example.yaml" "${tmp}/nolabels/chart/values.lapras.yaml"
  sed -i '/include "sulfur.validateUpstreamLabels"/d' "${tmp}/nolabels/chart/templates/validate.yaml"
  render "${tmp}/nolabels/chart" "${full[@]}" >"${tmp}/nolabels.yaml"
  expect_red 'LPSM labels dropped' 'labels differ from the LPSM set' assert_lpsm atomi.cloud "${tmp}/nolabels.yaml"
  ;;
reloader)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/reloader.yaml"
    assert_reloader "${tmp}/reloader.yaml" true
  done
  off=()
  for path in upstream upstream.webhook upstream.cainjector; do off+=(--set-string "${path}.deploymentAnnotations.reloader\.stakater\.com/auto=false"); done
  render chart "${full[@]}" "${off[@]}" >"${tmp}/optout.yaml"
  assert_reloader "${tmp}/optout.yaml" false
  copy_tree "${tmp}/noreloader"
  yq -i 'del(.upstream.webhook.deploymentAnnotations)' "${tmp}/noreloader/chart/values.yaml"
  render "${tmp}/noreloader/chart" "${full[@]}" >"${tmp}/noreloader.yaml"
  expect_red 'Reloader annotation dropped on the webhook' 'reloader.stakater.com/auto=true' assert_reloader "${tmp}/noreloader.yaml" true
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
  dep="$(yq -o=json '.dependencies[] | select(.name == "cert-manager")' chart/Chart.yaml)"
  version="$(jq -r .version <<<"${dep}")"
  [[ ${version} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ cert-manager ${version} is not an exact pin" >&2 && exit 1; }
  [ "$(jq -r .alias <<<"${dep}")" = upstream ] || { echo "❌ cert-manager is not aliased upstream" >&2 && exit 1; }
  [ "$(yq -r '.dependencies[] | select(.name == "cert-manager") | .version' chart/Chart.lock)" = "${version}" ] || { echo "❌ Chart.lock differs from Chart.yaml" >&2 && exit 1; }
  [ "$(git ls-files 'chart/charts/*.tgz')" = "chart/charts/cert-manager-${version}.tgz" ] || { echo "❌ the vendored archive is not cert-manager-${version}.tgz" >&2 && exit 1; }
  [ "$(yq -r .appVersion chart/Chart.yaml)" = "${version}" ] || { echo "❌ appVersion differs from the cert-manager version" >&2 && exit 1; }
  [ "$(tar -xzOf "chart/charts/cert-manager-${version}.tgz" cert-manager/Chart.yaml | yq -r .appVersion)" = "${version}" ] || { echo "❌ the vendored chart does not default to image ${version}" >&2 && exit 1; }
  render chart "${full[@]}" | yq -N eval-all 'select(.kind == "Deployment" or .kind == "Job") | .spec.template.spec.containers[].image' | sort -u >"${tmp}/images.txt"
  printf 'quay.io/jetstack/cert-manager-%s:%s\n' cainjector "${version}" controller "${version}" startupapicheck "${version}" webhook "${version}" >"${tmp}/want.txt"
  diff -u "${tmp}/want.txt" "${tmp}/images.txt" >&2 || { echo "❌ cert-manager images are not quay.io/jetstack/cert-manager-*:${version}" >&2 && exit 1; }
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/sulfur-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/sulfur-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'a tag that differs from Chart.yaml' 'does not match tag 9.9.9' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh
  ;;
presence)
  test -s docs/developer/sulfur-baseline.md
  test -s .claude/skills/sulfur/SKILL.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ sulfur ${mode} validation passed"
