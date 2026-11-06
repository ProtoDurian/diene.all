#!/usr/bin/env bash
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-zinc-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-zinc-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-zinc}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
sulfur_sha="${SULFUR_SHA:-dbeed3c7915065e34896a313006870e579591394}"
namespace=certs
fixture_ns=zinc-fixture
prod=https://acme-v02.api.letsencrypt.org/directory
staging=https://acme-staging-v02.api.letsencrypt.org/directory
zones='["castform.dev.atomi.cloud","eevee.dev.atomi.cloud"]'
eso_crd=tests/fixtures/external-secrets-v2.7.0-externalsecret-crd.yaml.gz
eso_crd_digest=40e62748e37461e3cbe8815a50104c8afdff9f3498ec39d9776338996ee3adb7
helm_k=(--kube-context "k3d-${cluster_name}" --namespace "${namespace}")
k=(kubectl --context "k3d-${cluster_name}")
tmp="$(mktemp -d)"
diagnose() {
  "${k[@]}" get clusterissuers -o yaml || true
  "${k[@]}" get externalsecrets,certificates -A || true
  "${k[@]}" --namespace "${namespace}" get pods -o wide || true
}
cleanup() {
  local status=$?
  [ "${status}" -ne 0 ] && diagnose
  bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

issuer() {
  "${k[@]}" get clusterissuer "$1" -o json |
    jq -c '{server: .spec.acme.server, zones: (.spec.acme.solvers[0].selector.dnsZones // [] | sort), ref: .spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef}'
}
expect_issuer() {
  issuer "$1" | jq -e --arg s "$2" --argjson z "$3" '. == {server: $s, zones: $z, ref: {name: "zinc-secrets", key: "ZINC_CLOUDFLARE_API_TOKEN"}}' >/dev/null ||
    { echo "❌ ClusterIssuer $1 read back differs: $(issuer "$1")" >&2 && exit 1; }
}
expect_absent() {
  "${k[@]}" get clusterissuer "$1" >/dev/null 2>"${tmp}/absent.txt" && { echo "❌ ClusterIssuer $1 still exists" >&2 && exit 1; }
  rg -q 'NotFound' "${tmp}/absent.txt" || { cat "${tmp}/absent.txt" >&2 && echo "❌ reading ClusterIssuer $1 failed for a reason other than NotFound" >&2 && exit 1; }
}
expect_release_owns_no_certificate() {
  helm get manifest zinc "${helm_k[@]}" | yq eval-all -e '[select(.kind == "Certificate" or .kind == "CertificateRequest")] | length == 0' >/dev/null ||
    { echo "❌ the zinc release owns a Certificate" >&2 && exit 1; }
}

# The sulfur chart at its recorded .3 SHA supplies the cert-manager CRDs and webhook.
if [ -n "${SULFUR_DIR:-}" ]; then
  sulfur="${SULFUR_DIR}"
else
  git rev-parse --verify --quiet "${sulfur_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${sulfur_sha}"
  sulfur="${tmp}/sulfur"
  mkdir -p "${sulfur}"
  git archive "${sulfur_sha}" chart tests/fixtures | tar -x -C "${sulfur}"
fi

bash ./scripts/local/create-k3d-cluster.sh

gzip -dc "${sulfur}/tests/fixtures/gateway-api-standard-v1.7.0.yaml.gz" >"${tmp}/gateway-api.yaml"
echo "4e2602c4cbe1afbc394d86f4ac6522e1a5263b01133bba1e40a6d1a549e753a1  ${tmp}/gateway-api.yaml" | sha256sum -c --quiet
"${k[@]}" apply --server-side -f "${tmp}/gateway-api.yaml" >/dev/null
helm install sulfur "${sulfur}/chart" "${helm_k[@]}" --create-namespace --values "${sulfur}/chart/values.example.yaml" --values "${sulfur}/chart/values.lapras.yaml" --wait --wait-for-jobs --timeout 5m
"${k[@]}" wait --for=condition=Established crd/clusterissuers.cert-manager.io crd/certificates.cert-manager.io --timeout=1m
# A stopped controller never contacts Let's Encrypt; the webhook still validates every apply.
"${k[@]}" --namespace "${namespace}" scale deployment/sulfur-cert-manager --replicas=0
"${k[@]}" --namespace "${namespace}" rollout status deployment/sulfur-cert-manager-webhook --timeout=2m
echo "✅ sulfur at ${sulfur_sha} installed: cert-manager CRDs + webhook"

gzip -dc "${eso_crd}" >"${tmp}/eso-crd.yaml"
echo "${eso_crd_digest}  ${tmp}/eso-crd.yaml" | sha256sum -c --quiet
"${k[@]}" apply --server-side -f "${tmp}/eso-crd.yaml" >/dev/null
"${k[@]}" wait --for=condition=Established crd/externalsecrets.external-secrets.io --timeout=1m

helm install zinc chart "${helm_k[@]}" --values chart/values.pikachu.yaml --wait --timeout 3m
expect_issuer zinc-letsencrypt "${prod}" '[]'
"${k[@]}" --namespace "${namespace}" get externalsecret zinc-secrets -o json |
  jq -e '.spec.secretStoreRef == {kind: "SecretStore", name: "certs"} and .spec.target.name == "zinc-secrets"' >/dev/null ||
  { echo "❌ the ExternalSecret zinc-secrets read back differs" >&2 && exit 1; }
expect_release_owns_no_certificate
echo "✅ one plain helm install (pikachu): zinc-letsencrypt on LE production, ExternalSecret applied"

helm upgrade zinc chart "${helm_k[@]}" --values chart/values.pichu.yaml --wait --timeout 3m
expect_issuer zinc-letsencrypt "${staging}" '[]'
echo "✅ pichu: zinc-letsencrypt on LE staging"

helm upgrade zinc chart "${helm_k[@]}" --values chart/values.entei.yaml --wait --timeout 3m
expect_issuer zinc-staging "${staging}" "${zones}"
expect_issuer zinc-production "${prod}" "${zones}"
expect_absent zinc-letsencrypt
expect_release_owns_no_certificate
echo "✅ ENTEI: zinc-staging + zinc-production with the hosted-zone restriction"

"${k[@]}" create namespace "${fixture_ns}"
"${k[@]}" apply -f tests/fixtures/certificates/instance-intents.yaml
"${k[@]}" --namespace "${fixture_ns}" get certificates -o json |
  jq -r '.items[].spec.issuerRef.name' | sort | paste -sd' ' | rg -qx 'zinc-production zinc-staging' ||
  { echo "❌ the fixture Certificates do not reference both ENTEI refs" >&2 && exit 1; }
for ref in zinc-staging zinc-production; do "${k[@]}" get clusterissuer "${ref}" >/dev/null; done
[ "$("${k[@]}" get certificates -A -o json | jq '[.items[] | select(.metadata.namespace != "zinc-fixture")] | length')" = 0 ] ||
  { echo "❌ a Certificate exists outside the test fixture" >&2 && exit 1; }
echo "✅ a materializer-owned instance Certificate references either ENTEI ref; zinc owns none"

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/zinc" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/zinc-0.1.0.tgz"

echo "✅ k3d: sulfur then zinc installed, ClusterIssuers read back, fixture Certificates bind, OCI round-trip passed"
