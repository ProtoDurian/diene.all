#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
tree="$(git write-tree)"
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

for p in "${D_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "D path reintroduced: ${p}"; fi
done

args=()
for t in "${D_TOKENS[@]}"; do args+=(-e "${t}"); done
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files reference removed D paths:"$'\n'"${hits}"

show() { git show "${tree}:$1"; }
[[ "$(show .github/workflows/ci.yaml | yq '[.jobs | keys | .[] | select(test("docker"))] | length')" == 0 ]] || fail "ci.yaml has a docker job"
[[ "$(show .github/workflows/ci.yaml | yq '[.jobs[] | select(.uses // "" | test("docker"))] | length')" == 0 ]] || fail "ci.yaml calls a docker workflow"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker")] | length')" == 0 ]] || fail "dependabot.yml has a docker entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|hadolint)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml smokes a D binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker"))] | length')" == 0 ]] || fail "features.json has a docker row"
if show CLAUDE.md | grep -qi '^# docker'; then fail "CLAUDE.md has a Docker section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(docker|hadolint) '; then fail "binary-smoke.ts smokes a D binary"; fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ docker-absence: the inherited Docker-free state holds"
