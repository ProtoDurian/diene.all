#!/usr/bin/env bash
set -euo pipefail

# Binaries are not checked (owner !A103): the bundles keep docker and helm on PATH.
# bun-lib re-adds cd.yaml for its npm publish job only.

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
  infra
  .dockerignore
  '.github/workflows/⚡reusable-docker.yaml'
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
)
# Strings no remaining file may contain (the parent's D_TOKENS minus cd.yaml,
# which bun-lib re-adds for publish).
D_TOKENS=(
  infra/Dockerfile .dockerignore reusable-docker Taskfile.docker docker.sh
  docker-push standards/docker docker/index.md docker-build
  '](infra)' 'infra/' 'docker:build' 'docker:run'
)
H_PATHS=(
  infra/root_chart
  '.github/workflows/⚡reusable-helm.yaml'
  tasks/Taskfile.helm.yaml
  scripts/ci/helm.sh
  .claude/skills/helm-push
  docs/standards/helm
  probes/helm-lint.ts
  probes/helm-render.ts
  probes/hook-helm-lint.ts
  .helmignore
)
H_TOKENS=(
  root_chart reusable-helm Taskfile.helm helm.sh helm-push standards/helm
  helm/index.md a-helm-lint helm-lint helm-render
)
# The declaration itself; machine-maintained history; the probe harness whose
# command-string fixtures are generic and name no axis file.
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**')

# --- paths ----------------------------------------------------------------------
for p in "${D_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "D path still tracked: ${p}"; fi
done
for p in "${H_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "H path still tracked: ${p}"; fi
done

# --- references -------------------------------------------------------------------
args=()
for t in "${D_TOKENS[@]}" "${H_TOKENS[@]}"; do args+=(-e "${t}"); done
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files still reference removed D/H paths:"$'\n'"${hits}"

# --- anchored entries -------------------------------------------------------------
show() { git show "${tree}:$1"; }
for wf in .github/workflows/ci.yaml .github/workflows/cd.yaml; do
  [[ "$(show "${wf}" | yq '[.jobs[] | select(.uses // "" | test("docker|helm"))] | length')" == 0 ]] || fail "${wf} still calls a docker/helm workflow"
  [[ "$(show "${wf}" | yq '.jobs | (has("docker") or has("helm"))')" == false ]] || fail "${wf} still has a docker/helm job"
done
[[ "$(show .github/workflows/cd.yaml | yq '.jobs | keys | join(",")')" == publish ]] || fail "cd.yaml carries a job other than publish"
[[ "$(show Taskfile.yaml | yq '.includes | (has("docker") or has("helm"))')" == false ]] || fail "Taskfile.yaml still includes docker/helm"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker" or .package-ecosystem == "helm")] | length')" == 0 ]] || fail "dependabot.yml still has a docker/helm entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|dockerd|hadolint|helm|helm-docs|helmlint)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes a D/H binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker|helm"))] | length')" == 0 ]] || fail "features.json still has a docker/helm row"
if show CLAUDE.md | grep -Eqi '^# (docker|helm)'; then fail "CLAUDE.md still has a Docker/Helm section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(docker|dockerd|hadolint|helm|helm-docs|helmlint) '; then fail "binary-smoke.ts still smokes a D/H binary"; fi
if git grep -n -i -w -E 'helm|image or chart|Docker (scripts|callers)' "${tree}" -- docs/standards/ci-cd/index.md; then fail "ci-cd publishing prose still names Docker/Helm"; fi
if git grep -n -E 'CI/CD, (Docker|Helm)|Docker, Helm' "${tree}" -- README.md; then fail "README.md still lists Docker/Helm"; fi
if git grep -n -E 'image values|chart values|image and chart' "${tree}" -- docs/standards/taskfile/index.md; then fail "taskfile rule 5 still names images/charts"; fi

# --- the many-owner files the strip edited still parse and lint ---------------------
for f in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/dependabot.yml Taskfile.yaml dlint.yaml; do
  yq e '.' "${f}" >/dev/null 2>&1 || fail "${f} is not valid YAML"
done
jq -e . probes/features.json >/dev/null 2>&1 || fail "probes/features.json is not valid JSON"
for f in nix/packages.nix nix/env.nix; do
  nix-instantiate --parse "${f}" >/dev/null 2>"${work}/nix.out" || fail "${f} does not parse: $(head -3 "${work}/nix.out")"
done
actionlint -config-file .github/actionlint.yaml .github/workflows/*.y*ml >"${work}/actionlint.out" 2>&1 || fail "actionlint failed: $(head -5 "${work}/actionlint.out")"
task --list-all >"${work}/task.out" 2>&1 || fail "task --list-all failed: $(head -5 "${work}/task.out")"
dlint ci-wiring >"${work}/dlint.out" 2>&1 || fail "dlint ci-wiring failed: $(head -5 "${work}/dlint.out")"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ strip-absence: no D/H path, reference, entry, smoke line or prose; cd.yaml is publish-only; edited files valid"
