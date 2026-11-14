#!/usr/bin/env bash
set -euo pipefail

# Renders a chart fresh into the gitignored infra/rendered/<chart>/ (scripts/local/helm-render.sh),
# runs `helm lint`, then checks every rendered file in two steps:
#   1. `chart-checks check`: Kubernetes schemas (unknown fields refused) and the
#      ValidatingAdmissionPolicies of the policy charts listed in chart-checks.yaml (installed first;
#      the cluster-policies chart is fetched from its stand-in repo at the pinned commit). That
#      chart is rendered with the labelPrefix of the stack being checked (the root chart's own value
#      plus that stack's overlay). The LPSM label rule and the reload label rule there cover
#      workloads and pod templates only, upstream subcharts included.
#   2. First-party labels: every object from the chart's OWN templates (not its subcharts),
#      of any kind, carries the four LPSM labels under that prefix. Helm test hooks are exempt,
#      like in the policy chart.
# Nothing is committed and nothing is dropped from step 1.

chart="${1:-infra/root_chart}"
rendered="infra/rendered/$(basename "${chart}")"

root="$(git rev-parse --show-toplevel)"
cd "${root}"

name="$(yq -r '.name' "${chart}/Chart.yaml")"

./scripts/local/helm-render.sh "${chart}"
helm lint "${chart}"

files=("${rendered}"/*.yaml)
[ -e "${files[0]}" ] || {
  echo "❌ no rendered YAML in ${rendered}" >&2
  exit 1
}

stack_prefix() {
  local overlay="${chart}/values.$1.yaml"
  if [ "$1" = "default" ] || [ ! -e "${overlay}" ]; then
    yq -r '.labelPrefix' "${chart}/values.yaml"
  else
    yq ea -r 'select(fi == 0) * select(fi == 1) | .labelPrefix' "${chart}/values.yaml" "${overlay}"
  fi
}

policy_dir="infra/rendered/policies"
fetched=".chart-checks/policies/cluster-policies"

# chart-checks.yaml pins the policy chart by commit; install fetches it into .chart-checks/ (exit 4 when the
# commit cannot be fetched, 3 when the config is refused).
chart-checks install -c chart-checks.yaml
[ -d "${fetched}" ] || {
  echo "❌ chart-checks did not install ${fetched}" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${root}/.chart-checks"
ln -s "${root}/.chart-checks" "${tmp}/.chart-checks"
rel_root="$(realpath --relative-to="${tmp}" "${root}")"
for file in "${files[@]}"; do
  [ "$(basename "${file}")" = "chart-checks.yaml" ] && continue
  stack="$(basename "${file}" .yaml)"
  prefix="$(stack_prefix "${stack}")"
  [ -n "${prefix}" ] && [ "${prefix}" != "null" ] || {
    echo "❌ ${chart}/values.yaml has no labelPrefix" >&2
    exit 1
  }

  rm -rf "${policy_dir}"
  mkdir -p "${policy_dir}"
  cp -R "${fetched}/." "${policy_dir}/"
  PREFIX="${prefix}" yq -i '.labelPrefix = strenv(PREFIX)' "${policy_dir}/values.yaml"
  # Only the cluster-policies entry (a git entry) points at the rendered copy; every other entry
  # keeps its own source. chart-checks resolves paths next to the config file, so they are given relative to the
  # temporary config directory.
  ROOT="${rel_root}" POLICY_DIR="${rel_root}/${policy_dir}" yq '
    (.policies[] | select(.name == "cluster-policies")) |= (del(.git) | del(.commit) | del(.subpath) | .path = strenv(POLICY_DIR))
    | (.policies[] | select(.name != "cluster-policies") | .path | select(. != null)) |= strenv(ROOT) + "/" + .
  ' chart-checks.yaml >"${tmp}/chart-checks.yaml"
  chart-checks check -c "${tmp}/chart-checks.yaml" "${file}"

  # Helm marks each document with "# Source: <chart>/templates/..." (own) or
  # "# Source: <chart>/charts/<sub>/..." (subchart); turn it into a key yq can select on.
  # shellcheck disable=SC2016 # $l and $k are yq variables, not shell ones
  missing="$(
    awk '/^# Source: /{ sub(/^# Source: /, ""); printf "__source: \"%s\"\n", $0; next } { print }' "${file}" |
      PREFIX="${prefix}" OWN="${name}/templates/" yq ea -r '
        select(.__source | test("^" + strenv(OWN)))
        | select(((.metadata.annotations // {})["helm.sh/hook"] // "" | split(",") | map(trim)
            | any_c(. == "test" or . == "test-success" or . == "test-failure")) | not)
        | select((.metadata.labels // {}) as $l
            | ["landscape", "platform", "service", "module"]
            | map(strenv(PREFIX) + "/" + .)
            | any_c(. as $k | $l | has($k) | not))
        | .__source + " (" + .kind + " " + .metadata.name + ")"
      ' -
  )"
  if [ -n "${missing}" ]; then
    echo "❌ ${file}: first-party objects without all four ${prefix}/ LPSM labels:" >&2
    while IFS= read -r line; do echo "   - ${line}" >&2; done <<<"${missing}"
    exit 1
  fi
done

echo "✅ Helm render checks passed"
