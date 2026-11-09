#!/usr/bin/env bash
set -euo pipefail

# Modes of the three chart-check hooks; every other check runs from probes/ only.

mode="${1:-}"
release="${RELEASE:-helm-wrapper}"
namespace="${NAMESPACE:-sample}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

bash ./scripts/local/vendor-chart-config.sh >/dev/null

# The three committed stacks: base -> landscape -> cluster.
stacks=("" "--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")

case "${mode}" in
lint)
  # helm lint also validates every stack against chart/values.schema.json.
  for stack in "${stacks[@]}"; do
    # shellcheck disable=SC2086
    helm lint chart --namespace "${namespace}" ${stack}
    # shellcheck disable=SC2086
    helm template "${release}" chart --namespace "${namespace}" ${stack} >/dev/null
  done
  ;;
schema)
  bash ./scripts/local/generate-chart-schema.sh >/dev/null
  ;;
manifests)
  files=()
  index=0
  for stack in "${stacks[@]}"; do
    index=$((index + 1))
    # The podinfo helm-test hook Pods are upstream-named and only exist on `helm test`.
    # shellcheck disable=SC2086
    helm template "${release}" chart --namespace "${namespace}" --skip-tests ${stack} >"${tmp}/stack-${index}.yaml"
    files+=("${tmp}/stack-${index}.yaml")
  done
  chart-checks check "${files[@]}"
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Helm wrapper ${mode} validation passed"
