#!/usr/bin/env bash
set -euo pipefail

# Nothing of D survives, proved by files: no D path, no reference to one, no D
# job, include, Dependabot entry, dlint smoke or probe row, and CD is the
# release-only stub. docker on PATH from the whole infralint bundle is fine.
# The many-owner files the strip edited still parse and lint.

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
# Strings no remaining file may contain (workspace's D_TOKENS, plus infra/,
# which leaves with D once H is gone, and go-base's image policy).
D_TOKENS=(
  infra/Dockerfile .dockerignore reusable-docker Taskfile.docker docker.sh
  docker-push standards/docker docker/index.md docker-build
  '](infra)' 'infra/' 'docker:build' 'docker:run'
  go-image-policy distroless-base-policy nonroot-image-policy
)
# The declaration itself; machine-maintained history; the probe harness whose
# command-string fixtures are generic and name no axis file.
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**')

# --- paths ----------------------------------------------------------------------
for p in "${D_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "D path still tracked: ${p}"; fi
done

# --- references -------------------------------------------------------------------
args=()
for t in "${D_TOKENS[@]}"; do args+=(-e "${t}"); done
rc=0
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}")" || rc=$?
[[ ${rc} -le 1 ]] || fail "git grep failed (exit ${rc})"
[[ -z ${hits} ]] || fail "files still reference removed D paths:"$'\n'"${hits}"

# --- anchored entries -------------------------------------------------------------
show() { git show "${tree}:$1"; }
[[ "$(show .github/workflows/ci.yaml | yq '[.jobs[] | select(.uses // "" | test("docker"))] | length')" == 0 ]] || fail "ci.yaml still calls a docker workflow"
[[ "$(show .github/workflows/ci.yaml | yq '.jobs | has("docker")')" == false ]] || fail "ci.yaml still has a docker job"
[[ "$(show Taskfile.yaml | yq '.includes | has("docker")')" == false ]] || fail "Taskfile.yaml still includes docker"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker")] | length')" == 0 ]] || fail "dependabot.yml still has a docker entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|dockerd|hadolint)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes a D binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker|distroless|nonroot"))] | length')" == 0 ]] || fail "features.json still has a docker row"
if show CLAUDE.md | grep -qi '^# docker'; then fail "CLAUDE.md still has a Docker section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(docker|dockerd|hadolint) '; then fail "binary-smoke.ts still smokes a D binary"; fi
if show probes/lib/go.ts | grep -q ImagePolicy; then fail "probes/lib/go.ts still carries the image-policy helpers"; fi

# --- the CD stub: exactly the release job, which publishes nothing ------------------
cd_wf=.github/workflows/cd.yaml
note_wf='.github/workflows/⚡reusable-release-note.yaml'
note_sh=scripts/ci/release-note.sh
for p in "${cd_wf}" "${note_wf}" "${note_sh}"; do
  git cat-file -e "${tree}:${p}" 2>/dev/null || fail "CD stub file missing: ${p}"
done
[[ "$(show "${cd_wf}" | yq -o=json -I=0 '.on')" == '{"push":{"tags":["v*.*.*"]}}' ]] || fail "cd.yaml must run on v*.*.* tags only"
[[ "$(show "${cd_wf}" | yq -o=json -I=0 '.jobs | keys')" == '["release"]' ]] || fail "cd.yaml must have exactly the release job"
[[ "$(show "${cd_wf}" | yq '.jobs.release.uses')" == "./${note_wf}" ]] || fail "cd.yaml release job must call ${note_wf}"
[[ "$(show "${cd_wf}" | yq -o=json -I=0 '.jobs.release.permissions')" == '{"contents":"read"}' ]] || fail "cd.yaml release job must grant only contents: read"
# shellcheck disable=SC2016
[[ "$(show "${cd_wf}" | yq -o=json -I=0 '.jobs.release.with')" == '{"version":"${{ github.ref_name }}"}' ]] || fail "cd.yaml release job must pass only version: the tag"
[[ "$(show dlint.yaml | yq '[.checks["ci-wiring"].orchestrators[] | select(. == ".github/workflows/cd.yaml")] | length')" == 1 ]] || fail "dlint.yaml must wire cd.yaml as an orchestrator"
[[ "$(show "${note_wf}" | yq -o=json -I=0 '.jobs | keys')" == '["release-note"]' ]] || fail "${note_wf} must have exactly the release-note job"
[[ "$(show "${note_wf}" | yq '[.jobs[].steps[] | select(has("run")) | .run | select(test("[$][{][{]"))] | length')" == 0 ]] || fail "${note_wf} inlines a \${{ }} template in run:"
[[ "$(show "${note_wf}" | yq -o=json -I=0 '[.jobs[].steps[] | select(has("run")) | .run]')" == "[\"nix develop .#cd -c ./${note_sh}\"]" ]] || fail "${note_wf} must run only ${note_sh} in the cd shell"
[[ "$(show "${note_wf}" | yq '[.jobs[].steps[] | select(has("uses")) | .uses | select(test("^AtomiCloud/actions[.]setup-nix@") | not)] | length')" == 0 ]] || fail "${note_wf} uses an action other than setup-nix"
# shellcheck disable=SC2016
[[ "$(show "${note_sh}" | grep -Ev '^(#|set -euo pipefail$|$)')" == 'echo "Released ${VERSION}"' ]] || fail "${note_sh} must only echo the release"

# --- the many-owner files the strip edited still parse and lint ---------------------
for f in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/dependabot.yml Taskfile.yaml dlint.yaml; do
  yq e '.' "${f}" >/dev/null 2>&1 || fail "${f} is not valid YAML"
done
jq -e . probes/features.json >/dev/null 2>&1 || fail "probes/features.json is not valid JSON"
actionlint -config-file .github/actionlint.yaml .github/workflows/*.y*ml >"${work}/actionlint.out" 2>&1 || fail "actionlint failed: $(head -5 "${work}/actionlint.out")"
task --list-all >"${work}/task.out" 2>&1 || fail "task --list-all failed: $(head -5 "${work}/task.out")"
dlint ci-wiring >"${work}/dlint.out" 2>&1 || fail "dlint ci-wiring failed: $(head -5 "${work}/dlint.out")"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ docker-absence: no D path, reference, entry or smoke line; CD is the release-only stub; edited files valid"
