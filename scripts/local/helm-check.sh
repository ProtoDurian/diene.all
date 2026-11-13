#!/usr/bin/env bash
set -euo pipefail

# Renders a chart fresh into the gitignored infra/rendered/<chart>/ (scripts/local/helm-render.sh),
# then checks every rendered file in two steps:
#   1. `chart-checks check`: Kubernetes schemas (unknown fields refused) and the
#      ValidatingAdmissionPolicies of the policy charts listed in chart-checks.yaml. The LPSM
#      label rule there covers workloads and pod templates only, upstream subcharts included.
#   2. First-party labels: every object from the chart's OWN templates (not its subcharts),
#      of any kind, carries the four LPSM labels under the policy chart's labelPrefix.
# Nothing is committed and nothing is dropped from step 1.

chart="${1:-infra/root_chart}"
rendered="infra/rendered/$(basename "${chart}")"
policy_values="infra/policies/values.yaml"

root="$(git rev-parse --show-toplevel)"
cd "${root}"

./scripts/local/helm-render.sh "${chart}"

files=("${rendered}"/*.yaml)
[ -e "${files[0]}" ] || {
  echo "❌ no rendered YAML in ${rendered}" >&2
  exit 1
}

chart-checks check -c chart-checks.yaml "${files[@]}"

name="$(yq -r '.name' "${chart}/Chart.yaml")"
prefix="$(yq -r '.labelPrefix' "${policy_values}")"
[ -n "${prefix}" ] && [ "${prefix}" != "null" ] || {
  echo "❌ ${policy_values} has no labelPrefix" >&2
  exit 1
}

# Helm marks each document with "# Source: <chart>/templates/..." (own) or
# "# Source: <chart>/charts/<sub>/..." (subchart); turn it into a key yq can select on.
# shellcheck disable=SC2016 # $l and $k are yq variables, not shell ones
missing="$(
  awk '/^# Source: /{ sub(/^# Source: /, ""); printf "__source: \"%s\"\n", $0; next } { print }' "${files[@]}" |
    PREFIX="${prefix}" OWN="${name}/templates/" yq ea -r '
      select(.__source | test("^" + strenv(OWN)))
      | select((.metadata.labels // {}) as $l
          | ["landscape", "platform", "service", "module"]
          | map(strenv(PREFIX) + "/" + .)
          | any_c(. as $k | $l | has($k) | not))
      | .__source + " (" + .kind + " " + .metadata.name + ")"
    ' -
)"
if [ -n "${missing}" ]; then
  echo "❌ first-party objects without all four ${prefix}/ LPSM labels:" >&2
  while IFS= read -r line; do echo "   - ${line}" >&2; done <<<"${missing}"
  exit 1
fi

echo "✅ Helm render checks passed"
