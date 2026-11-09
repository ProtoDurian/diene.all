#!/usr/bin/env bash
set -euo pipefail

# Renders a chart to plain YAML (gitignored, never committed): one file per values stack under
# infra/rendered/<chart>/<stack>.yaml. `values.yaml` is the `default` stack; each
# `values.<name>.yaml` overlay is the stack `<name>` (rendered on top of `values.yaml`).

chart="${1:-infra/root_chart}"
release="${RELEASE:-diene-workspace}"
out="infra/rendered/$(basename "${chart}")"

[ -d "${chart}" ] || {
  echo "❌ chart '${chart}' not found" >&2
  exit 1
}

root="$(git rev-parse --show-toplevel)"
cd "${root}"
mkdir -p "${out}"
find "${out}" -maxdepth 1 -name '*.yaml' -delete

helm template "${release}" "${chart}" >"${out}/default.yaml"
for overlay in "${chart}"/values.*.yaml; do
  [ -e "${overlay}" ] || continue
  stack="$(basename "${overlay}" .yaml)"
  stack="${stack#values.}"
  helm template "${release}" "${chart}" --values "${chart}/values.yaml" --values "${overlay}" >"${out}/${stack}.yaml"
done

echo "✅ Rendered ${chart} into ${out}"
