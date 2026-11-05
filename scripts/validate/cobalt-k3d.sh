#!/usr/bin/env bash
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-cobalt-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-cobalt-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-cobalt}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
namespace=secrets
values=(--values chart/values.example.yaml --values chart/values.lapras.yaml)
helm_k=(--kube-context "k3d-${cluster_name}" --namespace "${namespace}")
k=(kubectl --context "k3d-${cluster_name}")
kc=("${k[@]}" --namespace "${namespace}")
tmp="$(mktemp -d)"
diagnose() {
  "${kc[@]}" get deployments,pods,services -o wide || true
  "${k[@]}" get clustersecretstores -o yaml || true
  "${kc[@]}" logs deployment/cobalt-eso --tail=50 || true
  "${kc[@]}" logs deployment/cobalt-eso-webhook --tail=50 || true
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

helm install cobalt chart "${helm_k[@]}" --create-namespace "${values[@]}" --wait --timeout 5m

for deployment in cobalt-eso cobalt-eso-webhook cobalt-eso-cert-controller; do
  "${kc[@]}" rollout status "deployment/${deployment}" --timeout=3m
done
"${kc[@]}" get pods -l app.kubernetes.io/instance=cobalt -o json |
  jq -e '.items | length >= 3 and all(.[]; .status.phase == "Running" and all(.status.containerStatuses[]; .ready))' >/dev/null ||
  { echo "❌ ESO pods are not all running and ready" >&2 && exit 1; }
echo "✅ ESO controller, webhook and cert-controller healthy"

store_json() {
  local reconciled=false
  for _ in $(seq 1 30); do
    "${k[@]}" get clustersecretstore infisical -o json >"${tmp}/store.json" 2>/dev/null &&
      jq -e '[.status.conditions[]? | select(.type == "Ready")] | length == 1' "${tmp}/store.json" >/dev/null && reconciled=true && break
    sleep 2
  done
  [ "${reconciled}" = true ] || { echo "❌ the store is missing or the ESO controller never reconciled it ($1)" >&2 && exit 1; }
}
store_json install
first_uid="$(jq -r .metadata.uid "${tmp}/store.json")"
jq -e '.apiVersion == "external-secrets.io/v1" and (.spec.provider.infisical.secretsScope | del(.expandSecretReferences)) == {"projectSlug": "sos", "environmentSlug": "example", "secretsPath": "/", "recursive": true} and
  .spec.conditions == [{"namespaceSelector": {"matchLabels": {"atomi.cloud/sos-reader": "true"}}}] and
  .spec.provider.infisical.auth.universalAuthCredentials.clientSecret == {"name": "cobalt-sos-bootstrap", "namespace": "secrets", "key": "clientSecret"}' "${tmp}/store.json" >/dev/null ||
  { echo "❌ the applied ClusterSecretStore differs from the chart" >&2 && cat "${tmp}/store.json" >&2 && exit 1; }
helm get hooks cobalt "${helm_k[@]}" | yq -e 'select(.kind == "ClusterSecretStore") | .metadata.name == "infisical"' >/dev/null ||
  { echo "❌ the store is not a hook of the helm release" >&2 && exit 1; }
"${k[@]}" get crd -o json | jq -e '[.items[] | select(.spec.group | endswith("external-secrets.io"))] | length == 24 and
  all(.[]; .metadata.annotations["helm.sh/resource-policy"] == "keep")' >/dev/null ||
  { echo "❌ the ESO CRDs are not all installed with the keep policy" >&2 && exit 1; }
echo "✅ one plain helm install: CRDs, ESO and the infisical store"

helm upgrade cobalt chart "${helm_k[@]}" "${values[@]}" --wait --timeout 5m
store_json upgrade
[ "$(jq -r .metadata.uid "${tmp}/store.json")" != "${first_uid}" ] || { echo "❌ helm upgrade did not re-apply the store hook" >&2 && exit 1; }
echo "✅ helm upgrade carries the CRDs and the store"

jq '.spec.provider.infisical.secretsScope.unknownField = "x" | del(.metadata.resourceVersion, .metadata.uid, .metadata.managedFields, .status)' "${tmp}/store.json" >"${tmp}/bad-field.json"
if "${k[@]}" replace --dry-run=server --validate=strict -f "${tmp}/bad-field.json" >"${tmp}/bad-field.txt" 2>&1; then
  echo "❌ the API server accepted a store with an unknown field" >&2 && exit 1
fi
rg -q 'unknown field' "${tmp}/bad-field.txt" || { cat "${tmp}/bad-field.txt" >&2 && echo "❌ the unknown-field store was rejected for another reason" >&2 && exit 1; }
jq 'del(.spec.provider.infisical.secretsScope.environmentSlug) | del(.metadata.resourceVersion, .metadata.uid, .metadata.managedFields, .status)' "${tmp}/store.json" >"${tmp}/no-env.json"
if "${k[@]}" replace --dry-run=server -f "${tmp}/no-env.json" >"${tmp}/no-env.txt" 2>&1; then
  echo "❌ the API server accepted a store without environmentSlug" >&2 && exit 1
fi
rg -q 'environmentSlug' "${tmp}/no-env.txt" || { cat "${tmp}/no-env.txt" >&2 && echo "❌ the store without environmentSlug was rejected for another reason" >&2 && exit 1; }
echo "✅ ClusterSecretStore infisical is schema-valid (Ready needs a live Infisical)"

"${k[@]}" get --raw /apis/external-secrets.io/v1beta1 >/dev/null 2>&1 && echo "❌ external-secrets.io/v1beta1 is served" >&2 && exit 1
echo "✅ external-secrets.io/v1beta1 is not served"

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/cobalt" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/cobalt-0.1.0.tgz"

echo "✅ k3d install, ESO healthy, store applied + schema-valid, OCI round-trip passed"
