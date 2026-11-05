#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs are single-quoted on purpose
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-cobalt}"
namespace="${NAMESPACE:-secrets}"
crd_list="scripts/validate/cobalt-expected-crds.txt"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

stacks=("--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")
lint_stacks=("" "${stacks[@]}")
full=(--values chart/values.example.yaml --values chart/values.lapras.yaml)
workloads='["Deployment/cobalt-eso","Deployment/cobalt-eso-cert-controller","Deployment/cobalt-eso-webhook"]'

render() {
  local chart="$1"
  shift
  helm template "${release}" "${chart}" --namespace "${namespace}" "$@"
}

json() { yq eval-all -o=json '.' "$1" | jq -s 'map(select(.kind != null))'; }

# need_jq <reason> <jq args...>: a failed check names its reason so negative fixtures can match it.
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

copy_tree() {
  mkdir -p "$1"
  cp -a chart schemas "$1/"
}

assert_store_auth() {
  json "$1" | need_jq 'the ClusterSecretStore does not authenticate from the SoS bootstrap Secret reference alone' '
    map(select(.kind == "ClusterSecretStore")) as $s | ($s | length) == 1 and
    $s[0].spec.provider.infisical.auth == {"universalAuthCredentials": {
      "clientId": {"name": "cobalt-sos-bootstrap", "namespace": "secrets", "key": "clientId"},
      "clientSecret": {"name": "cobalt-sos-bootstrap", "namespace": "secrets", "key": "clientSecret"}}}' || return 1
  json "$1" | need_jq 'the chart renders a credential Secret' '
    all(.[] | select(.kind == "Secret"); .metadata.name == "cobalt-eso-webhook" and .data == null and .stringData == null)'
}

assert_no_literal_secrets() {
  yq eval-all -o=json '.' "$1"/values*.yaml | need_jq 'a literal credential is in a values file' -s '
    def credential_key: test("^(password|passphrase|token|apikey|api[_-]key|clientid|client[_-]id|clientsecret|client[_-]secret|secretkey|accesskey|privatekey|credentials?|value|authorization)$"; "i");
    [.[] | .. | objects | to_entries[] | select((.key | credential_key) and (.value | type) == "string" and .value != "")] +
    [.[] | .. | strings | select(test("://[^/@\\s]+:[^/@\\s]+@"))] | length == 0'
}

assert_store_scope() {
  json "$1" | need_jq "the store is not scoped to SoS project + landscape $2 only" --arg l "$2" '
    map(select(.kind == "ClusterSecretStore")) as $s | ($s | length) == 1 and
    $s[0].metadata.name == "infisical" and
    $s[0].spec.provider.infisical.hostAPI == "https://secrets.atomi.cloud" and
    $s[0].spec.provider.infisical.secretsScope == {"projectSlug": "sos", "environmentSlug": $l, "secretsPath": "/", "recursive": true}'
}

assert_crds() {
  local actual="${tmp}/crds-actual.txt"
  json "$1" | jq -r '.[] | select(.kind == "CustomResourceDefinition") | .metadata.name' | LC_ALL=C sort -u >"${actual}"
  diff -u "${crd_list}" "${actual}" >&2 || { echo "❌ rendered ESO CRD lifecycle set differs from ${crd_list}" >&2 && return 1; }
  json "$1" | need_jq 'an ESO CRD is a hook, not a normal template' '
    all(.[] | select(.kind == "CustomResourceDefinition"); (.metadata.annotations // {}) | has("helm.sh/hook") | not)'
}

assert_v1_only() {
  local hits
  hits="$(rg -n --glob '*.{yaml,yml,tpl,json}' --glob '!chart/charts/**' 'external-secrets\.io/v1beta1' "$1/chart" "$1/schemas" || true)"
  [ -z "${hits}" ] || { echo "❌ a committed manifest references external-secrets.io/v1beta1: ${hits}" >&2 && return 1; }
  hits="$(rg -n --glob '*.{yaml,yml,tpl}' --glob '!chart/charts/**' '^\s*kind:\s*(Cluster)?PushSecret\b' "$1/chart" || true)"
  [ -z "${hits}" ] || { echo "❌ a PushSecret is authored (cobalt is pull-only): ${hits}" >&2 && return 1; }
}

assert_v1_render() {
  json "$1" | need_jq 'the render authors or serves external-secrets.io/v1beta1' '
    all(.[] | select(.kind == "ClusterSecretStore" or .kind == "SecretStore" or .kind == "ExternalSecret"); .apiVersion == "external-secrets.io/v1") and
    all(.[] | select(.kind == "CustomResourceDefinition") | .spec.versions[] | select(.name == "v1beta1"); .served == false)'
}

assert_lpsm() {
  local prefix="$1" file="$2"
  json "${file}" | need_jq 'store or ESO workload labels differ from the LPSM set' --arg p "${prefix}" --argjson w "${workloads}" '
    ({($p + "/platform"): "secrets", ($p + "/service"): "cobalt", ($p + "/module"): "sos", ($p + "/layer"): "1",
      ($p + "/landscape"): "example", ($p + "/cluster"): "lapras"}) as $want |
    def has_lpsm: . as $l | all($want | to_entries[]; $l[.key] == .value);
    (map(select(.kind == "Deployment") | .kind + "/" + .metadata.name) | sort) == $w and
    all(.[] | select(.kind == "Deployment"); (.metadata.labels | has_lpsm) and (.spec.template.metadata.labels | has_lpsm)) and
    all(.[] | select(.kind == "Service"); .metadata.labels | has_lpsm) and
    (map(select(.kind == "ClusterSecretStore")) | length == 1 and all(.[]; (.metadata.labels | has_lpsm) and (.metadata.annotations | has_lpsm)))'
}

assert_reloader() {
  json "$1" | need_jq "ESO workloads do not carry reloader.stakater.com/auto=$2" --arg want "$2" --argjson w "${workloads}" '
    map(select(.kind == "Deployment")) as $d | ($d | map(.kind + "/" + .metadata.name) | sort) == $w and
    all($d[]; .spec.template.metadata.annotations["reloader.stakater.com/auto"] == $want)'
}

# The inherited rendered-manifest stage: template -> kubeconform -> kyverno VAP.
vap_stage() {
  mkdir -p "${tmp}/schemas"
  cp schemas/*.json "${tmp}/schemas/"
  yq eval-all -o=json 'select(.kind == "CustomResourceDefinition" and .metadata.name == "clustersecretstores.external-secrets.io") | .spec.versions[] | select(.name == "v1") | .schema.openAPIV3Schema' "$1" >"${tmp}/schemas/clustersecretstore.json"
  [ -s "${tmp}/schemas/clustersecretstore.json" ] || { echo "❌ the ClusterSecretStore CRD v1 schema did not render" >&2 && return 1; }
  # The ESO CRDs are upstream bytes; kubeconform ships no schema for the CRD kind.
  kubeconform -strict -summary -skip CustomResourceDefinition -schema-location default -schema-location "${tmp}/schemas/{{ .ResourceKind }}.json" "$1"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "$1" >"$1.vap.yaml"
  json "$1.vap.yaml" | need_jq "the ESO workloads are not all in the VAP input ($2)" --argjson w "${workloads}" '(map(select(.kind == "Deployment") | .kind + "/" + .metadata.name) | sort) == $w' || return 1
  kyverno apply policies/vap --resource "$1.vap.yaml" --detailed-results --remove-color >"$1.vap.txt" 2>&1 ||
    { cat "$1.vap.txt" >&2 && echo "❌ an ESO workload or Service fails the VAP ($2)" >&2 && return 1; }
  rg -q '^pass: [1-9][0-9]*, fail: 0, warn: 0, error: 0' "$1.vap.txt" || { cat "$1.vap.txt" >&2 && echo "❌ the VAP stage evaluated nothing ($2)" >&2 && return 1; }
}

case "${mode}" in
schema)
  for stack in "${lint_stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack} >"${tmp}/schema.txt" 2>&1 ||
      { echo "❌ schema rejected the stack '${stack:-values.yaml}'" >&2 && cat "${tmp}/schema.txt" >&2 && exit 1; }
  done
  expect_red 'layer is not numeric' "serviceTree/layer.*does not match pattern|at '/serviceTree/layer'" helm lint chart --namespace "${namespace}" --set-string serviceTree.layer=one
  expect_red 'plain-http Infisical host' "store/hostAPI.*does not match pattern|at '/store/hostAPI'" helm lint chart --namespace "${namespace}" --set store.hostAPI=http://secrets.atomi.cloud
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  for stack in "${lint_stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack}
  done
  ;;
render)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >/dev/null
  done
  expect_refusal 'serviceTree.landscape is required'
  ;;
store-auth)
  assert_no_literal_secrets chart
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/auth.yaml"
    assert_store_auth "${tmp}/auth.yaml"
  done
  copy_tree "${tmp}/literal"
  yq -i '.store.credentials.clientSecret = "fixture-literal"' "${tmp}/literal/chart/values.yaml"
  expect_red 'a literal client secret in values' 'literal credential' assert_no_literal_secrets "${tmp}/literal/chart"
  expect_red 'a literal client secret through the schema' "additional properties 'clientSecret' not allowed|clientSecret" render "${tmp}/literal/chart" "${full[@]}"
  copy_tree "${tmp}/inline"
  cat >"${tmp}/inline/chart/templates/bootstrap.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: cobalt-sos-bootstrap
stringData:
  clientId: fixture-id
  clientSecret: fixture-secret
EOF
  render "${tmp}/inline/chart" "${full[@]}" >"${tmp}/inline.yaml"
  expect_red 'an inlined bootstrap credential Secret' 'renders a credential Secret' assert_store_auth "${tmp}/inline.yaml"
  render chart "${full[@]}" --set store.credentials.secretName=other-secret >"${tmp}/other.yaml"
  expect_red 'the store reads another Secret' 'bootstrap Secret reference alone' assert_store_auth "${tmp}/other.yaml"
  ;;
store-scope)
  render chart --values chart/values.example.yaml >"${tmp}/scope.yaml"
  assert_store_scope "${tmp}/scope.yaml" example
  render chart "${full[@]}" --set serviceTree.landscape=serving --set 'upstream.commonLabels.atomi\.cloud/landscape=serving' >"${tmp}/serving.yaml"
  assert_store_scope "${tmp}/serving.yaml" serving
  expect_refusal 'serviceTree.landscape is required'
  copy_tree "${tmp}/wide"
  sed -i 's#environmentSlug: {{ .Values.serviceTree.landscape | quote }}#environmentSlug: "serving"#' "${tmp}/wide/chart/templates/clustersecretstore.yaml"
  render "${tmp}/wide/chart" "${full[@]}" >"${tmp}/wide.yaml"
  expect_red 'store environment widened past the landscape' 'not scoped to SoS project \+ landscape example' assert_store_scope "${tmp}/wide.yaml" example
  render chart "${full[@]}" --set store.project=platform >"${tmp}/project.yaml"
  expect_red 'store bound to another project' 'not scoped to SoS project' assert_store_scope "${tmp}/project.yaml" example
  copy_tree "${tmp}/org"
  sed -i 's#^        secretsPath: /$#        secretsPath: /\n        organizationSlug: atomi#' "${tmp}/org/chart/templates/clustersecretstore.yaml"
  render "${tmp}/org/chart" "${full[@]}" >"${tmp}/org.yaml"
  expect_red 'an extra scope field' 'not scoped to SoS project' assert_store_scope "${tmp}/org.yaml" example
  ;;
crd-lifecycle)
  tar -tzf chart/charts/external-secrets-*.tgz | rg -q '^external-secrets/crds/' &&
    { echo "❌ the vendored chart ships install-only crds/" >&2 && exit 1; }
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/crds.yaml"
    assert_crds "${tmp}/crds.yaml"
  done
  render chart "${full[@]}" --set upstream.crds.createClusterSecretStore=false >"${tmp}/no-css.yaml"
  expect_red 'the ClusterSecretStore CRD removed' 'CRD lifecycle set differs' assert_crds "${tmp}/no-css.yaml"
  render chart "${full[@]}" --set upstream.installCRDs=false --set store.name=infisical >"${tmp}/no-crds.yaml"
  expect_red 'CRD installation disabled' 'CRD lifecycle set differs' assert_crds "${tmp}/no-crds.yaml"
  ;;
v1-only)
  assert_v1_only .
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/v1.yaml"
    assert_v1_render "${tmp}/v1.yaml"
  done
  copy_tree "${tmp}/beta"
  sed -i 's#^apiVersion: external-secrets.io/v1$#apiVersion: external-secrets.io/v1beta1#' "${tmp}/beta/chart/templates/clustersecretstore.yaml"
  expect_red 'a v1beta1 store manifest' 'references external-secrets.io/v1beta1' assert_v1_only "${tmp}/beta"
  render "${tmp}/beta/chart" "${full[@]}" >"${tmp}/beta.yaml"
  expect_red 'a v1beta1 store render' 'authors or serves external-secrets.io/v1beta1' assert_v1_render "${tmp}/beta.yaml"
  render chart "${full[@]}" --set upstream.crds.unsafeServeV1Beta1=true >"${tmp}/serve.yaml"
  expect_red 'v1beta1 served' 'authors or serves external-secrets.io/v1beta1' assert_v1_render "${tmp}/serve.yaml"
  copy_tree "${tmp}/push"
  printf 'apiVersion: external-secrets.io/v1alpha1\nkind: PushSecret\nmetadata:\n  name: push\n' >"${tmp}/push/chart/templates/push.yaml"
  expect_red 'a PushSecret' 'PushSecret is authored' assert_v1_only "${tmp}/push"
  ;;
lpsm-labels)
  render chart "${full[@]}" >"${tmp}/lpsm.yaml"
  assert_lpsm atomi.cloud "${tmp}/lpsm.yaml"
  expect_refusal 'upstream.commonLabels must equal' "${full[@]}" --set labelPrefix=example.dev
  expect_refusal 'upstream.commonLabels must equal' "${full[@]}" --set serviceTree.cluster=other
  expect_refusal 'must equal release namespace' "${full[@]}" --namespace other
  copy_tree "${tmp}/nolabels"
  sed -i '/include "cobalt.serviceTreeLabels" \. }}$/d' "${tmp}/nolabels/chart/templates/_helpers.tpl"
  render "${tmp}/nolabels/chart" "${full[@]}" >"${tmp}/nolabels.yaml"
  expect_red 'store labels dropped' 'labels differ from the LPSM set' assert_lpsm atomi.cloud "${tmp}/nolabels.yaml"
  ;;
reloader)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/reloader.yaml"
    assert_reloader "${tmp}/reloader.yaml" true
  done
  render chart "${full[@]}" --set-string 'upstream.global.podAnnotations.reloader\.stakater\.com/auto=false' >"${tmp}/optout.yaml"
  assert_reloader "${tmp}/optout.yaml" false
  render chart "${full[@]}" --set upstream.global.podAnnotations=null >"${tmp}/noreloader.yaml"
  expect_red 'Reloader annotation dropped' 'reloader.stakater.com/auto=true' assert_reloader "${tmp}/noreloader.yaml" true
  ;;
rendered-manifests)
  index=0
  for stack in "${stacks[@]}"; do
    index=$((index + 1))
    # shellcheck disable=SC2086
    render chart ${stack} >"${tmp}/rendered-${index}.yaml"
    vap_stage "${tmp}/rendered-${index}.yaml" "stack ${stack}"
  done
  render chart "${full[@]}" --set upstream.image.tag=latest >"${tmp}/latest.yaml"
  expect_red 'a :latest ESO image' 'explicit non-latest tag' vap_stage "${tmp}/latest.yaml" latest
  ;;
pin)
  dep="$(yq -o=json '.dependencies[] | select(.name == "external-secrets")' chart/Chart.yaml)"
  version="$(jq -r .version <<<"${dep}")"
  [[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ external-secrets ${version} is not an exact pin" >&2 && exit 1; }
  [ "$(jq -r .alias <<<"${dep}")" = upstream ] || { echo "❌ external-secrets is not aliased upstream" >&2 && exit 1; }
  [ "$(yq -r '.dependencies[] | select(.name == "external-secrets") | .version' chart/Chart.lock)" = "${version}" ] || { echo "❌ Chart.lock differs from Chart.yaml" >&2 && exit 1; }
  [ "$(git ls-files 'chart/charts/*.tgz')" = "chart/charts/external-secrets-${version}.tgz" ] || { echo "❌ the vendored archive is not external-secrets-${version}.tgz" >&2 && exit 1; }
  [ "$(yq -r .appVersion chart/Chart.yaml)" = "${version}" ] || { echo "❌ appVersion differs from the external-secrets version" >&2 && exit 1; }
  [ "$(tar -xzOf "chart/charts/external-secrets-${version}.tgz" external-secrets/Chart.yaml | yq -r .appVersion)" = "v${version}" ] || { echo "❌ the vendored chart does not default to image v${version}" >&2 && exit 1; }
  render chart "${full[@]}" | yq -N eval-all 'select(.kind == "Deployment") | .spec.template.spec.containers[].image' | sort -u >"${tmp}/images.txt"
  [ "$(cat "${tmp}/images.txt")" = "ghcr.io/external-secrets/external-secrets:v${version}" ] || { echo "❌ ESO images are not ghcr.io/external-secrets/external-secrets:v${version}: $(tr '\n' ' ' <"${tmp}/images.txt")" >&2 && exit 1; }
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/cobalt-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/cobalt-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'a tag that differs from Chart.yaml' 'does not match tag 9.9.9' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh
  ;;
presence)
  test -s docs/developer/cobalt-baseline.md
  test -s .claude/skills/cobalt/SKILL.md
  test -s policies/vap/workload-baseline.yaml
  test -s "${crd_list}"
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ cobalt ${mode} validation passed"
