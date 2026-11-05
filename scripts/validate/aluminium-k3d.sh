#!/usr/bin/env bash
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-aluminium-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-aluminium-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-aluminium}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
namespace=telemetry
kc=(kubectl --context "k3d-${cluster_name}" --namespace "${namespace}")
tmp="$(mktemp -d)"
forward_pid=""
diagnose() {
  "${kc[@]}" get alloy,pods,statefulsets,daemonsets,services -o wide || true
  "${kc[@]}" logs deployment/aluminium-alloy-operator --tail=100 || true
}
cleanup() {
  local status=$?
  [ "${status}" -ne 0 ] && diagnose
  [ -n "${forward_pid}" ] && { kill "${forward_pid}" 2>/dev/null || true; }
  bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

bash ./scripts/local/create-k3d-cluster.sh
helm dependency build chart
helm upgrade --install aluminium chart --kube-context "k3d-${cluster_name}" --namespace "${namespace}" --create-namespace --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
"${kc[@]}" wait --for=condition=Available deployment/aluminium-alloy-operator --timeout=3m

# The operator materializes the collector workloads from the Alloy CRs after install.
for _ in $(seq 1 60); do
  "${kc[@]}" get statefulset/aluminium-alloy-metrics daemonset/aluminium-alloy-logs >/dev/null 2>&1 && break
  sleep 5
done
"${kc[@]}" rollout status statefulset/aluminium-alloy-metrics --timeout=5m
"${kc[@]}" rollout status daemonset/aluminium-alloy-logs --timeout=5m

"${kc[@]}" get statefulset/aluminium-alloy-metrics -o json | jq -e '[.spec.template.spec.containers[] | select(.name == "alloy") | .args[]] | any(. == "--cluster.enabled=true")' >/dev/null ||
  { echo "❌ alloy-metrics is not clustered" >&2 && exit 1; }
"${kc[@]}" get daemonset/aluminium-alloy-logs -o json | jq -e '[.spec.template.spec.containers[] | select(.name == "alloy") | .args[]] | all(. != "--cluster.enabled=true")' >/dev/null ||
  { echo "❌ alloy-logs is clustered" >&2 && exit 1; }
"${kc[@]}" get pods -l app.kubernetes.io/instance=aluminium-alloy-metrics -o json | jq -e '.items | length > 0 and all(.[]; .status.phase == "Running")' >/dev/null
"${kc[@]}" get pods -l app.kubernetes.io/instance=aluminium-alloy-logs -o json | jq -e '.items | length > 0 and all(.[]; .status.phase == "Running")' >/dev/null

# shellcheck disable=SC2016 # expands inside the pod
"${kc[@]}" exec daemonset/aluminium-alloy-logs -c alloy -- sh -c 'f="$(find /var/log/pods -name "*.log" -type f | head -n 1)"; [ -n "$f" ] && head -c 1 "$f" >/dev/null' ||
  { echo "❌ alloy-logs cannot read /var/log/pods" >&2 && exit 1; }
logs_pod="$("${kc[@]}" get pods -l app.kubernetes.io/instance=aluminium-alloy-logs -o jsonpath='{.items[0].metadata.name}')"
tailed=""
for _ in $(seq 1 30); do
  tailed="$(kubectl --context "k3d-${cluster_name}" get --raw "/api/v1/namespaces/${namespace}/pods/${logs_pod}:12345/proxy/metrics" | rg '^otelcol_receiver_accepted_log_records_total\{.* [1-9]' || true)"
  [ -n "${tailed}" ] && break
  sleep 5
done
if [ -z "${tailed}" ]; then
  echo "❌ alloy-logs accepted no pod log records" >&2
  kubectl --context "k3d-${cluster_name}" get --raw "/api/v1/namespaces/${namespace}/pods/${logs_pod}:12345/proxy/metrics" | rg 'log_records|filelog' >&2 || true
  exit 1
fi
echo "✅ alloy-logs tails pod logs"

"${kc[@]}" port-forward service/aluminium-alloy-metrics :4318 >"${tmp}/forward.log" 2>&1 &
forward_pid=$!
port=""
for _ in $(seq 1 30); do
  port="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9]*\) -> 4318$/\1/p' "${tmp}/forward.log" | head -n 1)"
  [ -n "${port}" ] && break
  sleep 1
done
[ -z "${port}" ] && echo "❌ no port-forward to alloy-metrics :4318" >&2 && cat "${tmp}/forward.log" >&2 && exit 1

# One OTLP span and one OTLP log record, protobuf-encoded.
printf '%s' 'Ck4STBJKChABAgMEBQYHCAkKCwwNDg8QEggBAgMEBQYHCCoYYWx1bWluaXVtLWszZC1wcm9vZi1zcGFuMAE5AEBTbuaU4xdBQIJibuaU4xc=' | base64 --decode >"${tmp}/traces.pb"
printf '%s' 'ClUSUxJRCQBAU27mlOMXEAkaBElORk8qGQoXYWx1bWluaXVtIGszZCBwcm9vZiBsb2dKEAECAwQFBgcICQoLDA0ODxBSCAECAwQFBgcIWQBAU27mlOMX' | base64 --decode >"${tmp}/logs.pb"
for signal in traces logs; do
  code="$(curl --silent --show-error --max-time 30 --output /dev/null --write-out '%{http_code}' --header 'Content-Type: application/x-protobuf' --data-binary "@${tmp}/${signal}.pb" "http://127.0.0.1:${port}/v1/${signal}")"
  [ "${code}" != 200 ] && echo "❌ OTLP ${signal} returned HTTP ${code}" >&2 && exit 1
  echo "✅ OTLP/HTTP ${signal} accepted on :4318"
done

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/aluminium" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/aluminium-0.1.0.tgz"

echo "✅ k3d install, both collectors healthy, OTLP span/log accepted, OCI round-trip passed"
