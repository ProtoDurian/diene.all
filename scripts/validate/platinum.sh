#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq and yq programs are single-quoted on purpose
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-platinum}"
namespace="${NAMESPACE:-sulfoxide}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

c=chart
# name|values flags: base, local loopback landscapes, serving landscape x cluster, ENTEI host role.
stacks=("base|" "ditto|--values ${c}/values.ditto.yaml" "rotom|--values ${c}/values.rotom.yaml" "absol|--values ${c}/values.absol.yaml")
for l in pichu pikachu raichu ampharos; do
  for k in opal ruby emerald; do
    stacks+=("${l}-${k}|--values ${c}/values.${l}.yaml --values ${c}/values.${k}.yaml")
  done
done
stacks+=("entei|--values ${c}/values.opal.yaml --values ${c}/values.entei.yaml")
entei=(--values "${c}/values.opal.yaml" --values "${c}/values.entei.yaml")

render() { helm template "${release}" chart --namespace "${namespace}" "$@"; }
render_stack() { # render_stack <stack entry> <out>
  # shellcheck disable=SC2086
  render ${1#*|} >"$2"
}
json() { yq eval-all -o=json '.' "$1" | jq -s 'map(select(.kind != null))'; }

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
  echo "🟥 negative fixture '${label}' caught"
}

expect_refusal() {
  local pattern="$1"
  shift
  expect_red "refusal: ${pattern}" "${pattern}" render "$@"
}

# yq_edit <in> <out> <expr>: a sabotaged copy of a render.
yq_edit() { yq eval-all "$3" "$1" >"$2"; }

assert_lpsm() { # assert_lpsm <render> <prefix> <landscape> <cluster>
  json "$1" | need_jq "rendered labels differ from the LPSM set" --arg p "$2" --arg l "$3" --arg k "$4" '
    ({($p + "/platform"): "sulfoxide", ($p + "/service"): "platinum", ($p + "/module"): "gateway", ($p + "/layer"): "1"}
      + (if $l == "" then {} else {($p + "/landscape"): $l} end) + (if $k == "" then {} else {($p + "/cluster"): $k} end)) as $want |
    map(select(.kind != "ClusterRole" and .kind != "ClusterRoleBinding")) as $objs |
    ($objs | length) > 0 and all($objs[]; (.metadata.labels // {}) as $have | ($have | with_entries(select(.key | startswith($p + "/")))) == $want)'
}

assert_gateway() { # GatewayClass + ONE shared Gateway bound to kgateway, generated proxy kept internal
  json "$1" | need_jq "expected one GatewayClass platinum (kgateway.dev/kgateway) and one shared Gateway platinum-shared" '
    (map(select(.kind == "GatewayClass")) | length == 1 and .[0].metadata.name == "platinum" and .[0].spec.controllerName == "kgateway.dev/kgateway") and
    (map(select(.kind == "Gateway")) | length == 1 and .[0].metadata.name == "platinum-shared" and .[0].spec.gatewayClassName == "platinum"
      and .[0].spec.infrastructure.parametersRef == {group: "gateway.kgateway.dev", kind: "GatewayParameters", name: "platinum-proxy"}) and
    (map(select(.kind == "GatewayParameters")) | length == 1 and .[0].metadata.name == "platinum-proxy" and .[0].spec.kube.service.type == "ClusterIP")'
}

assert_proxy() { # kgateway-generated envoy pods meet the fleet VAP; the default kgateway class reuses platinum-proxy
  json "$1" | need_jq "platinum-proxy does not give generated envoy pods runAsNonRoot and CPU/memory requests and limits" '
    map(select(.kind == "GatewayParameters"))[0].spec.kube as $k |
    $k.podTemplate.securityContext.runAsNonRoot == true and ($k.omitDefaultSecurityContext // false) == false and
    ([$k.envoyContainer.resources // {} | .requests.cpu, .requests.memory, .limits.cpu, .limits.memory] | all(. != null and . != ""))' || return 1
  json "$1" | need_jq "the default kgateway GatewayClass is not bound to platinum-proxy, or Istio sidecars are enabled" '
    map(select(.kind == "Deployment" and .metadata.name == "platinum-gateway"))[0].spec.template.spec.containers[0].env as $e |
    ($e[] | select(.name == "KGW_GATEWAY_CLASS_PARAMETERS_REFS") | .value | fromjson) == {kgateway: {name: "platinum-proxy", namespace: "sulfoxide"}} and
    ([$e[] | select(.name | IN("KGW_ENABLE_ISTIO_AUTO_MTLS", "KGW_ENABLE_ISTIO_INTEGRATION")) | .value] | all(. != "true"))'
}

# Upstream-named cluster RBAC (kgateway v2.5.0 has no override) and the GatewayClass host-pool names `platinum`.
fullname_exempt='["ClusterRole/kgateway-sulfoxide", "ClusterRoleBinding/upstream-role-sulfoxide", "GatewayClass/platinum"]'

assert_fullname() { # every rendered name is <service>-<token>, bar the explicit exemptions
  json "$1" | need_jq "rendered names are not <service>-<token>: $(json "$1" | jq -c --argjson x "${fullname_exempt}" '[.[] | (.kind + "/" + .metadata.name) | select(IN($x[]) | not) | select(split("/")[1] | test("^[a-z0-9]+-[a-z0-9]+$") | not)]')" \
    --argjson x "${fullname_exempt}" 'all(.[]; (.kind + "/" + .metadata.name) as $n | ($n | IN($x[])) or (.metadata.name | test("^[a-z0-9]+-[a-z0-9]+$")))'
}

assert_health() { # fixed /healthz route on the shared Gateway, answered 2xx by kgateway
  json "$1" | need_jq "health route contract broken (Exact /healthz on platinum-shared:http -> DirectResponse platinum-healthz 2xx)" '
    (map(select(.kind == "HTTPRoute" and .metadata.name == "platinum-healthz")) | length == 1) and
    (map(select(.kind == "HTTPRoute" and .metadata.name == "platinum-healthz"))[0].spec as $s |
      $s.parentRefs == [{name: "platinum-shared", sectionName: "http"}] and ($s.hostnames // []) == [] and ($s.rules | length) == 1 and
      $s.rules[0].matches == [{path: {type: "Exact", value: "/healthz"}}] and ($s.rules[0].backendRefs // []) == [] and
      $s.rules[0].filters == [{type: "ExtensionRef", extensionRef: {group: "gateway.kgateway.dev", kind: "DirectResponse", name: "platinum-healthz"}}]) and
    (map(select(.kind == "DirectResponse" and .metadata.name == "platinum-healthz")) | length == 1 and .[0].spec.status >= 200 and .[0].spec.status < 300)'
}

edge() { json "$1" | jq 'map(select(.kind == "Service" and .metadata.name == "platinum-edge")) | .[0]'; }

assert_lb() { # assert_lb <render> <provider>
  edge "$1" | need_jq "platinum-edge is not a LoadBalancer exposing 80/443 on the generated proxy" '
    .spec.type == "LoadBalancer" and .spec.selector == {"gateway.networking.k8s.io/gateway-name": "platinum-shared"} and
    ([.spec.ports[] | [.port, .targetPort]] | sort) == [[80, 80], [443, 443]] and ([.spec.ports[] | has("nodePort")] | any | not)' || return 1
  case "$2" in
  aws) edge "$1" | need_jq "AWS overlay lost its NLB Elastic IP annotations" '.metadata.annotations as $a |
      ($a["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] // "" | split(",") | map(select(. != "")) | length) as $e |
      $a["service.beta.kubernetes.io/aws-load-balancer-type"] == "external" and $a["service.beta.kubernetes.io/aws-load-balancer-scheme"] == "internet-facing" and
      $e > 0 and ($a["service.beta.kubernetes.io/aws-load-balancer-subnets"] // "" | split(",") | length) == $e' || return 1 ;;
  oci) edge "$1" | need_jq "OCI overlay lost its reserved public IP annotation" '.metadata.annotations as $a |
      ($a["oci.oraclecloud.com/reserved-ips"] // "" | test("^[0-9.]+$")) and $a["oci.oraclecloud.com/load-balancer-type"] == "nlb"' || return 1 ;;
  digitalocean) edge "$1" | need_jq "DigitalOcean overlay lost its LB-lifetime name annotation" '.metadata.annotations as $a |
      ($a["service.beta.kubernetes.io/do-loadbalancer-name"] // "" | length) > 0' || return 1 ;;
  local) edge "$1" | need_jq "local loopback overlay carries a cloud LB annotation" '.metadata.annotations | keys | all(startswith("atomi.cloud/"))' || return 1 ;;
  esac
  local others
  others="$(edge "$1" | jq -r '.metadata.annotations | keys[] | select(startswith("atomi.cloud/") | not)' | rg -v "^($(provider_keys "$2"))$" || true)"
  [ -z "${others}" ] || { echo "❌ ${2} overlay carries another provider's annotation: ${others}" >&2 && return 1; }
}

provider_keys() {
  case "$1" in
  aws) echo 'service\.beta\.kubernetes\.io/aws-load-balancer-.*' ;;
  oci) echo 'oci\.oraclecloud\.com/.*' ;;
  digitalocean) echo 'service\.beta\.kubernetes\.io/do-loadbalancer-.*' ;;
  *) echo '__none__' ;;
  esac
}

assert_entei() { # the dev-host role renders the shared edge only
  json "$1" | need_jq "ENTEI overlay renders more than the shared edge (or lost ListenerSet admission)" '
    (map(select(.kind != "ServiceAccount" and .kind != "ClusterRole" and .kind != "ClusterRoleBinding" and .kind != "Deployment" and .metadata.name != "platinum-gateway") | .kind + "/" + .metadata.name) | sort) ==
      ["DirectResponse/platinum-healthz", "Gateway/platinum-shared", "GatewayClass/platinum", "GatewayParameters/platinum-proxy", "HTTPRoute/platinum-healthz", "Service/platinum-edge"] and
    (map(select(.kind == "Gateway"))[0].spec as $g |
      $g.allowedListeners == {namespaces: {from: "Selector", selector: {matchLabels: {"atomi.cloud/managed-vcluster": "true"}}}} and
      $g.listeners == [{name: "http", protocol: "HTTP", port: 80, allowedRoutes: {namespaces: {from: "Same"}}}])'
}

assert_vap() { # assert_vap <render> <label>: the inherited rendered-manifest stage
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "$1" || { echo "❌ kubeconform rejected ${2}" >&2 && return 1; }
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "$1" >"$1.vap.yaml"
  kyverno apply policies/vap --resource "$1.vap.yaml" --detailed-results --remove-color >"$1.kyverno.txt" 2>&1 ||
    { cat "$1.kyverno.txt" && echo "❌ VAP stage denied ${2}" >&2 && return 1; }
}

case "${mode}" in
schema | lint)
  for s in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${s#*|} >"${tmp}/lint.txt" 2>&1 || { cat "${tmp}/lint.txt" >&2 && echo "❌ ${s%%|*} rejected" >&2 && exit 1; }
  done
  [ "${mode}" = lint ] && { echo "✅ Platinum lint validation passed" && exit 0; }
  expect_red 'unknown provider' "value must be one of" helm lint chart --namespace "${namespace}" --set gateway.provider=gcp
  expect_red 'foreign controller' "value must be 'kgateway.dev/kgateway'" helm lint chart --namespace "${namespace}" --set gateway.controllerName=example.com/other
  expect_red 'non-2xx health status' "maximum" helm lint chart --namespace "${namespace}" --set gateway.health.status=503
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json" || { echo "❌ chart/values.schema.json is stale" >&2 && exit 1; }
  ;;
render)
  for s in "${stacks[@]}"; do render_stack "${s}" "${tmp}/r.yaml"; done
  test -z "$(find chart -maxdepth 1 -name 'values.lapras.yaml')" || { echo "❌ lapras is Boron-direct and has no kgateway overlay" >&2 && exit 1; }
  expect_refusal 'must equal release namespace' --namespace other
  expect_refusal 'fullnameOverride must be' --set fullnameOverride=platinum-api
  expect_refusal 'upstream.fullnameOverride must be' --set upstream.fullnameOverride=platinum-api
  expect_refusal 'AWS gateway mode requires' --set gateway.provider=aws
  expect_refusal 'identical lengths' --values chart/values.ruby.yaml --set 'gateway.aws.eipAllocationIds={eipalloc-1}'
  expect_refusal 'OCI gateway mode requires' --set gateway.provider=oci
  expect_refusal 'no registered-fleet Certificates' --set gateway.provider=local
  expect_refusal 'must point the default kgateway class' --set upstream.gatewayClassParametersRefs.kgateway.name=platinum-other
  ;;
lpsm-labels)
  render >"${tmp}/base.yaml"
  assert_lpsm "${tmp}/base.yaml" atomi.cloud "" ""
  render --values chart/values.ditto.yaml >"${tmp}/ditto.yaml"
  assert_lpsm "${tmp}/ditto.yaml" atomi.cloud ditto ""
  render --values chart/values.raichu.yaml --values chart/values.ruby.yaml >"${tmp}/raichu.yaml"
  assert_lpsm "${tmp}/raichu.yaml" atomi.cloud raichu ruby
  render "${entei[@]}" >"${tmp}/entei.yaml"
  assert_lpsm "${tmp}/entei.yaml" atomi.cloud "" entei
  json "${tmp}/raichu.yaml" | need_jq "platinum-owned objects lack LPSM annotations" 'map(select(.metadata.name | test("^platinum-(edge|shared|proxy|healthz|cert)|^platinum$"))) | all(.[]; .metadata.annotations["atomi.cloud/platform"] == "sulfoxide")'
  expect_refusal 'upstream.commonLabels must equal' --values chart/values.raichu.yaml --set serviceTree.cluster=other
  expect_refusal 'upstream.commonLabels must equal' --set labelPrefix=example.dev
  yq_edit "${tmp}/raichu.yaml" "${tmp}/drift.yaml" '(select(.kind == "Gateway") | .metadata.labels."atomi.cloud/service") = "drift"'
  expect_red 'a drifted LPSM label' 'labels differ from the LPSM set' assert_lpsm "${tmp}/drift.yaml" atomi.cloud raichu ruby
  ;;
gateway)
  for s in "${stacks[@]}"; do
    render_stack "${s}" "${tmp}/g.yaml"
    assert_gateway "${tmp}/g.yaml" || { echo "❌ in stack ${s%%|*}" >&2 && exit 1; }
    assert_proxy "${tmp}/g.yaml" || { echo "❌ in stack ${s%%|*}" >&2 && exit 1; }
  done
  render --values chart/values.pichu.yaml --values chart/values.opal.yaml >"${tmp}/g.yaml"
  json "${tmp}/g.yaml" | need_jq "registered-fleet Gateway lacks its HTTP + two terminating HTTPS listeners" '
    map(select(.kind == "Gateway"))[0].spec.listeners | map([.name, .protocol, .port, (.tls.mode // ""), (.tls.certificateRefs[0].name // "")]) ==
      [["http", "HTTP", 80, "", ""], ["https-primary", "HTTPS", 443, "Terminate", "platinum-certprimary"], ["https-backup", "HTTPS", 443, "Terminate", "platinum-certbackup"]]'
  yq_edit "${tmp}/g.yaml" "${tmp}/two.yaml" '., (select(.kind == "Gateway") | .metadata.name = "platinum-second")'
  expect_red 'a second Gateway' 'one shared Gateway' assert_gateway "${tmp}/two.yaml"
  yq_edit "${tmp}/g.yaml" "${tmp}/lb.yaml" '(select(.kind == "GatewayParameters") | .spec.kube.service.type) = "LoadBalancer"'
  expect_red 'a second public LoadBalancer from the generated proxy' 'one shared Gateway' assert_gateway "${tmp}/lb.yaml"
  yq_edit "${tmp}/g.yaml" "${tmp}/nores.yaml" 'del(select(.kind == "GatewayParameters") | .spec.kube.envoyContainer.resources.limits.memory)'
  expect_red 'envoy proxy without a memory limit' 'requests and limits' assert_proxy "${tmp}/nores.yaml"
  yq_edit "${tmp}/g.yaml" "${tmp}/root.yaml" 'del(select(.kind == "GatewayParameters") | .spec.kube.podTemplate)'
  expect_red 'envoy pods without pod runAsNonRoot' 'runAsNonRoot' assert_proxy "${tmp}/root.yaml"
  render --set-string upstream.controller.extraEnv.KGW_ENABLE_ISTIO_AUTO_MTLS=true >"${tmp}/istio.yaml"
  expect_red 'Istio sidecars switched on' 'Istio sidecars are enabled' assert_proxy "${tmp}/istio.yaml"
  ;;
health)
  for s in "${stacks[@]}"; do
    render_stack "${s}" "${tmp}/h.yaml"
    assert_health "${tmp}/h.yaml" || { echo "❌ in stack ${s%%|*}" >&2 && exit 1; }
  done
  render --set gateway.health.path=/health >"${tmp}/path.yaml"
  expect_red 'health route on a different path' 'health route contract broken' assert_health "${tmp}/path.yaml"
  render >"${tmp}/h.yaml"
  yq_edit "${tmp}/h.yaml" "${tmp}/backend.yaml" '(select(.kind == "HTTPRoute") | .spec.rules[0].filters[0].extensionRef.name) = "platinum-other"'
  expect_red 'health route to another backend' 'health route contract broken' assert_health "${tmp}/backend.yaml"
  yq_edit "${tmp}/h.yaml" "${tmp}/none.yaml" 'select(.kind != "HTTPRoute")'
  expect_red 'health route missing' 'health route contract broken' assert_health "${tmp}/none.yaml"
  ;;
lb)
  for s in "${stacks[@]}"; do
    render_stack "${s}" "${tmp}/lb.yaml"
    provider="$(yq -r '.gateway.provider' chart/values.yaml)"
    for f in ${s#*|}; do if [ -f "${f}" ] && [ -n "$(yq -r '.gateway.provider // ""' "${f}")" ]; then provider="$(yq -r '.gateway.provider' "${f}")"; fi; done
    assert_lb "${tmp}/lb.yaml" "${provider}" || { echo "❌ in stack ${s%%|*}" >&2 && exit 1; }
  done
  render --values chart/values.pichu.yaml --values chart/values.ruby.yaml >"${tmp}/aws.yaml"
  render --values chart/values.pichu.yaml --values chart/values.emerald.yaml >"${tmp}/oci.yaml"
  render --values chart/values.pichu.yaml --values chart/values.opal.yaml >"${tmp}/digitalocean.yaml"
  [ "$(for f in aws oci digitalocean; do edge "${tmp}/${f}.yaml" | jq -c '.metadata.annotations | with_entries(select(.key | startswith("atomi.cloud/") | not))'; done | sort -u | wc -l)" -eq 3 ] ||
    { echo "❌ per-cloud LB annotation sets are not distinct" >&2 && exit 1; }
  yq_edit "${tmp}/aws.yaml" "${tmp}/aws-drop.yaml" '(select(.kind == "Service" and .metadata.name == "platinum-edge") | .metadata.annotations) |= with_entries(select(.key | test("aws-load-balancer") | not))'
  expect_red 'AWS annotation block dropped' 'lost its NLB Elastic IP annotations' assert_lb "${tmp}/aws-drop.yaml" aws
  yq_edit "${tmp}/oci.yaml" "${tmp}/oci-drop.yaml" '(select(.kind == "Service" and .metadata.name == "platinum-edge") | .metadata.annotations) |= with_entries(select(.key | test("oraclecloud") | not))'
  expect_red 'OCI annotation block dropped' 'lost its reserved public IP annotation' assert_lb "${tmp}/oci-drop.yaml" oci
  yq_edit "${tmp}/digitalocean.yaml" "${tmp}/do-drop.yaml" '(select(.kind == "Service" and .metadata.name == "platinum-edge") | .metadata.annotations) |= with_entries(select(.key | test("do-loadbalancer") | not))'
  expect_red 'DO annotation block dropped' 'lost its LB-lifetime name annotation' assert_lb "${tmp}/do-drop.yaml" digitalocean
  yq_edit "${tmp}/digitalocean.yaml" "${tmp}/clusterip.yaml" '(select(.kind == "Service" and .metadata.name == "platinum-edge") | .spec.type) = "ClusterIP"'
  expect_red 'edge Service not a LoadBalancer' 'is not a LoadBalancer' assert_lb "${tmp}/clusterip.yaml" digitalocean
  ;;
entei)
  render "${entei[@]}" >"${tmp}/entei.yaml"
  assert_entei "${tmp}/entei.yaml"
  yq_edit "${tmp}/entei.yaml" "${tmp}/cert.yaml" '., (select(.kind == "GatewayClass") | .apiVersion = "cert-manager.io/v1" | .kind = "Certificate" | .metadata.name = "instance")'
  expect_red 'ENTEI renders an instance Certificate' 'more than the shared edge' assert_entei "${tmp}/cert.yaml"
  yq_edit "${tmp}/entei.yaml" "${tmp}/ls.yaml" '., (select(.kind == "GatewayClass") | .kind = "ListenerSet" | .metadata.name = "host")'
  expect_red 'ENTEI renders a per-host ListenerSet' 'more than the shared edge' assert_entei "${tmp}/ls.yaml"
  yq_edit "${tmp}/entei.yaml" "${tmp}/route.yaml" '., (select(.kind == "HTTPRoute") | .metadata.name = "platinum-host")'
  expect_red 'ENTEI renders a per-host HTTPRoute' 'more than the shared edge' assert_entei "${tmp}/route.yaml"
  render "${entei[@]}" --set devHost.emergencyListeners.enabled=true \
    --set-json 'devHost.emergencyListeners.listeners=[{"name":"escape","protocol":"HTTP","port":80,"hostname":"escape.example.test"}]' >"${tmp}/escape.yaml"
  json "${tmp}/escape.yaml" | need_jq "emergency listener not appended" 'map(select(.kind == "Gateway"))[0].spec.listeners | map(.name) == ["http", "escape"]'
  expect_red 'direct mutation on by default' 'more than the shared edge' assert_entei "${tmp}/escape.yaml"
  listeners="$(jq -nc '[range(64)] | map({name: "l\(.)", protocol: "HTTP", port: 80, hostname: "h\(.).example.test"})')"
  expect_refusal '64-listener ceiling' "${entei[@]}" --set devHost.emergencyListeners.enabled=true --set-json "devHost.emergencyListeners.listeners=${listeners}"
  expect_refusal 'emergency fallback is disabled' "${entei[@]}" --set-json 'devHost.emergencyListeners.listeners=[{"name":"x","protocol":"HTTP","port":80}]'
  expect_refusal 'requires devHost.enabled' --set devHost.emergencyListeners.enabled=true
  expect_refusal 'renders no Certificate' "${entei[@]}" --set registeredCertificates.enabled=true
  ;;
fullname)
  for s in "${stacks[@]}"; do
    render_stack "${s}" "${tmp}/n.yaml"
    assert_fullname "${tmp}/n.yaml" || { echo "❌ in stack ${s%%|*}" >&2 && exit 1; }
  done
  render >"${tmp}/n.yaml"
  json "${tmp}/n.yaml" | need_jq "a fullname exemption no longer renders; drop it" --argjson x "${fullname_exempt}" '[.[] | .kind + "/" + .metadata.name] as $n | all($x[]; IN($n[]))'
  yq_edit "${tmp}/n.yaml" "${tmp}/twodash.yaml" '(select(.kind == "Service" and .metadata.name == "platinum-edge") | .metadata.name) = "platinum-edge-lb"'
  expect_red 'a two-dash rendered name' 'not <service>-<token>' assert_fullname "${tmp}/twodash.yaml"
  yq_edit "${tmp}/n.yaml" "${tmp}/nodash.yaml" '(select(.kind == "HTTPRoute") | .metadata.name) = "platinum"'
  expect_red 'a chart-default (dash-less) rendered name' 'not <service>-<token>' assert_fullname "${tmp}/nodash.yaml"
  ;;
issuer-free)
  for s in "${stacks[@]}"; do
    render_stack "${s}" "${tmp}/i.yaml"
    json "${tmp}/i.yaml" | need_jq "${s%%|*}: platinum renders an issuer, Secret, ExternalSecret or ListenerSet" 'map(select(.kind | IN("Issuer", "ClusterIssuer", "Secret", "ExternalSecret", "ListenerSet"))) == []'
    json "${tmp}/i.yaml" | need_jq "${s%%|*}: registered Certificates must be the two zinc-letsencrypt wildcards" '
      map(select(.kind == "Certificate")) as $c | ($c | length) == 0 or (($c | length) == 2 and
        all($c[]; .spec.issuerRef == {group: "cert-manager.io", kind: "ClusterIssuer", name: "zinc-letsencrypt"} and (.spec.dnsNames | length) == 1 and (.spec.dnsNames[0] | test("^\\*\\.[a-z0-9.-]+$"))))'
  done
  render --values chart/values.ditto.yaml >"${tmp}/local.yaml"
  json "${tmp}/local.yaml" | need_jq "local loopback stack renders Certificates" 'map(select(.kind == "Certificate")) == []'
  ;;
pins)
  for dep in kgateway kgateway-crds; do
    v="$(yq -r ".dependencies[] | select(.name == \"${dep}\") | .version" chart/Chart.yaml)"
    [[ ${v} =~ ^v2\.[0-9]+\.[0-9]+$ ]] || { echo "❌ ${dep} chart pin '${v}' is not an explicit v2.x.y" >&2 && exit 1; }
    [ "$(yq -r ".dependencies[] | select(.name == \"${dep}\") | .version" chart/Chart.lock)" = "${v}" ] || { echo "❌ Chart.lock ${dep} differs from Chart.yaml" >&2 && exit 1; }
    test -s "chart/charts/${dep}-${v}.tgz" || { echo "❌ chart/charts/${dep}-${v}.tgz is not vendored" >&2 && exit 1; }
  done
  v="$(yq -r '.dependencies[] | select(.name == "kgateway") | .version' chart/Chart.yaml)"
  [ "$(yq -r '.appVersion' chart/Chart.yaml)" = "${v}" ] || { echo "❌ appVersion differs from the kgateway pin" >&2 && exit 1; }
  for key in .upstream.image.tag .upstream.controller.image.tag; do
    [ "$(yq -r "${key}" chart/values.yaml)" = "${v}" ] || { echo "❌ ${key} is not pinned to ${v}" >&2 && exit 1; }
  done
  render >"${tmp}/p.yaml"
  json "${tmp}/p.yaml" | need_jq "controller image or proxy image default is not the pinned ${v}" --arg v "${v}" '
    map(select(.kind == "Deployment" and .metadata.name == "platinum-gateway"))[0].spec.template.spec.containers[0] as $c |
    $c.image == "cr.kgateway.dev/kgateway-dev/kgateway:\($v)" and ($c.env[] | select(.name == "KGW_DEFAULT_IMAGE_TAG") | .value) == $v'
  gzip -dc tests/fixtures/gateway-api-standard-v1.7.0.yaml.gz | yq -o=json 'select(.metadata.name == "listenersets.gateway.networking.k8s.io")' |
    need_jq "ListenerSet is not pinned to gateway.networking.k8s.io/v1 in the Gateway API v1.7.0 standard bundle" '.metadata.annotations["gateway.networking.k8s.io/bundle-version"] == "v1.7.0" and .metadata.annotations["gateway.networking.k8s.io/channel"] == "standard" and [.spec.versions[] | select(.served and .storage) | .name] == ["v1"]'
  [ "$(yq -r '.spec.parentRef.kind + "@" + .apiVersion' tests/fixtures/entei/listenerset.yaml)" = "Gateway@gateway.networking.k8s.io/v1" ] || { echo "❌ fixture ListenerSet is not gateway.networking.k8s.io/v1" >&2 && exit 1; }
  [[ "$(yq -r '.image.tag' tests/fixtures/entei/cert-manager-values.yaml)" =~ ^v1\.[0-9]+\.[0-9]+$ ]] || { echo "❌ cert-manager fixture version is not pinned" >&2 && exit 1; }
  rg -q 'gateway-api-standard-v1\.7\.0\.yaml\.gz' scripts/validate/platinum-k3d.sh || { echo "❌ k3d tier does not apply the pinned Gateway API fixture" >&2 && exit 1; }
  ;;
reloader)
  render >"${tmp}/r.yaml"
  json "${tmp}/r.yaml" | need_jq "controller pods are not reloader opt-in" 'map(select(.kind == "Deployment"))[0].spec.template.metadata.annotations["reloader.stakater.com/auto"] == "true"'
  render --set-string 'upstream.controller.podAnnotations.reloader\.stakater\.com/auto=false' >"${tmp}/o.yaml"
  json "${tmp}/o.yaml" | need_jq "reloader opt-out did not turn the annotation off" 'map(select(.kind == "Deployment"))[0].spec.template.metadata.annotations["reloader.stakater.com/auto"] == "false"'
  ;;
rendered-manifests)
  for s in "${stacks[@]}"; do
    render_stack "${s}" "${tmp}/m-${s%%|*}.yaml"
    assert_vap "${tmp}/m-${s%%|*}.yaml" "${s%%|*}"
  done
  # Platinum's one wiring sabotage: the edge Service type moved off LoadBalancer.
  yq_edit "${tmp}/m-pichu-opal.yaml" "${tmp}/nodeport.yaml" '(select(.kind == "Service" and .metadata.name == "platinum-edge") | .spec.type) = "NodePort"'
  expect_red 'edge Service type moved to NodePort' 'NodePort services are forbidden' assert_vap "${tmp}/nodeport.yaml" nodeport
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/platinum-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  tar -tzf "${tmp}/git/platinum-0.1.0.tgz" >"${tmp}/files.txt"
  rg -q '^platinum/charts/kgateway/Chart.yaml$' "${tmp}/files.txt" || { echo "❌ package lacks the vendored kgateway chart" >&2 && exit 1; }
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/platinum-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'tag differs from Chart.yaml' 'does not match tag' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/bad" bash ./scripts/ci/publish.sh
  ;;
task-surface)
  task --list-all --json | jq -e '[.tasks[].name] as $n | ["debug", "template", "install", "remove"] | all(("pichu:opal:" + .) | IN($n[]))' >/dev/null ||
    { echo "❌ pichu:opal is missing a debug/template/install/remove task" >&2 && exit 1; }
  task --silent pichu:opal:template >"${tmp}/task.yaml"
  rg -q 'atomi.cloud/cluster: "opal"' "${tmp}/task.yaml" || { echo "❌ pichu:opal:template did not stack values.opal.yaml" >&2 && exit 1; }
  ;;
presence)
  test -s docs/developer/platinum-baseline.md
  test -s .claude/skills/platinum/SKILL.md
  rg -q 'listener ceiling' docs/developer/platinum-baseline.md || { echo "❌ baseline doc does not document the emergency listener ceiling" >&2 && exit 1; }
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Platinum ${mode} validation passed"
