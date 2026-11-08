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
[[ "$(show .github/workflows/cd.yaml | yq -o=json -I=0 '.jobs | keys')" == '["release","publish"]' ]] || fail "cd.yaml must have exactly the release and publish jobs"
[[ "$(show .github/workflows/cd.yaml | yq '.jobs.publish.uses')" == "./${publish}" ]] || fail "cd.yaml publish does not call ${publish}"
for wf in .github/workflows/cd.yaml "${publish}"; do
  [[ "$(show "${wf}" | yq '[.jobs[].steps[]? | (.uses // "") + " " + (.run // "") | select(test("(?i)docker|helm"))] | length')" == 0 ]] || fail "${wf} carries a docker/helm step"
done

note_wf='.github/workflows/⚡reusable-release-note.yaml'
note_sh=scripts/ci/release-note.sh
for p in "${note_wf}" "${note_sh}"; do
  git cat-file -e "${tree}:${p}" 2>/dev/null || fail "CD stub file missing: ${p}"
done
[[ "$(show .github/workflows/cd.yaml | yq -o=json -I=0 '.on')" == '{"push":{"tags":["v*.*.*"]}}' ]] || fail "cd.yaml must run on v*.*.* tags only"
[[ "$(show .github/workflows/cd.yaml | yq '.jobs.release.uses')" == "./${note_wf}" ]] || fail "cd.yaml release job must call ${note_wf}"
[[ "$(show .github/workflows/cd.yaml | yq -o=json -I=0 '.jobs.release.permissions')" == '{"contents":"read"}' ]] || fail "cd.yaml release job must grant only contents: read"
# shellcheck disable=SC2016
[[ "$(show .github/workflows/cd.yaml | yq -o=json -I=0 '.jobs.release.with')" == '{"version":"${{ github.ref_name }}"}' ]] || fail "cd.yaml release job must pass only version: the tag"
[[ "$(show dlint.yaml | yq '[.checks["ci-wiring"].orchestrators[] | select(. == ".github/workflows/cd.yaml")] | length')" == 1 ]] || fail "dlint.yaml must wire cd.yaml as an orchestrator"
[[ "$(show "${note_wf}" | yq -o=json -I=0 '.jobs | keys')" == '["release-note"]' ]] || fail "${note_wf} must have exactly the release-note job"
[[ "$(show "${note_wf}" | yq '[.jobs[].steps[] | select(has("run")) | .run | select(test("[$][{][{]"))] | length')" == 0 ]] || fail "${note_wf} inlines a \${{ }} template in run:"
[[ "$(show "${note_wf}" | yq -o=json -I=0 '[.jobs[].steps[] | select(has("run")) | .run]')" == "[\"nix develop .#cd -c ./${note_sh}\"]" ]] || fail "${note_wf} must run only ${note_sh} in the cd shell"
[[ "$(show "${note_wf}" | yq '[.jobs[].steps[] | select(has("uses")) | .uses | select(test("^AtomiCloud/actions[.]setup-nix@") | not)] | length')" == 0 ]] || fail "${note_wf} uses an action other than setup-nix"
# shellcheck disable=SC2016
[[ "$(show "${note_sh}" | grep -Ev '^(#|set -euo pipefail$|$)')" == 'echo "Released ${VERSION}"' ]] || fail "${note_sh} must only echo the release"
rc=0
hits="$(git -c core.quotePath=false grep -n -i -E 'helm|chart|docker|image' "${tree}" -- "${note_wf}" "${note_sh}")" || rc=$?
[[ ${rc} -le 1 ]] || fail "git grep failed (exit ${rc})"
[[ -z ${hits} ]] || fail "the release-note path names an image or chart:"$'\n'"${hits}"
[[ "$(show Taskfile.yaml | yq '.includes | (has("docker") or has("helm"))')" == false ]] || fail "Taskfile.yaml still includes docker/helm"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker" or .package-ecosystem == "helm")] | length')" == 0 ]] || fail "dependabot.yml still has a docker/helm entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|dockerd|hadolint|helm|helm-docs|helmlint|kubeconform|kyverno)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes a D/H binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker|helm|distroless|nonroot"))] | length')" == 0 ]] || fail "features.json still has a docker/helm row"
if grep -Eqi '^# (docker|helm)' <<<"$(show CLAUDE.md)"; then fail "CLAUDE.md still has a Docker/Helm section"; fi
if grep -Eq '^(docker|dockerd|hadolint|helm|helm-docs|helmlint) ' <<<"$(show probes/binary-smoke.ts)"; then fail "binary-smoke.ts still smokes a D/H binary"; fi
if grep -q ImagePolicy <<<"$(show probes/lib/go.ts)"; then fail "probes/lib/go.ts still carries the image-policy helpers"; fi

# Binaries are not checked: the whole infralint/infrautils bundles keep docker and helm on PATH.
for f in nix/packages.nix nix/env.nix; do
  if grep -v '^ *#' <<<"$(show "${f}")" | grep -Ec '(^|[^A-Za-z0-9-])(infralint-docker|infrautils-docker|docker|docker-client|hadolint|skopeo|kubernetes-helm|helm|helm-docs|helmlint)([^A-Za-z0-9-]|$)' >/dev/null; then
    fail "${f} declares a docker/helm-carrying package"
  fi
done

for f in .github/workflows/ci.yaml .github/workflows/cd.yaml "${publish}" "${note_wf}" .github/dependabot.yml Taskfile.yaml dlint.yaml; do
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

echo "✅ stripped-axis-absence: no D/H path, reference, entry, or nix package; cd.yaml is release + publish, the release note publishes nothing; edited files valid"
