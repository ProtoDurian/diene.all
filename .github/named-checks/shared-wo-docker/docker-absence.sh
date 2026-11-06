#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

D_PATHS=(
  infra/Dockerfile
  .dockerignore
  '.github/workflows/⚡reusable-docker.yaml'
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
)
D_TOKENS=(
  infra/Dockerfile .dockerignore reusable-docker Taskfile.docker docker.sh
  docker-push standards/docker docker/index.md docker-build
)
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**')
H_PATHS=(
  infra/root_chart/Chart.yaml
  '.github/workflows/⚡reusable-helm.yaml'
  tasks/Taskfile.helm.yaml
  scripts/ci/helm.sh
  .claude/skills/helm-push/SKILL.md
  docs/standards/helm/index.md
  probes/helm-lint.ts
  probes/helm-render.ts
  probes/hook-helm-lint.ts
)

for p in "${D_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "D path still tracked: ${p}"; fi
done

args=()
for t in "${D_TOKENS[@]}"; do args+=(-e "${t}"); done
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files still reference removed D paths:"$'\n'"${hits}"

show() { git show "${tree}:$1"; }
for f in .github/workflows/ci.yaml .github/workflows/cd.yaml; do
  [[ "$(show "${f}" | yq '.jobs | has("docker")')" == false ]] || fail "${f} still has a docker job"
  [[ "$(show "${f}" | yq '[.jobs[] | select(.uses // "" | test("docker"))] | length')" == 0 ]] || fail "${f} still calls a docker workflow"
done
[[ "$(show Taskfile.yaml | yq '.includes | has("docker")')" == false ]] || fail "Taskfile.yaml still includes docker"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker")] | length')" == 0 ]] || fail "dependabot.yml still has a docker entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|hadolint)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes a D binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker"))] | length')" == 0 ]] || fail "features.json still has a docker row"
if show CLAUDE.md | grep -qi '^# docker'; then fail "CLAUDE.md still has a Docker section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(docker|hadolint) '; then fail "binary-smoke.ts still smokes a D binary"; fi

# Positive control: the Helm surface helm-wrapper consumes is intact.
for p in "${H_PATHS[@]}"; do
  [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]] || fail "Helm path missing: ${p}"
done
for f in .github/workflows/ci.yaml .github/workflows/cd.yaml; do
  [[ "$(show "${f}" | yq '.jobs.helm.uses')" == './.github/workflows/⚡reusable-helm.yaml' ]] || fail "${f} lost its helm job"
done
[[ "$(show Taskfile.yaml | yq '.includes.helm')" == tasks/Taskfile.helm.yaml ]] || fail "Taskfile.yaml lost its helm include"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "helm")] | length')" == 1 ]] || fail "dependabot.yml lost its helm entry"
[[ "$(show probes/features.json | jq '[.[] | select(.name == "helm-lint" or .name == "helm-render" or .name == "hook-helm-lint")] | length')" == 3 ]] || fail "features.json lost a helm row"
show CLAUDE.md | grep -qx '# Helm charts and publishing' || fail "CLAUDE.md lost its Helm section"
show nix/pre-commit.nix | grep -q 'a-helm-lint = {' || fail "pre-commit lost a-helm-lint"

for f in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/dependabot.yml Taskfile.yaml dlint.yaml; do
  yq e '.' "${f}" >/dev/null 2>&1 || fail "${f} is not valid YAML"
done
jq -e . probes/features.json >/dev/null 2>&1 || fail "probes/features.json is not valid JSON"
actionlint -config-file .github/actionlint.yaml .github/workflows/*.y*ml >"${work}/actionlint.out" 2>&1 || fail "actionlint failed: $(head -5 "${work}/actionlint.out")"
task --list-all --json >"${work}/task.out" 2>&1 || fail "task --list-all failed: $(head -5 "${work}/task.out")"
[[ "$(jq '[.tasks[].name | select(startswith("helm:"))] | length' "${work}/task.out" 2>/dev/null)" -gt 0 ]] || fail "task --list-all shows no helm tasks"
dlint ci-wiring >"${work}/dlint.out" 2>&1 || fail "dlint ci-wiring failed: $(head -5 "${work}/dlint.out")"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ docker-absence: no D path, reference or entry; Helm surface intact; edited files valid"
