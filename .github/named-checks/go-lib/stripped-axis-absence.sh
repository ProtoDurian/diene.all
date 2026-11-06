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
  infra
  .dockerignore
  '.github/workflows/⚡reusable-docker.yaml'
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
  probes/distroless-base-policy.ts
  probes/nonroot-image-policy.ts
  scripts/validate/go-image-policy.sh
)
D_TOKENS=(
  infra/Dockerfile .dockerignore reusable-docker Taskfile.docker docker.sh
  docker-push standards/docker docker/index.md docker-build
  '](infra)' 'infra/' 'docker:build' 'docker:run'
  go-image-policy distroless-base-policy nonroot-image-policy
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
)
H_TOKENS=(
  root_chart reusable-helm Taskfile.helm helm.sh helm-push standards/helm
  helm/index.md a-helm-lint helm-lint helm-render
)
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**')

for p in "${D_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "D path still tracked: ${p}"; fi
done
for p in "${H_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "H path still tracked: ${p}"; fi
done
if grep -Eq '(^|/)\.helmignore$' <<<"$(git ls-tree -r --name-only "${tree}")"; then fail "H path still tracked: .helmignore"; fi

args=()
for t in "${D_TOKENS[@]}" "${H_TOKENS[@]}"; do args+=(-e "${t}"); done
rc=0
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}")" || rc=$?
[[ ${rc} -le 1 ]] || fail "git grep failed (exit ${rc})"
[[ -z ${hits} ]] || fail "files still reference removed D/H paths:"$'\n'"${hits}"

show() { git show "${tree}:$1"; }
publish='.github/workflows/⚡reusable-publish.yaml'
for wf in .github/workflows/ci.yaml .github/workflows/cd.yaml; do
  [[ "$(show "${wf}" | yq '[.jobs[] | select(.uses // "" | test("docker|helm"))] | length')" == 0 ]] || fail "${wf} still calls a docker/helm workflow"
  [[ "$(show "${wf}" | yq '.jobs | (has("docker") or has("helm"))')" == false ]] || fail "${wf} still has a docker/helm job"
done
[[ "$(show .github/workflows/cd.yaml | yq '.jobs | keys | join(",")')" == publish ]] || fail "cd.yaml carries a job other than publish"
[[ "$(show .github/workflows/cd.yaml | yq '.jobs.publish.uses')" == "./${publish}" ]] || fail "cd.yaml publish does not call ${publish}"
for wf in .github/workflows/cd.yaml "${publish}"; do
  [[ "$(show "${wf}" | yq '[.jobs[].steps[]? | (.uses // "") + " " + (.run // "") | select(test("(?i)docker|helm"))] | length')" == 0 ]] || fail "${wf} carries a docker/helm step"
done
[[ "$(show Taskfile.yaml | yq '.includes | (has("docker") or has("helm"))')" == false ]] || fail "Taskfile.yaml still includes docker/helm"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker" or .package-ecosystem == "helm")] | length')" == 0 ]] || fail "dependabot.yml still has a docker/helm entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|dockerd|hadolint|skopeo|helm|helm-docs|helmlint|kubeconform|kyverno)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes a D/H binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker|helm|distroless|nonroot"))] | length')" == 0 ]] || fail "features.json still has a docker/helm row"
if grep -Eqi '^# (docker|helm)' <<<"$(show CLAUDE.md)"; then fail "CLAUDE.md still has a Docker/Helm section"; fi
if grep -Eq '^(docker|dockerd|hadolint|skopeo|helm|helm-docs|helmlint|kubeconform|kyverno) ' <<<"$(show probes/binary-smoke.ts)"; then fail "binary-smoke.ts still smokes a D/H binary"; fi

# Binaries are not checked: the whole infralint/infrautils bundles keep docker and helm on PATH.
for f in nix/packages.nix nix/env.nix; do
  if grep -v '^ *#' <<<"$(show "${f}")" | grep -Ec '(^|[^A-Za-z0-9-])(infralint-docker|infrautils-docker|docker|docker-client|hadolint|skopeo|kubernetes-helm|helm|helm-docs|helmlint)([^A-Za-z0-9-]|$)' >/dev/null; then
    fail "${f} declares a docker/helm-carrying package"
  fi
done

for f in .github/workflows/ci.yaml .github/workflows/cd.yaml "${publish}" .github/dependabot.yml Taskfile.yaml dlint.yaml; do
  yq e '.' "${f}" >/dev/null 2>&1 || fail "${f} is not valid YAML"
done
jq -e . probes/features.json >/dev/null 2>&1 || fail "probes/features.json is not valid JSON"
for f in nix/packages.nix nix/env.nix nix/shells.nix; do
  nix-instantiate --parse "${f}" >/dev/null 2>"${work}/nix.out" || fail "${f} does not parse: $(head -3 "${work}/nix.out")"
done
actionlint -config-file .github/actionlint.yaml .github/workflows/*.y*ml >"${work}/actionlint.out" 2>&1 || fail "actionlint failed: $(head -5 "${work}/actionlint.out")"
task --list-all >"${work}/task.out" 2>&1 || fail "task --list-all failed: $(head -5 "${work}/task.out")"
dlint ci-wiring >"${work}/dlint.out" 2>&1 || fail "dlint ci-wiring failed: $(head -5 "${work}/dlint.out")"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ stripped-axis-absence: no D/H path, reference, entry, or nix package; cd.yaml is publish-only; edited files valid"
