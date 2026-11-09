#!/usr/bin/env bash
set -euo pipefail

# Renders a chart fresh into the gitignored infra/rendered/<chart>/ (scripts/local/helm-render.sh),
# then runs `chart-checks check` on every rendered file: Kubernetes schemas (unknown fields
# refused) and the ValidatingAdmissionPolicies of the policy charts listed in chart-checks.yaml.
# Nothing is committed and nothing is dropped: each policy's matchConstraints selects.

chart="${1:-infra/root_chart}"
rendered="infra/rendered/$(basename "${chart}")"

root="$(git rev-parse --show-toplevel)"
cd "${root}"

./scripts/local/helm-render.sh "${chart}"

files=("${rendered}"/*.yaml)
[ -e "${files[0]}" ] || {
  echo "❌ no rendered YAML in ${rendered}" >&2
  exit 1
}

chart-checks check -c chart-checks.yaml "${files[@]}"

echo "✅ Helm render checks passed"
