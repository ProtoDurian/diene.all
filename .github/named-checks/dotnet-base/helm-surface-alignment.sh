#!/usr/bin/env bash
set -euo pipefail

bun_base_sha="${NAMED_CHECKS_BUN_BASE_SHA:-$(cat "$(dirname "$0")/bun-base.sha")}"
git rev-parse --verify --quiet "${bun_base_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${bun_base_sha}" || true
git rev-parse --verify --quiet "${bun_base_sha}^{commit}" >/dev/null || { echo "❌ bun-base .3 commit ${bun_base_sha} not found; fetch it first" >&2 && exit 1; }

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

paths=(
  infra/root_chart
  tasks/Taskfile.helm.yaml
  scripts/ci/helm.sh
  .github/workflows/⚡reusable-helm.yaml
  docs/standards/helm
  .claude/skills/helm-push
)
for path in "${paths[@]}"; do
  ours="$(git rev-parse --verify --quiet "${tree}:${path}" || echo absent)"
  theirs="$(git rev-parse --verify --quiet "${bun_base_sha}:${path}" || echo absent)"
  if [[ ${ours} != "${theirs}" ]]; then
    echo "❌ ${path} differs from bun-base (${ours} vs ${theirs})" >&2
    failed=1
  fi
done

compare() {
  local file="$1" expression="$2" ours theirs
  ours="$(git show "${tree}:${file}" | yq -o=json "${expression}")"
  theirs="$(git show "${bun_base_sha}:${file}" | yq -o=json "${expression}")"
  if [[ ${ours} == null || ${ours} != "${theirs}" ]]; then
    echo "❌ ${file} ${expression} differs from bun-base" >&2
    failed=1
  fi
}
compare .github/workflows/ci.yaml '.jobs.helm'
compare .github/workflows/cd.yaml '.jobs.helm'
compare .github/dependabot.yml '.updates[] | select(.package-ecosystem == "helm")'

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ helm-surface-alignment: Helm surface identical to bun-base .3 ${bun_base_sha}"
