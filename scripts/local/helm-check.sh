#!/usr/bin/env bash
set -euo pipefail

# Renders a chart fresh into the gitignored infra/rendered/<chart>/ (scripts/local/helm-render.sh),
# then validates every rendered object:
#   1. kubeconform -strict   against the Kubernetes schemas
#   2. kyverno apply         against the ValidatingAdmissionPolicies in infra/policies/
# Nothing is committed and nothing is dropped: each policy's matchConstraints selects.

chart="${1:-infra/root_chart}"
rendered="infra/rendered/$(basename "${chart}")"
policies="${POLICIES_DIR:-infra/policies}"

root="$(git rev-parse --show-toplevel)"
cd "${root}"

./scripts/local/helm-render.sh "${chart}"

files=("${rendered}"/*.yaml)
[ -e "${files[0]}" ] || {
  echo "❌ no rendered YAML in ${rendered}" >&2
  exit 1
}
policy_files=("${policies}"/*.yaml)
[ -e "${policy_files[0]}" ] || {
  echo "❌ no policies in ${policies}" >&2
  exit 1
}

kubeconform -strict -summary "${files[@]}"

for file in "${files[@]}"; do
  kyverno apply "${policy_files[@]}" --resource "${file}"
done

echo "✅ Helm render checks passed"
