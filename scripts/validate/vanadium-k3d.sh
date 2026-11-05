#!/usr/bin/env bash
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-vanadium-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-vanadium-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-vanadium}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
context="k3d-${cluster_name}"
namespace=admission
fixtures=tests/vap
kc=(kubectl --context "${context}")
tmp="$(mktemp -d)"
# The API rejects or strips these before admission runs, so only the unit tier proves them.
api_invalid='pod-ephemeral-|container-host-process|disallowPrivileged/|disallowProcMount/'
cleanup() {
  local status=$?
  if [ "${status}" -ne 0 ]; then
    "${kc[@]}" get validatingadmissionpolicies,validatingadmissionpolicybindings || true
    "${kc[@]}" get namespaces --show-labels || true
  fi
  bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

policy_of() { printf 'vanadium-%s' "$(basename "$(dirname "$1")" | tr '[:upper:]' '[:lower:]')"; }

# dry_run <fixture>: a server-side dry-run create; stderr (warnings, denials) goes to ${tmp}/out.txt.
dry_run() { "${kc[@]}" create --dry-run=server -f "$1" -o name >/dev/null 2>"${tmp}/out.txt"; }

vap_check_total() {
  "${kc[@]}" get --raw /metrics |
    awk -v p="$1" -v a="$2" '/^apiserver_validating_admission_policy_check_total[{]/ && index($0, "policy=\"" p "\"") && index($0, "enforcement_action=\"" a "\"") { sum += $NF } END { print sum + 0 }'
}

# wait_for <posture>: policies and namespace labels take effect asynchronously.
wait_for() {
  local posture="$1" fixture="$2"
  for _ in $(seq 1 60); do
    case "${posture}" in
    warn) dry_run "${fixture}" && rg -q "Warning: .*$(policy_of "${fixture}")" "${tmp}/out.txt" && return 0 ;;
    deny) ! dry_run "${fixture}" && rg -q "ValidatingAdmissionPolicy '$(policy_of "${fixture}")'" "${tmp}/out.txt" && return 0 ;;
    exempt) dry_run "${fixture}" && ! rg -q 'vanadium-' "${tmp}/out.txt" && return 0 ;;
    esac
    sleep 2
  done
  echo "❌ ${posture} posture never took effect for ${fixture}" >&2 && cat "${tmp}/out.txt" >&2 && return 1
}

# A landscape overlay changes what landscapeMatch accepts; swap example and $1 in a copy of the fixtures.
restamp() {
  local landscape="$1" out="${tmp}/fixtures-$1"
  rm -rf "${out}" && mkdir -p "${out}" && cp -r "${fixtures}/." "${out}/"
  find "${out}" -name '*.yaml' -exec sed -i -E \
    -e 's#(atomi\.cloud/landscape: )example$#\1@@#' -e "s#(atomi\\.cloud/landscape: )${landscape}\$#\\1example#" -e "s#(atomi\\.cloud/landscape: )@@\$#\\1${landscape}#" {} +
  echo "${out}"
}

mapfile -t bad < <(find "${fixtures}/bad" -name '*.yaml' | LC_ALL=C sort | rg -v "${api_invalid}")
mapfile -t good < <(find "${fixtures}/good" -name '*.yaml' | LC_ALL=C sort)
want_policies="$(yq -r '.policies | to_entries | map(select(.value.enabled)) | .[].key' chart/values.yaml | wc -l)"

bash ./scripts/local/create-k3d-cluster.sh
minor="$("${kc[@]}" version -o json | jq -r '.serverVersion.minor | sub("[^0-9]"; ""; "g")')"
[ "${minor}" -ge 30 ] || { echo "❌ k8s server 1.${minor} < 1.30" >&2 && exit 1; }
echo "k8s server: $("${kc[@]}" version -o json | jq -r '.serverVersion.gitVersion')"
for ns in $(yq -N -r '.metadata.namespace' "${bad[@]}" "${good[@]}" | sort -u); do
  "${kc[@]}" create namespace "${ns}" >/dev/null
done

# Audit landscape: every policy and binding installs; violations are admitted with a warning.
helm upgrade --install vanadium chart --kube-context "${context}" --namespace "${namespace}" --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
for kind in validatingadmissionpolicies validatingadmissionpolicybindings; do
  got="$("${kc[@]}" get "${kind}" -l app.kubernetes.io/instance=vanadium -o name | wc -l)"
  [ "${got}" -eq "${want_policies}" ] || { echo "❌ ${got} ${kind}, want ${want_policies}" >&2 && exit 1; }
done
probe="${fixtures}/bad/disallowLatest/latest-tag.yaml"
wait_for warn "${probe}"

before="$(vap_check_total vanadium-disallowlatest warn)"
"${kc[@]}" apply -f "${probe}" 2>"${tmp}/apply.txt" >/dev/null
rg -q "Warning: Validation failed for ValidatingAdmissionPolicy 'vanadium-disallowlatest'" "${tmp}/apply.txt" ||
  { echo "❌ the warn-mode apply returned no VAP warning" >&2 && cat "${tmp}/apply.txt" >&2 && exit 1; }
"${kc[@]}" delete -f "${probe}" --wait=false >/dev/null
after="$(vap_check_total vanadium-disallowlatest warn)"
[ "${after}" -gt "${before}" ] || { echo "❌ apiserver_validating_admission_policy_check_total{warn} did not increase (${before} -> ${after})" >&2 && exit 1; }
echo "✅ warn: violation admitted with an API warning; VAP check metric ${before} -> ${after}"

errors=0
# miss <reason>: record a failed fixture and keep going so one run reports them all.
miss() {
  echo "❌ $1" >&2 && sed 's/^/   /' "${tmp}/out.txt" >&2
  errors=$((errors + 1))
}
phase_done() { [ "${errors}" -eq 0 ] || { echo "❌ ${errors} fixture(s) failed the $1 phase" >&2 && exit 1; }; }

for fixture in "${bad[@]}"; do
  if ! dry_run "${fixture}"; then
    miss "audit landscape blocked ${fixture}"
  elif ! rg -q "Warning: .*'$(policy_of "${fixture}")'" "${tmp}/out.txt"; then
    miss "${fixture} returned no $(policy_of "${fixture}") warning"
  fi
done
phase_done warn
echo "✅ warn: ${#bad[@]} violations each warned by their own policy"

# Deny landscape. kube-system is exempt by label (sodium's kube-system exclude).
"${kc[@]}" label namespace kube-system atomi.cloud/policy-exempt=true --overwrite >/dev/null
helm upgrade vanadium chart --kube-context "${context}" --namespace "${namespace}" \
  --values chart/values.serving.yaml --values chart/values.lapras.yaml --wait --timeout 5m
serving="$(restamp serving)"
wait_for deny "${serving}/bad/disallowLatest/latest-tag.yaml"
before="$(vap_check_total vanadium-disallowlatest deny)"
for fixture in "${bad[@]}"; do
  f="${serving}/${fixture#"${fixtures}/"}"
  if dry_run "${f}"; then
    miss "deny landscape admitted ${fixture}"
  elif ! rg -q "ValidatingAdmissionPolicy '$(policy_of "${f}")' with binding '$(policy_of "${f}")' denied request" "${tmp}/out.txt"; then
    miss "${fixture} was not denied by $(policy_of "${f}")"
  fi
done
for fixture in "${good[@]}"; do
  if ! dry_run "${serving}/${fixture#"${fixtures}/"}"; then
    miss "deny landscape rejected good ${fixture}"
  elif rg -q 'vanadium-' "${tmp}/out.txt"; then
    miss "good ${fixture} drew a vanadium warning"
  fi
done
phase_done deny
after="$(vap_check_total vanadium-disallowlatest deny)"
[ "${after}" -gt "${before}" ] || { echo "❌ apiserver_validating_admission_policy_check_total{deny} did not increase" >&2 && exit 1; }
echo "✅ deny: ${#bad[@]} violations each denied by their own policy; ${#good[@]} good fixtures admitted; deny metric ${before} -> ${after}"

# The same violating manifests, admitted once their namespace carries the exemption label.
for ns in $(yq -N -r '.metadata.namespace' "${bad[@]}" | sort -u); do
  "${kc[@]}" label namespace "${ns}" atomi.cloud/policy-exempt=true --overwrite >/dev/null
done
wait_for exempt "${serving}/bad/disallowLatest/latest-tag.yaml"
for fixture in "${bad[@]}"; do
  dry_run "${serving}/${fixture#"${fixtures}/"}" || miss "exempt namespace rejected ${fixture}"
done
phase_done exempt
echo "✅ exempt: ${#bad[@]} denied manifests admitted in exempt namespaces"

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/vanadium" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/vanadium-0.1.0.tgz"

echo "✅ k3d install, warn + metric, deny, exemption and OCI round-trip passed"
