#!/usr/bin/env bash
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-sulfur-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-sulfur-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-sulfur}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
namespace=certs
fixture_ns=sulfur-fixture
values=(--values chart/values.example.yaml --values chart/values.lapras.yaml)
helm_k=(--kube-context "k3d-${cluster_name}" --namespace "${namespace}")
k=(kubectl --context "k3d-${cluster_name}")
kc=("${k[@]}" --namespace "${namespace}")
tmp="$(mktemp -d)"
diagnose() {
  "${kc[@]}" get deployments,pods,services,jobs -o wide || true
  "${k[@]}" --namespace "${fixture_ns}" get issuers,certificates,certificaterequests -o yaml || true
  for d in sulfur-cert-manager sulfur-cert-manager-webhook sulfur-cert-manager-cainjector; do
    "${kc[@]}" logs "deployment/${d}" --tail=50 || true
  done
}
cleanup() {
  local status=$?
  [ "${status}" -ne 0 ] && diagnose
  bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

bash ./scripts/local/create-k3d-cluster.sh
helm dependency build chart

helm install sulfur chart "${helm_k[@]}" --create-namespace "${values[@]}" --wait --wait-for-jobs --timeout 5m

for deployment in sulfur-cert-manager sulfur-cert-manager-cainjector sulfur-cert-manager-webhook; do
  "${kc[@]}" rollout status "deployment/${deployment}" --timeout=3m
done
"${kc[@]}" get pods -l app.kubernetes.io/instance=sulfur,app.kubernetes.io/component -o json |
  jq -e '[.items[] | select(.metadata.labels["app.kubernetes.io/component"] != "startupapicheck")] |
    length == 3 and all(.[]; .status.phase == "Running" and all(.status.containerStatuses[]; .ready))' >/dev/null ||
  { echo "❌ cert-manager controller, cainjector and webhook are not all running and ready" >&2 && exit 1; }
echo "✅ cert-manager controller, cainjector and webhook healthy (startupapicheck passed in the install)"

"${k[@]}" get crd -o json | jq -e '[.items[] | select(.spec.group | test("(^|\\.)cert-manager\\.io$"))] | length == 6 and
  all(.[]; .metadata.annotations["helm.sh/resource-policy"] == "keep")' >/dev/null ||
  { echo "❌ the six cert-manager CRDs are not all installed with the keep policy" >&2 && exit 1; }
"${kc[@]}" get configmap sulfur-cert-manager -o json | jq -r '.data["config.yaml"]' | yq -e '.enableGatewayAPI == true' >/dev/null ||
  { echo "❌ the live controller config does not enable Gateway API" >&2 && exit 1; }
echo "✅ one plain helm install: CRDs kept, Gateway API enabled"

"${k[@]}" create namespace "${fixture_ns}"
"${k[@]}" --namespace "${fixture_ns}" apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: fixture-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: fixture-cert
spec:
  secretName: fixture-cert-tls
  commonName: fixture.sulfur.example.invalid
  dnsNames: [fixture.sulfur.example.invalid]
  duration: 24h
  issuerRef:
    name: fixture-selfsigned
    kind: Issuer
YAML
"${k[@]}" --namespace "${fixture_ns}" wait --for=condition=Ready issuer/fixture-selfsigned --timeout=2m
"${k[@]}" --namespace "${fixture_ns}" wait --for=condition=Ready certificate/fixture-cert --timeout=3m
"${k[@]}" --namespace "${fixture_ns}" get secret fixture-cert-tls -o json | jq -r '.data["tls.crt"]' | base64 -d >"${tmp}/tls.crt"
openssl x509 -in "${tmp}/tls.crt" -noout -ext subjectAltName | rg -q 'DNS:fixture\.sulfur\.example\.invalid' ||
  { echo "❌ the issued certificate does not carry the requested SAN" >&2 && exit 1; }
echo "✅ self-signed Issuer + Certificate reached Ready=True and the TLS Secret carries the SAN"

helm get manifest sulfur "${helm_k[@]}" | yq -e '[select(.kind == "Issuer" or .kind == "ClusterIssuer")] | length == 0' >/dev/null ||
  { echo "❌ the sulfur release owns an Issuer/ClusterIssuer" >&2 && exit 1; }

helm upgrade sulfur chart "${helm_k[@]}" "${values[@]}" --wait --timeout 5m
"${k[@]}" --namespace "${fixture_ns}" wait --for=condition=Ready certificate/fixture-cert --timeout=1m
echo "✅ helm upgrade keeps the engine and the issued Certificate"

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/sulfur" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/sulfur-0.1.0.tgz"

echo "✅ k3d install, cert-manager healthy, self-signed Certificate Ready, OCI round-trip passed"
