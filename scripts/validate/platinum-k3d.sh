#!/usr/bin/env bash
# k3d tiers: `integration` (ditto stack) and `entei` (ENTEI dev-host overlay + node-owned fixtures).
# shellcheck disable=SC2329 # helpers are invoked through wait_for
set -euo pipefail

tier="${1:-}"
[ "${tier}" != integration ] && [ "${tier}" != entei ] && echo "❌ tier must be integration or entei" >&2 && exit 1

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s:%s' "${PWD}" "${tier}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-platinum-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-platinum-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-platinum}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
http_port="${K3D_HTTP_PORT:-18080}"
ctx="k3d-${cluster_name}"
ns=sulfoxide
vap_ns=platinum-vapcheck
fx=tests/fixtures/entei
host=api.zinc.nitroso.fixture1.eevee.dev.example.test
crd_bundle_digest=4e2602c4cbe1afbc394d86f4ac6522e1a5263b01133bba1e40a6d1a549e753a1
tmp="$(mktemp -d)"
pf_pid=""
trap '[ -n "${pf_pid}" ] && { pkill -P "${pf_pid}" 2>/dev/null; kill "${pf_pid}" 2>/dev/null; } || true; bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

k() { kubectl --context "${ctx}" "$@"; }

fail() {
  echo "❌ $*" >&2
  k get gateway,listenerset,httproute,certificate -A -o wide >&2 2>/dev/null || true
  k -n "${ns}" logs deployment/platinum-gateway --tail=40 >&2 2>/dev/null || true
  exit 1
}

# wait_for <seconds> <description> <cmd...>
wait_for() {
  local deadline=$((SECONDS + $1)) what="$2"
  shift 2
  until "$@" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || fail "timed out waiting for ${what}"
    sleep 2
  done
}

condition() { # condition <type> <kind/name> [-n ns]: True for the current generation
  local type="$1"
  shift
  k get "$@" -o json | jq -e --arg t "${type}" '.metadata.generation as $g | [.status.conditions[]? | select(.type == $t and .observedGeneration == $g) | .status] == ["True"]' >/dev/null
}

route_ok() { # every parent of the route reports Accepted and ResolvedRefs for the current generation
  local name="$1" namespace="$2"
  k -n "${namespace}" get httproute "${name}" -o json |
    jq -e '.metadata.generation as $g | (.status.parents | length) > 0 and
      all(.status.parents[]; ([.conditions[] | select((.type == "Accepted" or .type == "ResolvedRefs") and .observedGeneration == $g) | .status] | sort) == ["True", "True"])' >/dev/null
}

body_of() { curl -sS --max-time 5 "$@"; }

bash ./scripts/local/create-k3d-cluster.sh
helm dependency build chart >/dev/null

# The parent VAP, bound with Deny on the platinum namespaces before anything is installed (fixture workloads stay unbound).
for n in "${ns}" "${vap_ns}"; do k create namespace "${n}" --dry-run=client -o yaml | k apply -f - >/dev/null; done
k apply -f policies/vap/ >/dev/null
for p in $(yq -N '.metadata.name' policies/vap/*.yaml); do
  k apply -f - >/dev/null <<EOF
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: {name: ${p}}
spec:
  policyName: ${p}
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchExpressions: [{key: kubernetes.io/metadata.name, operator: In, values: [${ns}, ${vap_ns}]}]
EOF
done
vap_denies() { ! k -n "${ns}" create deployment vap-probe --image=registry.k8s.io/pause:3.10 --dry-run=server >"${tmp}/vap.txt" 2>&1 && rg -q 'requests and limits' "${tmp}/vap.txt"; }
wait_for 60 "the parent VAP to deny an unhardened Deployment" vap_denies
echo "✅ parent VAP bound with Deny on ${ns} and ${vap_ns}"

gzip -dc tests/fixtures/gateway-api-standard-v1.7.0.yaml.gz >"${tmp}/gateway-api.yaml"
echo "${crd_bundle_digest}  ${tmp}/gateway-api.yaml" | sha256sum -c --quiet || fail "Gateway API CRD fixture checksum mismatch"
k apply --server-side -f "${tmp}/gateway-api.yaml" >/dev/null
helm upgrade --install platinum-crds chart/charts/kgateway-crds-v2.5.0.tgz --kube-context "${ctx}" --namespace "${ns}" --create-namespace --wait >/dev/null

stack=(--values chart/values.ditto.yaml)
[ "${tier}" = entei ] && stack=(--values chart/values.opal.yaml --values chart/values.entei.yaml)
helm upgrade --install platinum chart --kube-context "${ctx}" --namespace "${ns}" "${stack[@]}" --wait --timeout 5m
k -n "${ns}" wait --for=condition=Programmed gateway/platinum-shared --timeout=5m
echo "✅ Gateway platinum-shared Programmed=True"
k get gatewayclass platinum -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' | rg -qx True || fail "GatewayClass platinum not Accepted"

wait_for 180 "platinum-edge endpoints" bash -c "kubectl --context ${ctx} -n ${ns} get endpointslices -l kubernetes.io/service-name=platinum-edge -o json | jq -e '[.items[].endpoints[]? | select(.conditions.ready)] | length > 0'"
k -n "${ns}" get service platinum-shared -o json | jq -c '[.spec.ports[] | .targetPort] | sort' >"${tmp}/generated-ports.json"
k -n "${ns}" get service platinum-edge -o json | jq -c '[.spec.ports[] | .targetPort] | sort' >"${tmp}/edge-ports.json"
jq -e --slurpfile edge "${tmp}/edge-ports.json" '. - $edge[0] == []' "${tmp}/generated-ports.json" >/dev/null || fail "platinum-edge targetPorts $(cat "${tmp}/edge-ports.json") miss a generated proxy port $(cat "${tmp}/generated-ports.json")"
[ "$(k -n "${ns}" get service platinum-shared -o jsonpath='{.spec.type}')" = ClusterIP ] || fail "the generated proxy Service is not ClusterIP"
echo "✅ the VAP admitted the generated proxy Deployment platinum-shared"

health() { [[ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${http_port}/healthz")" =~ ^2[0-9][0-9]$ ]]; }
wait_for 180 "/healthz 2xx through the LoadBalancer" health
echo "✅ /healthz answers 2xx through platinum-edge"

classes() { k get gatewayclass -o json | jq -e '[.items[].metadata.name] | sort == ["kgateway", "platinum"]' >/dev/null; }
wait_for 120 "GatewayClasses to be exactly kgateway + platinum" classes
k get gatewayclass kgateway -o json | jq -e --arg ns "${ns}" '.spec.parametersRef == {group: "gateway.kgateway.dev", kind: "GatewayParameters", name: "platinum-proxy", namespace: $ns}' >/dev/null ||
  fail "the default kgateway GatewayClass is not bound to platinum-proxy"
probe_gateway() { # probe_gateway <name> <class> [GatewayParameters name]
  k apply -f - >/dev/null <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: $1, namespace: ${vap_ns}}
spec:
  gatewayClassName: $2
  $([ -n "${3:-}" ] && echo "infrastructure: {parametersRef: {group: gateway.kgateway.dev, kind: GatewayParameters, name: $3}}")
  listeners: [{name: http, protocol: HTTP, port: 8080}]
EOF
}
probe_gateway default-probe kgateway
k -n "${vap_ns}" wait --for=condition=Programmed gateway/default-probe --timeout=3m >/dev/null || fail "a Gateway on the default kgateway class was not Programmed"
[ "$(k -n "${vap_ns}" get service default-probe -o jsonpath='{.spec.type}')" = ClusterIP ] || fail "the default kgateway class generated a non-ClusterIP Service"
k get service -A -o json | jq -e --arg ns "${ns}" '[.items[] | select(.spec.type == "LoadBalancer") | .metadata.namespace + "/" + .metadata.name] == [$ns + "/platinum-edge"]' >/dev/null ||
  fail "a LoadBalancer Service other than platinum-edge exists"
k -n "${vap_ns}" delete gateway default-probe --wait >/dev/null
echo "✅ GatewayClasses are kgateway + platinum; the default class stays ClusterIP; platinum-edge is the only LoadBalancer"

k apply -f - >/dev/null <<EOF
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata: {name: bare-proxy, namespace: ${vap_ns}}
spec: {kube: {service: {type: ClusterIP}}}
EOF
probe_gateway bare-probe platinum bare-proxy
denied() { {
  k get events -n "${vap_ns}" -o json
  k -n "${vap_ns}" get gateway bare-probe -o json
  k -n "${ns}" logs deployment/platinum-gateway
} 2>/dev/null | rg 'diene-wrapper-workload-baseline' | rg -q 'bare-probe'; }
wait_for 120 "the VAP to deny the proxy Deployment of a GatewayParameters without envoy resources" denied
[ -z "$(k -n "${vap_ns}" get deployment bare-probe --ignore-not-found -o name)" ] || fail "an unhardened proxy Deployment was admitted"
k -n "${vap_ns}" delete gateway bare-probe --wait >/dev/null
k -n "${vap_ns}" delete gatewayparameters bare-proxy --wait >/dev/null
echo "✅ the VAP denies a proxy Deployment without envoy resources"

if [ "${tier}" = integration ]; then
  k apply -f tests/fixtures/sample.yaml >/dev/null
  k -n platinum-sample rollout status deployment/sample --timeout=3m >/dev/null
  wait_for 120 "sample HTTPRoute Accepted+ResolvedRefs" route_ok sample platinum-sample
  sample() { body_of -H 'Host: sample.ditto.localhost' "http://127.0.0.1:${http_port}/hostname" | rg -q '^sample-'; }
  wait_for 120 "sample HTTPRoute traffic" sample
  echo "✅ sample HTTPRoute routes traffic through the shared Gateway"

  PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh >/dev/null
  helm pull "oci://localhost:${registry_port}/charts/platinum" --version 0.1.0 --plain-http --destination "${tmp}"
  test -s "${tmp}/platinum-0.1.0.tgz" || fail "OCI round-trip produced no archive"
  echo "✅ k3d integration tier passed (Programmed, sample route, /healthz 2xx, OCI round-trip)"
  exit 0
fi

# ENTEI tier: only node-owned fixtures; no charts/sulfur or charts/zinc artifact.
cm_version="$(yq -r '.image.tag' "${fx}/cert-manager-values.yaml")"
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version "${cm_version}" --kube-context "${ctx}" --namespace cert-manager --create-namespace --values "${fx}/cert-manager-values.yaml" --wait --timeout 5m >/dev/null
echo "✅ jetstack/cert-manager ${cm_version} installed"
k apply -f "${fx}/namespace.yaml" >/dev/null
k apply -f "${fx}/issuers.yaml" >/dev/null
k -n entei-fixture wait --for=condition=Ready certificate/fixture-ca --timeout=3m >/dev/null
k apply -f "${fx}/certificate.yaml" >/dev/null
k -n entei-fixture wait --for=condition=Ready certificate/fixture1-instance --timeout=3m >/dev/null
echo "✅ fixture Certificate Ready"
k -n entei-fixture get secret fixture-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"${tmp}/ca.crt"

k apply -f "${fx}/backends.yaml" >/dev/null
k -n entei-fixture rollout status deployment/fixture-a --timeout=3m >/dev/null
k -n entei-fixture rollout status deployment/fixture-b --timeout=3m >/dev/null

# service <name> <app> <port> <port name> [target port]: a ClusterIP Service standing in for the vcluster-synced one.
service() {
  k apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Service
metadata: {name: $1, namespace: entei-fixture}
spec:
  type: ClusterIP
  selector: {app: $2}
  ports: [{name: $4, port: $3, targetPort: ${5:-8080}}]
EOF
}
# route <service> <port>: the per-host HTTPRoute targets the observed Service and resolved numeric port.
route() {
  k apply -f - >/dev/null <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: api-zinc, namespace: entei-fixture}
spec:
  parentRefs: [{group: gateway.networking.k8s.io, kind: ListenerSet, name: api-zinc, sectionName: https}]
  hostnames: [${host}]
  rules: [{backendRefs: [{name: $1, port: $2}]}]
EOF
}

gateway_snapshot() { k -n "${ns}" get gateway platinum-shared -o json | jq -c '{generation: .metadata.generation, spec}'; }
cert_snapshot() {
  {
    k -n entei-fixture get certificate fixture1-instance -o json | jq -c '{uid: .metadata.uid, generation: .metadata.generation, notAfter: .status.notAfter, spec}'
    k -n entei-fixture get secret fixture1-instance -o jsonpath='{.data.tls\.crt}' | sha256sum
  }
}
gateway_snapshot >"${tmp}/gateway-before.json"
cert_snapshot >"${tmp}/cert-before.txt"

service synced-a fixture-a 80 http
k apply -f "${fx}/listenerset.yaml" >/dev/null
route synced-a 80
wait_for 120 "ListenerSet Accepted" condition Accepted -n entei-fixture listenerset/api-zinc
echo "✅ ListenerSet Accepted=True"
wait_for 120 "HTTPRoute Accepted+ResolvedRefs" route_ok api-zinc entei-fixture
echo "✅ HTTPRoute Accepted=True and ResolvedRefs=True"

pf_http=$((http_port + 1)) pf_tls=$((http_port + 2))
# kubectl port-forward exits when the pod refuses a connection; keep one tunnel for both edge ports up.
while true; do
  k -n "${ns}" port-forward service/platinum-edge "${pf_http}:80" "${pf_tls}:443" >>"${tmp}/pf.log" 2>&1
  sleep 1
done &
pf_pid=$!
tls_body() { body_of --cacert "${tmp}/ca.crt" --resolve "${host}:${pf_tls}:127.0.0.1" "https://${host}:${pf_tls}/hostname"; }
serves() { tls_body | rg -q "^$1-"; }
wait_for 120 "exact-host TLS to fixture-a" serves fixture-a
echo "✅ exact-host TLS succeeds through the service/platform wildcard SAN"

service synced-b fixture-b 80 http
route synced-b 80
k -n entei-fixture delete service synced-a --wait >/dev/null
wait_for 120 "route to follow the replaced Service" serves fixture-b
route_ok api-zinc entei-fixture || fail "HTTPRoute lost ResolvedRefs after Service replacement"
echo "✅ route follows the replaced Service"

# The new port reaches fixture-b's second container, which the old config (port 80 -> 8080) cannot.
service synced-b fixture-b 8081 web 9090
route synced-b 8081
wait_for 120 "HTTPRoute Accepted+ResolvedRefs for the named-port change" route_ok api-zinc entei-fixture
web() { for _ in 1 2 3; do [ "$(tls_body)" = fixture-b-web ] || return 1; done; }
wait_for 120 "only the new port's body after the named-port change" web
echo "✅ route follows the named-port change"

k -n entei-fixture delete httproute api-zinc --wait >/dev/null
k -n entei-fixture delete listenerset api-zinc --wait >/dev/null
shared_ok() { [[ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${pf_http}/healthz")" =~ ^2[0-9][0-9]$ ]]; }
# A refused TLS probe restarts the tunnel, so it must serve /healthz again before each probe.
tunnel_up() {
  for _ in 1 2 3 4 5; do
    shared_ok && return 0
    sleep 1
  done
  return 1
}
gone() { tunnel_up && ! tls_body >/dev/null 2>&1; }
wait_for 120 "the per-host listener to disappear" gone
gateway_snapshot >"${tmp}/gateway-after.json"
cert_snapshot >"${tmp}/cert-after.txt"
cmp -s "${tmp}/gateway-before.json" "${tmp}/gateway-after.json" || fail "the shared Gateway was mutated"
cmp -s "${tmp}/cert-before.txt" "${tmp}/cert-after.txt" || fail "the fixture Certificate changed"
[ "$(helm get manifest platinum --kube-context "${ctx}" -n "${ns}" | yq -N 'select(.kind == "Certificate" or .kind == "ListenerSet" or .kind == "Issuer" or .kind == "ClusterIssuer") | .kind' | wc -l)" -eq 0 ] ||
  fail "the ENTEI overlay release owns a Certificate, ListenerSet or issuer"
echo "✅ ENTEI fixture tier passed (shared Gateway unmutated, Certificate untouched)"
