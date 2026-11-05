#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-helm-wrapper}"
namespace="${NAMESPACE:-sample}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

bash ./scripts/local/vendor-chart-config.sh >/dev/null

render_contracts() {
  local ns="$1"
  shift
  helm template "${release}" chart --namespace "${ns}" --values chart/values.example.yaml --set "serviceTree.platform=${ns}" "$@" |
    yq -o=json 'select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data'
}

expect_vector() {
  local key="$1" host="$2" parsed_key="$3" coordinate="$4"
  shift 4
  render_contracts nitroso "$@" >"${tmp}/vector.json"
  jq -e --arg key "${key}" --arg host "${host}" --arg parsed "${parsed_key}" --argjson want "${coordinate}" \
    '.[$key] == $host and (.[$parsed] | fromjson) == $want' "${tmp}/vector.json" >/dev/null ||
    { echo "❌ LPSM vector ${host} mismatch" >&2 && cat "${tmp}/vector.json" >&2 && exit 1; }
}

expect_refusal() {
  local pattern="$1" ns="$2"
  shift 2
  if helm template "${release}" chart --namespace "${ns}" --values chart/values.example.yaml --set "serviceTree.platform=${ns}" "$@" >/dev/null 2>"${tmp}/refusal.txt"; then
    echo "❌ accepted: $*" >&2 && exit 1
  fi
  rg -q -- "${pattern}" "${tmp}/refusal.txt" || { echo "❌ wrong refusal for $*" >&2 && cat "${tmp}/refusal.txt" >&2 && exit 1; }
}

stacks=("" "--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")

# The podinfo helm-test hook Pods are upstream-named and only exist on `helm test`.
render_upstream() {
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set upstream.enabled=true --skip-tests
}

expect_dns_names() {
  local file="$1"
  yq eval-all -o=json '.' "${file}" | jq -s -e 'map(select(.kind != null) | .metadata.name, (.spec.target.name? // empty)) | length > 0 and all(.[]; type == "string" and test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null ||
    { echo "❌ a rendered or generated name in ${file} is not <service>-<token>" >&2 && yq eval-all -o=json '.' "${file}" | jq -s -r 'map(select(.kind != null) | .metadata.name, (.spec.target.name? // empty))[]' >&2 && exit 1; }
}

case "${mode}" in
schema)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack} >"${tmp}/schema.txt" 2>&1 ||
      { echo "❌ schema rejected the stack '${stack:-values.yaml}'" >&2 && cat "${tmp}/schema.txt" >&2 && exit 1; }
  done
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
  helm template "${release}" chart --namespace "${namespace}" >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;
config-vendoring)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/config.yaml"
  yq eval-all -o=json '.' "${tmp}/config.yaml" | jq -s -e 'map(select(.kind == "ConfigMap" and .metadata.name == "wrapper-config"))[0].data | has("application.yaml") and has("application.example.yaml")' >/dev/null
  ;;
labels)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq -s -e 'map(select(.kind != null)) | length > 0 and all(.[]; .metadata.labels["atomi.cloud/platform"] == "sample" and .metadata.labels["atomi.cloud/service"] == "wrapper" and .metadata.labels["atomi.cloud/module"] == "api" and .metadata.labels["atomi.cloud/layer"] == "2" and .metadata.labels["atomi.cloud/landscape"] == "example" and .metadata.labels["atomi.cloud/cluster"] == "lapras" and .metadata.annotations["atomi.cloud/platform"] == "sample")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml --set labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -s -e 'map(select(.kind != null)) | length > 0 and all(.[]; .metadata.labels["example.dev/platform"] == "sample" and .metadata.annotations["example.dev/service"] == "wrapper" and .metadata.labels["atomi.cloud/platform"] == null and .metadata.annotations["atomi.cloud/service"] == null)' >/dev/null
  ;;
reloader)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" | jq -s -e 'map(select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")) | length > 0 and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "true")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set workload.reloader.enabled=false >"${tmp}/optout.yaml"
  yq eval-all -o=json '.' "${tmp}/optout.yaml" | jq -s -e 'map(select(.kind == "Deployment"))[0].metadata.annotations["reloader.stakater.com/auto"] == null' >/dev/null
  ;;
secret)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set secret.enabled=true >"${tmp}/secret.yaml"
  yq eval-all -o=json '.' "${tmp}/secret.yaml" | jq -s -e 'map(select(.kind == "ExternalSecret")) | length == 1 and .[0].spec.data == null' >/dev/null ||
    { echo "❌ ExternalSecret declares hand-written key mappings (spec.data)" >&2 && exit 1; }
  yq eval-all -o=json '.' "${tmp}/secret.yaml" | jq -s -e 'map(select(.kind == "ExternalSecret"))[0] as $secret | $secret.metadata.name == "wrapper-secrets" and $secret.spec.target.name == "wrapper-secrets" and ($secret.spec.dataFrom | map(.find.path)) == ["/shared", "/wrapper"] and ($secret.spec.dataFrom | map(.rewrite[0].regexp.target)) == ["SHARED_$1", "WRAPPER_$1"]' >/dev/null ||
    { echo "❌ ExternalSecret name or folder-derived prefixes are wrong" >&2 && exit 1; }
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set secret.sharedFolder=/common --set secret.serviceFolder=/team/wrapper-api |
    yq eval-all -o=json '.' | jq -s -e 'map(select(.kind == "ExternalSecret"))[0].spec.dataFrom | map(.rewrite[0].regexp.target) == ["COMMON_$1", "TEAM_WRAPPER_API_$1"]' >/dev/null ||
    { echo "❌ ExternalSecret prefixes are not derived from the folders" >&2 && exit 1; }
  expect_refusal 'secret key prefixes "SHARED_" \(/shared\) and "SHARED_" \(/shared\) collide' "${namespace}" --set secret.serviceFolder=/shared
  expect_refusal 'collide' "${namespace}" --set secret.sharedFolder=/wrapper/inner
  expect_refusal 'yields an empty key prefix' "${namespace}" --set secret.serviceFolder=/
  ;;
fullname)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm template "${release}" chart --namespace "${namespace}" ${stack} >"${tmp}/names.yaml"
    expect_dns_names "${tmp}/names.yaml"
  done
  render_upstream >"${tmp}/upstream.yaml"
  expect_dns_names "${tmp}/upstream.yaml"
  yq eval-all -o=json '.' "${tmp}/upstream.yaml" | jq -s -e 'map(select(.kind == "Deployment") | .metadata.name) | sort == ["wrapper-api", "wrapper-upstream"]' >/dev/null ||
    { echo "❌ the upstream sub-chart did not render under its fullnameOverride" >&2 && exit 1; }
  yq -e '.upstream.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  ;;
primordial)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set primordial.enabled=true --set 'primordial.identity.concreteLandscapes={example,serving}' --set 'primordial.logtoApp.landscapes={example,serving}' >"${tmp}/primordial.yaml"
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/primordial.yaml"
  yq eval-all -o=json '.' "${tmp}/primordial.yaml" | jq -s -e 'map(select(.kind == "PlatformDependency"))[0].spec as $spec | [$spec.database, $spec.kv, $spec.cache, $spec.store] | map(. // {}) | add | to_entries | all(.[]; (.value.engine | keys) == [.value.type])' >/dev/null
  yq eval-all -o=json '.' "${tmp}/primordial.yaml" | jq -s -e 'map(select(.kind == "LogtoApp")) | map(.metadata.name) == ["wrapper-identityexample", "wrapper-identityserving"] and map(.spec.identityRef) == [{platform: "sample", landscape: "example"}, {platform: "sample", landscape: "serving"}] and map(.metadata.annotations["atomi.cloud/identity-issuer"]) == ["api.lithium.aldehyde.example.cluster.atomi.cloud", "api.lithium.aldehyde.serving.cluster.atomi.cloud"] and map(.metadata.annotations["atomi.cloud/credential-destination"]) == ["example:/wrapper", "serving:/wrapper"]' >/dev/null
  yq eval-all -o=json '.' "${tmp}/primordial.yaml" | jq -s -e 'map(select(.kind == "Problem")) | length == 1 and .[0].spec.module == "api" and .[0].metadata.name == "wrapper-problemsapi"' >/dev/null
  if rg -n '(^|[[:space:]])(share|sharedVia|redirectUris|desiredVersion):' "${tmp}/primordial.yaml" >&2; then
    echo "❌ primordial CRs carry a forbidden sharing/redirect/version field" >&2 && exit 1
  fi
  expect_refusal 'repeats "example"' "${namespace}" --set 'primordial.identity.concreteLandscapes={example,serving}' --set 'primordial.logtoApp.landscapes={example,serving,example}'
  expect_refusal 'repeats "serv-ing"' "${namespace}" --set 'primordial.identity.concreteLandscapes={serving,serv-ing}' --set 'primordial.logtoApp.landscapes={serving,serv-ing}'
  expect_refusal '"nitroso" is not listed in primordial.identity.concreteLandscapes' "${namespace}" --set 'primordial.logtoApp.landscapes={example,nitroso}'
  expect_refusal 'is the consumer platform' "${namespace}" --set 'primordial.logtoApp.landscapes={example,sample}'
  expect_refusal 'is a virtual landscape' "${namespace}" --set 'primordial.logtoApp.landscapes={example-vlandscape}'
  expect_refusal 'at least one concrete landscape' "${namespace}" --set 'primordial.logtoApp.landscapes=null'
  ;;
lpsm)
  expect_vector lpsm.ordinaryHostname api.zinc.nitroso.serving.cluster.atomi.cloud lpsm.ordinaryParsed \
    '{"landscape":"serving","platform":"nitroso","service":"zinc","module":"api","instance":""}' \
    --set contracts.lpsm.service=zinc --set contracts.lpsm.landscape=serving
  expect_vector lpsm.instanceHostname api.zinc.nitroso.raichu.serving.cluster.atomi.cloud lpsm.parsed \
    '{"landscape":"serving","platform":"nitroso","service":"zinc","module":"api","instance":"raichu"}' \
    --set contracts.lpsm.service=zinc --set contracts.lpsm.landscape=serving --set contracts.lpsm.instance=raichu --set contracts.lpsm.instanceZone=cluster.atomi.cloud
  expect_vector lpsm.instanceHostname api.zinc.nitroso.run42.absol.localhost lpsm.parsed \
    '{"landscape":"absol","platform":"nitroso","service":"zinc","module":"api","instance":"run42"}' \
    --set contracts.lpsm.service=zinc --set contracts.lpsm.landscape=absol --set contracts.lpsm.instance=run42 --set contracts.lpsm.instanceZone=localhost
  expect_vector lpsm.instanceHostname api.lithium.nitroso.kirin.lapras.admin.atomi.cloud lpsm.parsed \
    '{"landscape":"lapras","platform":"nitroso","service":"lithium","module":"api","instance":"kirin"}' \
    --set contracts.lpsm.service=lithium --set contracts.lpsm.landscape=lapras --set contracts.lpsm.instance=kirin --set contracts.lpsm.instanceZone=admin.atomi.cloud
  expect_vector lpsm.instanceHostname api.zinc.nitroso.otter-beats-potato.castform.host.example.invalid lpsm.parsed \
    '{"landscape":"castform","platform":"nitroso","service":"zinc","module":"api","instance":"otter-beats-potato"}' \
    --set contracts.lpsm.service=zinc --set contracts.lpsm.landscape=castform --set contracts.lpsm.instance=otter-beats-potato --set contracts.lpsm.instanceZone=host.example.invalid
  render_contracts other --set contracts.lpsm.service=zinc --set contracts.lpsm.landscape=serving | jq -e '."lpsm.ordinaryHostname" == "api.zinc.other.serving.cluster.atomi.cloud"' >/dev/null
  expect_refusal 'must equal release namespace' nitroso --set serviceTree.platform=other
  expect_refusal 'canonical dotted LPSM form' nitroso --set contracts.lpsm.instanceZone=localhost --set-string contracts.lpsm.parseHostname=api-zinc-nitroso-run42-absol.localhost
  expect_refusal 'canonical dotted LPSM form' "${namespace}" --set-string contracts.lpsm.parseHostname=api-wrapper-sample-run001-example.local.example.invalid
  label_63="$(printf 'a%.0s' {1..63})"
  render_contracts nitroso --set-string contracts.lpsm.instance="${label_63}" | jq -e --arg host "api.wrapper.nitroso.${label_63}.example.local.example.invalid" '."lpsm.instanceHostname" == $host' >/dev/null
  for bad in run.42 Run42 RUN42 '' -run42 run42- "${label_63}a" 'run_42'; do
    expect_refusal 'must be one lowercase DNS-1123 label of at most 63 bytes' nitroso --set-string contracts.lpsm.instance="${bad}"
  done
  for bad in 'api..nitroso.example.local.example.invalid' "api.wrapper.nitroso.${label_63}a.example.local.example.invalid" 'api.-zinc.nitroso.example.local.example.invalid'; do
    expect_refusal 'must be one lowercase DNS-1123 label of at most 63 bytes' nitroso --set-string contracts.lpsm.parseHostname="${bad}"
  done
  expect_refusal 'hostname label "'"${label_63}"'a" must be one lowercase DNS-1123 label' nitroso --set-string contracts.lpsm.service="${label_63}a"
  expect_refusal 'hostname label "-serving" must be one lowercase DNS-1123 label' nitroso --set-string contracts.lpsm.landscape=-serving
  render_contracts nitroso --set 'primordial.identity.concreteLandscapes={example,serving}' --set contracts.lpsm.identityLandscape=serving | jq -e '."identity.issuer" == "api.lithium.aldehyde.serving.cluster.atomi.cloud"' >/dev/null
  expect_refusal 'is the consumer platform' nitroso --set contracts.lpsm.identityLandscape=nitroso
  expect_refusal 'is a virtual landscape' nitroso --set contracts.lpsm.identityLandscape=example-vlandscape
  expect_refusal '"nitroso" is not listed in primordial.identity.concreteLandscapes' "${namespace}" --set contracts.lpsm.identityLandscape=nitroso
  expect_refusal '"serving" is not listed in primordial.identity.concreteLandscapes' nitroso --set contracts.lpsm.identityLandscape=serving
  label_a="$(render_contracts "${namespace}" --set-string instance.physicalId=repository-a:pr-123 | jq -r '."instance.label"')"
  label_b="$(render_contracts "${namespace}" --set-string instance.physicalId=repository-b:pr-123 | jq -r '."instance.label"')"
  [ "${label_a}" = "${label_b}" ] && echo "❌ repository-qualified instance labels collided" >&2 && exit 1
  long_id="$(printf 'repository-%080d' 1)"
  render_contracts "${namespace}" --set-string instance.physicalId="${long_id}" |
    jq -e --arg id "${long_id}" '."instance.original" == $id and (."instance.label" | length <= 63 and test("^repository-0+-[0-9a-f]{8}$"))' >/dev/null ||
    { echo "❌ long physical id did not normalize to a hashed DNS-1123 label with its original recorded" >&2 && exit 1; }
  ;;
lb)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=digitalocean >"${tmp}/do.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=oci --set-string gateway.oci.reservedPublicIp=203.0.113.10 >"${tmp}/oci.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=aws --set-string 'gateway.aws.subnetIds[0]=subnet-a' --set-string 'gateway.aws.subnetIds[1]=subnet-b' --set-string 'gateway.aws.eipAllocationIds[0]=eipalloc-a' --set-string 'gateway.aws.eipAllocationIds[1]=eipalloc-b' >"${tmp}/aws.yaml"
  yq eval-all -o=json '.' "${tmp}/do.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway"))[0] | .spec.type == "LoadBalancer" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == null and .metadata.annotations["oci.oraclecloud.com/reserved-ips"] == null' >/dev/null
  yq eval-all -o=json '.' "${tmp}/oci.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway"))[0].metadata.annotations["oci.oraclecloud.com/reserved-ips"] == "203.0.113.10"' >/dev/null
  yq eval-all -o=json '.' "${tmp}/aws.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway"))[0] | .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-subnets"] == "subnet-a,subnet-b" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == "eipalloc-a,eipalloc-b"' >/dev/null
  if rg -n 'nodePort:|hostPort:' "${tmp}/do.yaml" "${tmp}/oci.yaml" "${tmp}/aws.yaml" >&2; then
    echo "❌ rendered gateway carries nodePort/hostPort" >&2 && exit 1
  fi
  ;;
task-surface)
  task --list-all --json | jq -e '[.tasks[].name] as $names | ["debug", "template", "install", "remove"] | all(("example:lapras:" + .) | IN($names[]))' >/dev/null ||
    { echo "❌ example:lapras is missing a debug/template/install/remove task" >&2 && exit 1; }
  task --silent example:lapras:template >"${tmp}/task-template.yaml"
  rg -q '^kind: Deployment$' "${tmp}/task-template.yaml" || { echo "❌ example:lapras:template rendered no Deployment" >&2 && exit 1; }
  rg -q 'atomi.cloud/cluster: "lapras"' "${tmp}/task-template.yaml" || { echo "❌ example:lapras:template did not stack values.lapras.yaml" >&2 && exit 1; }
  ;;
rendered-manifests)
  index=0
  for stack in "${stacks[@]}" upstream; do
    index=$((index + 1))
    if [ "${stack}" = upstream ]; then
      render_upstream >"${tmp}/rendered-${index}.yaml"
    else
      # shellcheck disable=SC2086
      helm template "${release}" chart --namespace "${namespace}" ${stack} >"${tmp}/rendered-${index}.yaml"
    fi
    kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/rendered-${index}.yaml"
    yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered-${index}.yaml" >"${tmp}/vap-resources-${index}.yaml"
    kyverno apply policies/vap --resource "${tmp}/vap-resources-${index}.yaml" --detailed-results --remove-color
  done
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;
presence)
  test -s docs/developer/helm-wrapper-baseline.md
  test -s .claude/skills/helm-wrapper/SKILL.md
  test -s chart/templates/webhook-route.yaml
  test -s chart/templates/contracts.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s probes/features.json
  ;;
gateway-webhook-presence)
  rg -q '/healthz' docs/developer/helm-wrapper-baseline.md chart/values.yaml
  rg -q '/internal/webhooks/\{provider\}' docs/developer/helm-wrapper-baseline.md
  test -s chart/templates/webhook-route.yaml
  test -s chart/templates/contracts.yaml
  ;;
tokenization-presence)
  rg -q '^## Tokenization surface$' docs/developer/helm-wrapper-baseline.md
  rg -q 'repository-qualified physical instance id' docs/developer/helm-wrapper-baseline.md
  rg -q 'upstream chart name/version/repository' docs/developer/helm-wrapper-baseline.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Helm wrapper ${mode} validation passed"
