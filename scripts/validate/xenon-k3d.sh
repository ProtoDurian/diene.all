#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:-canary-xenon}"
registry_name="${K3D_REGISTRY_NAME:-canary-xenon-registry}"
registry_port="${K3D_REGISTRY_PORT:-5002}"
if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  cluster_name="canary-xenon-${isolation_key}"
  registry_name="canary-xenon-registry-${isolation_key}"
  registry_port="$((20000 + (16#${isolation_key:0:4} % 10000)))"
fi
namespace=metrics
values=(--values chart/values.serving.yaml --values chart/values.canary.yaml)
k=(kubectl --context "k3d-${cluster_name}")
kc=("${k[@]}" --namespace "${namespace}")
top_timeout="${TOP_TIMEOUT_SECONDS:-240}"
tmp="$(mktemp -d)"
export HELM_REPOSITORY_CONFIG="${tmp}/repositories.yaml" HELM_REPOSITORY_CACHE="${tmp}/repository-cache"
diagnose() {
  "${kc[@]}" get deployments,pods,services -o wide || true
  "${k[@]}" get apiservice v1beta1.metrics.k8s.io -o yaml || true
  "${kc[@]}" logs deployment/xenon-metrics --tail=80 || true
}
cleanup() {
  local status=$?
  [ "${status}" -ne 0 ] && diagnose
  k3d cluster delete "${cluster_name}" >/dev/null 2>&1 || true
  k3d registry delete "k3d-${registry_name}" >/dev/null 2>&1 || true
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

export K3D_CLUSTER_NAME="${cluster_name}" K3D_REGISTRY_NAME="${registry_name}" K3D_REGISTRY_PORT="${registry_port}"
yq eval '.metadata.name = strenv(K3D_CLUSTER_NAME) | .registries.create.name = strenv(K3D_REGISTRY_NAME) | .registries.create.hostPort = strenv(K3D_REGISTRY_PORT)' \
  infra/k3d.canary-xenon.yaml >"${tmp}/k3d.yaml"
k3d cluster create --config "${tmp}/k3d.yaml" --wait
"${k[@]}" wait --for=condition=Ready nodes --all --timeout=3m

# Precondition: no Resource Metrics API provider before xenon.
if "${k[@]}" get apiservice v1beta1.metrics.k8s.io >"${tmp}/pre.txt" 2>&1; then
  cat "${tmp}/pre.txt" >&2
  echo "❌ v1beta1.metrics.k8s.io already exists before install (the fixture cluster bundles a provider)" >&2 && exit 1
fi
rg -q 'NotFound' "${tmp}/pre.txt" || { cat "${tmp}/pre.txt" >&2 && echo "❌ could not prove the metrics API is absent" >&2 && exit 1; }
if "${k[@]}" top nodes >/dev/null 2>&1; then echo "❌ kubectl top answers before xenon is installed" >&2 && exit 1; fi
echo "✅ no Resource Metrics API before install"

helm repo add metrics-server "$(yq -r '.dependencies[] | select(.name == "metrics-server") | .repository' chart/Chart.yaml)" >/dev/null
helm dependency build chart
helm install xenon chart --kube-context "k3d-${cluster_name}" --namespace "${namespace}" --create-namespace "${values[@]}" --wait --timeout 5m
"${kc[@]}" rollout status deployment/xenon-metrics --timeout=3m
"${k[@]}" get apiservice v1beta1.metrics.k8s.io -o json |
  jq -e --arg ns "${namespace}" '.spec.service == {name: "xenon-metrics", namespace: $ns, port: 443}' >/dev/null ||
  { echo "❌ v1beta1.metrics.k8s.io is not served by xenon-metrics in ${namespace}" >&2 && exit 1; }

deadline=$((SECONDS + top_timeout))
until "${k[@]}" top nodes --no-headers >"${tmp}/top.txt" 2>"${tmp}/top.err" && [ -s "${tmp}/top.txt" ]; do
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    cat "${tmp}/top.err" >&2
    echo "❌ kubectl top nodes did not answer within ${top_timeout}s" >&2 && exit 1
  fi
  sleep 5
done
cat "${tmp}/top.txt"
awk 'NF >= 5 && $2 ~ /^[0-9]+m$/ && $4 ~ /^[0-9]+Mi$/ { ok = 1 } END { exit !ok }' "${tmp}/top.txt" ||
  { echo "❌ kubectl top nodes answered without CPU/memory figures" >&2 && exit 1; }
"${kc[@]}" get apiservice v1beta1.metrics.k8s.io -o json | jq -e '.status.conditions[] | select(.type == "Available") | .status == "True"' >/dev/null ||
  { echo "❌ v1beta1.metrics.k8s.io is not Available" >&2 && exit 1; }
"${kc[@]}" get pods -l app.kubernetes.io/instance=xenon -o json | jq -e '.items | length == 1 and all(.[]; all(.status.containerStatuses[]; .ready and .restartCount == 0))' >/dev/null ||
  { echo "❌ the metrics-server pod is not ready or restarted" >&2 && exit 1; }
echo "✅ kubectl top nodes answers through xenon"

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/xenon" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/xenon-0.1.0.tgz"

echo "✅ canary-xenon install, kubectl top, and local OCI round-trip passed"
