#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-vanadium}"
namespace="${NAMESPACE:-admission}"
fixtures=tests/vap
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

# landscape overlay -> expected posture; a new landscape overlay must be added here.
declare -A posture=([example]=audit [serving]=deny)
stacks=(
  "--values chart/values.example.yaml"
  "--values chart/values.example.yaml --values chart/values.lapras.yaml"
  "--values chart/values.serving.yaml"
  "--values chart/values.serving.yaml --values chart/values.lapras.yaml"
)

render() {
  # shellcheck disable=SC2086
  helm template "${release}" chart --namespace "${namespace}" $1 "${@:2}"
}

json() { yq eval-all -o=json '.' "$1" | jq -s 'map(select(.kind != null))'; }

# merged <stack>: values.yaml with the stack's overlays deep-merged, as helm sees them.
merged() {
  # shellcheck disable=SC2016,SC2086
  yq eval-all '. as $item ireduce ({}; . * $item)' chart/values.yaml ${1//--values /}
}

# need <reason> <cmd...>: a failed check names its reason so negative fixtures can match it.
need() {
  local reason="$1"
  shift
  "$@" >/dev/null 2>&1 || { echo "❌ ${reason}" >&2 && return 1; }
}

# expect_red <pattern> <cmd...>: the command must fail and print the pattern.
expect_red() {
  local pattern="$1"
  shift
  if "$@" >"${tmp}/red.txt" 2>&1; then
    echo "❌ accepted: $*" >&2 && exit 1
  fi
  rg -q -- "${pattern}" "${tmp}/red.txt" || { echo "❌ wrong refusal for $* (wanted '${pattern}')" >&2 && cat "${tmp}/red.txt" >&2 && exit 1; }
}

# definitions <render> <out>: only the ValidatingAdmissionPolicy objects, never their bindings.
definitions() { yq eval-all 'select(.kind == "ValidatingAdmissionPolicy")' "$1" >"$2"; }

# failed_policies <defs> <resource>: sorted names of the policies the resource fails.
failed_policies() {
  kyverno apply "$1" --resource "$2" --remove-color >"${tmp}/apply.txt" 2>&1 || true
  rg -q '^pass: [0-9]+, fail: [0-9]+, warn: 0, error: 0, skip: [0-9]+' "${tmp}/apply.txt" ||
    { echo "❌ kyverno did not evaluate $2 cleanly" >&2 && cat "${tmp}/apply.txt" >&2 && return 1; }
  sed -n 's/^policy \([^ ]*\) -> resource .* failed:$/\1/p' "${tmp}/apply.txt" | sort -u | paste -sd' ' -
}

policy_name() { printf 'vanadium-%s' "${1,,}"; }

enabled_policies() { yq -r '.policies | to_entries | map(select(.value.enabled)) | .[].key' chart/values.yaml; }

check_bad_fixtures() {
  local defs="$1" dir policy got want
  for dir in "${fixtures}"/bad/*/; do
    policy="$(basename "${dir}")"
    want="$(policy_name "${policy}")"
    for fixture in "${dir}"*.yaml; do
      got="$(failed_policies "${defs}" "${fixture}")"
      [ "${got}" = "${want}" ] || { echo "❌ ${fixture} must fail exactly ${want}, failed [${got}]" >&2 && return 1; }
    done
  done
}

check_good_fixtures() {
  local defs="$1" got
  for fixture in "${fixtures}"/good/*.yaml; do
    got="$(failed_policies "${defs}" "${fixture}")"
    [ -z "${got}" ] || { echo "❌ good fixture ${fixture} failed [${got}]" >&2 && return 1; }
  done
}

case "${mode}" in
schema)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack} >"${tmp}/schema.txt" 2>&1 ||
      { echo "❌ schema rejected the stack '${stack}'" >&2 && cat "${tmp}/schema.txt" >&2 && exit 1; }
  done
  for bad in enforcement=block 'policies.disallowLatest.actions={Block}' exemptionLabel=Bad_Label policies.disallowLatest.enabled=maybe 'policies.disallowLatest.actions={Audit,Audit}'; do
    expect_red "don't meet the specifications of the schema" helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --set "${bad}"
  done
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack}
  done
  ;;
render)
  for stack in "${stacks[@]}"; do
    render "${stack}" >/dev/null
  done
  expect_red 'serviceTree.landscape is required' render ""
  expect_red 'must equal release namespace' render "${stacks[0]}" --set serviceTree.platform=other
  expect_red 'must be absolute with no \.\.' render "${stacks[0]}" --set 'policies.restrictVolumeTypes.hostPathCarveOut.paths={/var/log/..}'
  expect_red 'no template "vanadium.policy.unknownRule"' render "${stacks[0]}" --set policies.unknownRule.enabled=true
  ;;
lpsm-labels)
  for stack in "${stacks[@]}"; do
    render "${stack}" >"${tmp}/labels.yaml"
    landscape="$(merged "${stack}" | yq -r '.serviceTree.landscape // ""')"
    cluster="$(merged "${stack}" | yq -r '.serviceTree.cluster // ""')"
    json "${tmp}/labels.yaml" | jq -e --arg l "${landscape}" --arg c "${cluster}" '
      ({"atomi.cloud/platform": "admission", "atomi.cloud/service": "vanadium", "atomi.cloud/module": "policies", "atomi.cloud/layer": "1", "atomi.cloud/landscape": $l}
        + (if $c == "" then {} else {"atomi.cloud/cluster": $c} end)) as $want |
      length > 0 and all(.[]; .metadata.labels as $m | .metadata.annotations as $a |
        all($want | to_entries[]; $m[.key] == .value and $a[.key] == .value))' >/dev/null ||
      { echo "❌ an object in '${stack}' lacks the LPSM labels/annotations" >&2 && exit 1; }
  done
  render "${stacks[1]}" --set labelPrefix=example.dev >"${tmp}/override.yaml"
  json "${tmp}/override.yaml" | jq -e 'length > 0 and all(.[];
      .metadata.labels["example.dev/platform"] == "admission" and .metadata.annotations["example.dev/service"] == "vanadium" and
      .metadata.labels["atomi.cloud/platform"] == null and .metadata.annotations["atomi.cloud/service"] == null)' >/dev/null ||
    { echo "❌ labelPrefix does not drive every label and annotation" >&2 && exit 1; }
  yq eval-all 'select(.kind == "ValidatingAdmissionPolicy")' "${tmp}/override.yaml" >"${tmp}/override-defs.yaml"
  rg -q "'example.dev/landscape'" "${tmp}/override-defs.yaml" || { echo "❌ labelPrefix does not drive the policy keys" >&2 && exit 1; }
  if rg -q 'atomi\.cloud' "${tmp}/override-defs.yaml"; then
    echo "❌ a policy hard-codes atomi.cloud" >&2 && exit 1
  fi
  ;;
names)
  render "${stacks[0]}" >"${tmp}/names.yaml"
  json "${tmp}/names.yaml" >"${tmp}/names.json"
  want="$(enabled_policies | while read -r p; do
    policy_name "${p}"
    echo
  done | sort | paste -sd' ' -)"
  for kind in ValidatingAdmissionPolicy ValidatingAdmissionPolicyBinding; do
    got="$(jq -r --arg k "${kind}" '[.[] | select(.kind == $k) | .metadata.name] | sort | join(" ")' "${tmp}/names.json")"
    [ "${got}" = "${want}" ] || { echo "❌ ${kind} names [${got}] != one per enabled policy [${want}]" >&2 && exit 1; }
  done
  jq -e 'map(select(.kind == "ValidatingAdmissionPolicyBinding")) | all(.[]; .spec.policyName == .metadata.name)' "${tmp}/names.json" >/dev/null ||
    { echo "❌ a binding does not point at its own policy" >&2 && exit 1; }
  jq -e 'map(.kind) | unique == ["ValidatingAdmissionPolicy", "ValidatingAdmissionPolicyBinding"]' "${tmp}/names.json" >/dev/null ||
    { echo "❌ the chart renders something other than policies and bindings" >&2 && exit 1; }
  render "${stacks[0]}" --set policies.disallowNodePort.enabled=false | yq -N eval-all 'select(.metadata.name == "vanadium-disallownodeport") | .kind' >"${tmp}/disabled.txt"
  [ ! -s "${tmp}/disabled.txt" ] || { echo "❌ a disabled policy still renders" >&2 && exit 1; }
  ;;
parity)
  doc=docs/developer/vanadium-baseline.md
  sed -n '/^## Sodium parity$/,/^## /p' "${doc}" | rg '^\|' | awk -F'|' 'NR != 2 { for (i = 2; i < NF; i++) { gsub(/^ +| +$/, "", $i) } print $2 "\t" $3 "\t" $4 "\t" NF }' >"${tmp}/parity.tsv"
  need "${doc} has no '## Sodium parity' table" test -s "${tmp}/parity.tsv"
  [ "$(head -n 1 "${tmp}/parity.tsv")" = "$(printf 'sodium\tvanadium\tstatus\t5')" ] ||
    { echo "❌ parity header must be exactly 'sodium | vanadium | status' (no PSA column)" >&2 && exit 1; }
  tail -n +2 "${tmp}/parity.tsv" >"${tmp}/rows.tsv"
  bad_rows="$(awk -F'\t' '$4 != 5 || $1 == "" || $2 == "" || $3 !~ /^(implemented|label exemption|workload escape hatch|dropped \(.+\))$/' "${tmp}/rows.tsv")"
  [ -z "${bad_rows}" ] || { echo "❌ malformed parity rows:"$'\n'"${bad_rows}" >&2 && exit 1; }
  rows="$(awk -F'\t' '$3 == "implemented" && $2 ~ /^`[A-Za-z]+`$/ { gsub(/`/, "", $2); print $2 }' "${tmp}/rows.tsv" | sort -u)"
  keys="$(yq -r '.policies | keys | .[]' chart/values.yaml | sort)"
  [ "${rows}" = "${keys}" ] || {
    echo "❌ parity rows and chart policies differ:" >&2 && diff <(echo "${keys}") <(echo "${rows}") >&2
    exit 1
  }
  for exclude in kube-system '*-cleanup-controller-*' '*-container-logs-collector*'; do
    awk -F'\t' -v e="${exclude}" 'index($1, "`" e "`") && ($3 == "label exemption" || $3 == "workload escape hatch") { found = 1 } END { exit !found }' "${tmp}/rows.tsv" ||
      { echo "❌ sodium exclude ${exclude} has no label-based mapping row" >&2 && exit 1; }
  done
  rg -q '^## Workload escape hatch$' "${doc}" || { echo "❌ workload-level escape hatch is not documented" >&2 && exit 1; }
  ;;
rendered-manifests)
  # The inherited Q-G20 stage: helm template -> kubeconform -> kyverno apply (definitions only).
  index=0
  for stack in "${stacks[@]}"; do
    index=$((index + 1))
    render "${stack}" >"${tmp}/rendered-${index}.yaml"
    definitions "${tmp}/rendered-${index}.yaml" "${tmp}/defs-${index}.yaml"
    kubeconform -strict -summary -schema-location default "${tmp}/rendered-${index}.yaml"
    kyverno apply "${tmp}/defs-${index}.yaml" --resource "${tmp}/rendered-${index}.yaml" --detailed-results --remove-color
    json "${tmp}/defs-${index}.yaml" | jq -e 'length > 0 and all(.[];
        .spec.paramKind == null and
        all(.spec.matchConstraints.resourceRules[]; (.operations | index("CREATE")) != null and (.operations | index("UPDATE")) != null))' >/dev/null ||
      { echo "❌ a definition takes params or misses CREATE/UPDATE ('${stack}')" >&2 && exit 1; }
    if rg -n 'oldObject|authorizer|params\.' "${tmp}/defs-${index}.yaml" >&2; then
      echo "❌ a CI-facing definition is not object-only ('${stack}')" >&2 && exit 1
    fi
  done
  ;;
conformance)
  render "${stacks[0]}" >"${tmp}/rendered.yaml"
  definitions "${tmp}/rendered.yaml" "${tmp}/defs.yaml"
  mapfile -t all < <(find "${fixtures}" -name '*.yaml' | LC_ALL=C sort)
  [ "${#all[@]}" -gt 0 ] || { echo "❌ no fixtures under ${fixtures}" >&2 && exit 1; }
  kubeconform -strict -summary -schema-location default "${all[@]}"
  want="$(enabled_policies | sort | paste -sd' ' -)"
  got="$(find "${fixtures}/bad" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | paste -sd' ' -)"
  [ "${got}" = "${want}" ] || { echo "❌ bad fixture dirs [${got}] != one per policy [${want}]" >&2 && exit 1; }
  for listed in disallowLatest/latest-tag requireResources/missing-limits disallowNodePort/nodeport requireLabels/deployment-missing-module-label \
    requireNonRoot/root-user requireAnnotations/deployment-missing-service-annotation landscapeMatch/label-mismatch landscapeMatch/annotation-mismatch \
    layerRange/layer-3 platformAccepted/platform-rogue disallowPrivEscalation/escalation-true restrictVolumeTypes/hostpath-etc \
    restrictVolumeTypes/carveout-path-outside restrictVolumeTypes/carveout-other-serviceaccount; do
    need "goal-listed fixture ${listed} is missing" test -s "${fixtures}/bad/${listed}.yaml"
  done
  check_good_fixtures "${tmp}/defs.yaml"
  check_bad_fixtures "${tmp}/defs.yaml"
  ;;
audit-enforce)
  for overlay in chart/values.*.yaml; do
    landscape="$(yq -r '.serviceTree.landscape // ""' "${overlay}")"
    [ -z "${landscape}" ] && continue
    [ -n "${posture[${landscape}]:-}" ] || { echo "❌ landscape overlay ${overlay} has no declared posture" >&2 && exit 1; }
    [ "${posture[${landscape}]}" = deny ] && want='["Deny"]' || want='["Warn","Audit"]'
    for cluster in "" "--values chart/values.lapras.yaml"; do
      render "--values ${overlay} ${cluster}" >"${tmp}/posture.yaml"
      json "${tmp}/posture.yaml" | jq -e --argjson want "${want}" 'map(select(.kind == "ValidatingAdmissionPolicyBinding")) | length > 0 and all(.[]; .spec.validationActions == $want)' >/dev/null ||
        { echo "❌ ${landscape} must bind every policy ${want}" >&2 && exit 1; }
    done
  done
  [ "$(yq -r '.enforcement' chart/values.yaml)" = audit ] || { echo "❌ the base posture must be audit ([Warn, Audit])" >&2 && exit 1; }
  expect_red 'binds Deny in an audit landscape' render "${stacks[0]}" --set 'policies.disallowLatest.actions={Deny}'
  expect_red 'binds Deny in an audit landscape' render "" --set serviceTree.landscape=example --set 'policies.requireLabels.actions={Deny,Audit}'
  expect_red 'cannot combine Deny and Warn' render "${stacks[2]}" --set 'policies.disallowLatest.actions={Deny,Warn}'
  render "${stacks[2]}" --set 'policies.disallowLatest.actions={Warn,Audit}' | yq -o=json eval-all 'select(.kind == "ValidatingAdmissionPolicyBinding" and .metadata.name == "vanadium-disallowlatest") | .spec.validationActions' |
    jq -e '. == ["Warn", "Audit"]' >/dev/null || { echo "❌ a per-policy override does not apply in a deny landscape" >&2 && exit 1; }
  ;;
exemption)
  render "${stacks[0]}" >"${tmp}/rendered.yaml"
  json "${tmp}/rendered.yaml" | jq -e 'map(select(.kind == "ValidatingAdmissionPolicyBinding")) | length > 0 and all(.[];
      .spec.matchResources == {namespaceSelector: {matchExpressions: [{key: "atomi.cloud/policy-exempt", operator: "NotIn", values: ["true"]}]}})' >/dev/null ||
    { echo "❌ a binding does not select on the namespace exemption label" >&2 && exit 1; }
  render "${stacks[0]}" --set exemptionLabel=admission-skip | yq -o=json eval-all 'select(.kind == "ValidatingAdmissionPolicyBinding") | .spec.matchResources.namespaceSelector.matchExpressions[0].key' |
    jq -se 'unique == ["atomi.cloud/admission-skip"]' >/dev/null || { echo "❌ exemptionLabel does not drive the selector" >&2 && exit 1; }
  yq eval-all 'select(.kind == "ValidatingAdmissionPolicy" or .kind == "ValidatingAdmissionPolicyBinding")' "${tmp}/rendered.yaml" >"${tmp}/bound.yaml"
  # The SAME violating manifest, once with its namespace exempt and once without.
  for dir in "${fixtures}"/bad/*/; do
    want="$(policy_name "$(basename "${dir}")")"
    for fixture in "${dir}"*.yaml; do
      ns="$(yq -r '.metadata.namespace' "${fixture}")"
      for exempt in true false; do
        labels='{}'
        [ "${exempt}" = true ] && labels='{"atomi.cloud/policy-exempt": "true"}'
        jq -n --arg ns "${ns}" --argjson l "${labels}" '{apiVersion: "cli.kyverno.io/v1alpha1", kind: "Value", namespaceSelector: [{name: $ns, labels: $l}]}' | yq -P >"${tmp}/ns.yaml"
        kyverno apply "${tmp}/bound.yaml" --resource "${fixture}" --values-file "${tmp}/ns.yaml" --remove-color >"${tmp}/apply.txt" 2>&1 || true
        got="$(sed -n 's/^policy \([^ ]*\) -> resource .* failed:$/\1/p' "${tmp}/apply.txt" | sort -u | paste -sd' ' -)"
        if [ "${exempt}" = true ]; then
          rg -q '^pass: 0, fail: 0, warn: 0, error: 0, skip: 0' "${tmp}/apply.txt" || { echo "❌ ${fixture} is not admitted in exempt namespace ${ns}" >&2 && cat "${tmp}/apply.txt" >&2 && exit 1; }
        else
          [ "${got}" = "${want}" ] || { echo "❌ ${fixture} in non-exempt namespace ${ns} must fail ${want}, failed [${got}]" >&2 && exit 1; }
        fi
      done
    done
  done
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  need "git chart package missing" test -s "${tmp}/git/vanadium-0.1.0.tgz"
  need "git chart index missing" test -s "${tmp}/git/index.yaml"
  if tar -tzf "${tmp}/git/vanadium-0.1.0.tgz" | rg -q '^vanadium/tests/'; then
    echo "❌ the chart package ships test fixtures" >&2 && exit 1
  fi
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  need "OCI chart package missing" test -s "${tmp}/oci/vanadium-0.1.0.tgz"
  need "OCI ref is not the dry-run default" rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'does not match tag 9.9.9' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/mismatch" bash ./scripts/ci/publish.sh
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ vanadium ${mode} validation passed"
