#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks are literal doc text
set -euo pipefail

# Replaces the dropped presence, gateway-webhook-presence and tokenization-presence modes:
# docs/developer/helm-wrapper-baseline.md lists the tokenization surface and documents the
# gateway health and webhook route conventions.
cd "$(git rev-parse --show-toplevel)"
tree="$(git write-tree)"
doc=docs/developer/helm-wrapper-baseline.md
failed=0
fail() {
  echo "❌ $*" >&2
  failed=1
}

git cat-file -e "${tree}:${doc}" 2>/dev/null || {
  echo "❌ ${doc} is missing from HEAD" >&2
  exit 1
}
text="$(git show "${tree}:${doc}")"

# The section runs from its heading to the next heading of the same level.
section="$(awk '/^## Tokenization surface$/ { on = 1; next } /^## / { on = 0 } on' <<<"${text}")"
[[ -n ${section} ]] || fail "${doc} has no non-empty '## Tokenization surface' section"

scalars=(
  'chart and release name'
  'serviceTree platform/service/module/layer'
  '`labelPrefix`'
  'upstream chart name/version/repository'
  'vendored tgz filename'
  'skopeo image refs'
  'OCI/ghcr organization path'
  'git repository URL'
  'landscape overlay filenames'
  'cluster overlay filenames'
  '`chart-checks.yaml` entries'
  'repository-qualified physical instance id'
  'normalized instance DNS label'
  'original-instance metadata annotation'
  'hostname zone selection'
)
for scalar in "${scalars[@]}"; do
  grep -qiF -- "${scalar}" <<<"${section}" || fail "the Tokenization surface section does not list: ${scalar}"
done

# Gateway health path (contracts.health.path, 2xx contract) and the webhook route convention.
grep -qF '`contracts.health.path`' <<<"${text}" || fail "${doc} does not name contracts.health.path"
grep -qF '2xx' <<<"${text}" || fail "${doc} does not state the 2xx health contract"
grep -qF '/internal/webhooks/{provider}' <<<"${text}" || fail "${doc} does not document /internal/webhooks/{provider}"
health_path="$(git show "${tree}:chart/values.yaml" | yq -r '.contracts.health.path')"
grep -qF -- "${health_path}" <<<"${text}" || fail "${doc} does not document the health path ${health_path} that chart/values.yaml sets"
git cat-file -e "${tree}:chart/templates/webhook-route.yaml" 2>/dev/null || fail "chart/templates/webhook-route.yaml (the webhook scaffold) is missing"

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ baseline-doc: the baseline doc lists the tokenization surface and documents the gateway health and webhook conventions"
