#!/usr/bin/env bash
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-chlorine-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-chlorine-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-chlorine}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
namespace=reloader
fixture_ns=chlorine-fixture
values=(--values chart/values.example.yaml --values chart/values.lapras.yaml)
helm_k=(--kube-context "k3d-${cluster_name}" --namespace "${namespace}")
k=(kubectl --context "k3d-${cluster_name}")
kc=("${k[@]}" --namespace "${namespace}")
kf=("${k[@]}" --namespace "${fixture_ns}")
tmp="$(mktemp -d)"
diagnose() {
  "${kc[@]}" get deployments,pods -o wide || true
  "${kf[@]}" get deployments,replicasets,pods,secrets -o wide || true
  "${kc[@]}" logs deployment/chlorine-reloader --tail=80 || true
}
cleanup() {
  local status=$?
  [ "${status}" -ne 0 ] && diagnose
  bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

fixture() {
  local name="$1" annotate="$2"
  cat <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: ${name}-secret
stringData:
  token: before
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  annotations: {${annotate}}
spec:
  replicas: 1
  selector:
    matchLabels: {app: ${name}}
  template:
    metadata:
      labels: {app: ${name}}
    spec:
      securityContext: {runAsNonRoot: true, runAsUser: 65534}
      containers:
        - name: ${name}
          image: registry.k8s.io/pause:3.10
          envFrom: [{secretRef: {name: ${name}-secret}}]
          resources:
            requests: {cpu: 5m, memory: 8Mi}
            limits: {cpu: 50m, memory: 32Mi}
YAML
}

state() {
  local pod rs
  pod="$("${kf[@]}" get pods -l "app=$1" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.uid}')"
  rs="$("${kf[@]}" get replicasets -l "app=$1" -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sort | tr '\n' ' ')"
  printf '%s|%s' "${pod}" "${rs}"
}

rotate() {
  "${kf[@]}" create secret generic "$1-secret" --from-literal=token=after --dry-run=client -o yaml | "${kf[@]}" apply -f - >/dev/null
}

bash ./scripts/local/create-k3d-cluster.sh
helm dependency build chart

helm install chlorine chart "${helm_k[@]}" --create-namespace "${values[@]}" --wait --timeout 5m
"${kc[@]}" rollout status deployment/chlorine-reloader --timeout=3m
"${kc[@]}" get pods -l app=chlorine-reloader -o json |
  jq -e '.items | length == 1 and all(.[]; .status.phase == "Running" and all(.status.containerStatuses[]; .ready and .restartCount == 0))' >/dev/null ||
  { echo "❌ the Reloader controller pod is not running and ready" >&2 && exit 1; }
"${kc[@]}" get deployment chlorine-reloader -o json |
  jq -e '(.spec.template.spec.containers[0].args // []) | all(.[]; test("^--auto-reload-all") | not)' >/dev/null ||
  { echo "❌ the live Reloader runs with auto-reload-all" >&2 && exit 1; }
echo "✅ one plain helm install --wait: Reloader healthy, annotation opt-in"

"${k[@]}" create namespace "${fixture_ns}"
fixture annotated 'reloader.stakater.com/auto: "true"' | "${kf[@]}" apply -f -
fixture quiet '' | "${kf[@]}" apply -f -
for d in annotated quiet; do "${kf[@]}" rollout status "deployment/${d}" --timeout=2m; done
annotated_before="$(state annotated)"
quiet_before="$(state quiet)"
one='^[0-9a-f-]{36}[|][^ ]+ $'
[[ ${annotated_before} =~ ${one} && ${quiet_before} =~ ${one} ]] ||
  { echo "❌ fixture baseline is not one running pod and one ReplicaSet each (${annotated_before} / ${quiet_before})" >&2 && exit 1; }

# Rotate quiet first: once annotated restarts, Reloader has already handled quiet's event.
rotate quiet
rotate annotated
restarted=false
for _ in $(seq 1 60); do
  now="$(state annotated)"
  if [ "${now%%|*}" != "${annotated_before%%|*}" ] && [ -n "${now%%|*}" ] && [ "${now#*|}" != "${annotated_before#*|}" ]; then
    restarted=true
    break
  fi
  sleep 3
done
[ "${restarted}" = true ] || { echo "❌ Reloader did not restart the annotated Deployment within 180s of its Secret change (${annotated_before} -> $(state annotated))" >&2 && exit 1; }
"${kf[@]}" get deployment annotated -o json |
  jq -e '.spec.template.metadata.annotations // {} | keys | any(startswith("reloader.stakater.com/"))' >/dev/null ||
  { echo "❌ the annotated Deployment rolled without a Reloader pod-template annotation" >&2 && exit 1; }
echo "✅ Secret change -> annotated Deployment restarted (new ReplicaSet, new pod UID)"

sleep 15
quiet_after="$(state quiet)"
[ "${quiet_after}" = "${quiet_before}" ] || { echo "❌ Reloader restarted the un-annotated Deployment (${quiet_before} -> ${quiet_after})" >&2 && exit 1; }
echo "✅ Secret change -> un-annotated Deployment untouched (same ReplicaSet and pod UID)"

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/chlorine" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/chlorine-0.1.0.tgz"

echo "✅ k3d install, Reloader healthy, opt-in restart proven, OCI round-trip passed"
