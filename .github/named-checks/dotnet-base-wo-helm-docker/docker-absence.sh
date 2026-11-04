#!/usr/bin/env bash
set -euo pipefail

# Nothing of D survives: no D path, no reference to one, no D job, include,
# Dependabot entry, dlint smoke or probe row, no docker-axis nix slice, and no
# docker binary in the default shell. The many-owner files the strip edited
# still parse and lint.

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
  .github/workflows/cd.yaml
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
)
# Strings no remaining file may contain (workspace's D_TOKENS, plus cd.yaml and
# infra/, which leave with D once H is gone).
D_TOKENS=(
  infra/Dockerfile .dockerignore reusable-docker Taskfile.docker docker.sh
  docker-push standards/docker docker/index.md docker-build
  '](infra)' 'infra/' workflows/cd.yaml 'docker:build' 'docker:run'
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
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files still reference removed D paths:"$'\n'"${hits}"

# --- anchored entries -------------------------------------------------------------
show() { git show "${tree}:$1"; }
[[ "$(show .github/workflows/ci.yaml | yq '[.jobs[] | select(.uses // "" | test("docker"))] | length')" == 0 ]] || fail "ci.yaml still calls a docker workflow"
[[ "$(show .github/workflows/ci.yaml | yq '.jobs | has("docker")')" == false ]] || fail "ci.yaml still has a docker job"
[[ "$(show Taskfile.yaml | yq '.includes | has("docker")')" == false ]] || fail "Taskfile.yaml still includes docker"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker")] | length')" == 0 ]] || fail "dependabot.yml still has a docker entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|dockerd|hadolint|skopeo)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes a D binary"
[[ "$(show dlint.yaml | yq '[.checks["ci-wiring"].orchestrators[] | select(. == ".github/workflows/cd.yaml")] | length')" == 0 ]] || fail "dlint.yaml still wires cd.yaml"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker"))] | length')" == 0 ]] || fail "features.json still has a docker row"
if show CLAUDE.md | grep -qi '^# docker'; then fail "CLAUDE.md still has a Docker section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(docker|dockerd|hadolint|skopeo) '; then fail "binary-smoke.ts still smokes a D binary"; fi

# --- nix: no slice or package that carries D by content -------------------------------
for f in nix/packages.nix nix/env.nix; do
  if show "${f}" | grep -v '^ *#' | grep -Eq '(^|[^A-Za-z0-9-])(infralint-docker|infrautils-docker|infralint|infrautils|docker|docker-client|hadolint|skopeo)([^A-Za-z0-9-]|$)'; then
    fail "${f} declares a docker-carrying package"
  fi
done

# --- the shell itself: no docker binary, the kept toolchain still there -------------
# -i clears the caller's PATH, so only the shell's own inputs resolve. The
# positive control proves the lookup is not vacuous.
# shellcheck disable=SC2016
nix develop -i --keep HOME .#default -c bash -c '
  set -u
  bad=0
  for b in docker dockerd hadolint skopeo; do
    if p="$(command -v "$b")"; then echo "❌ default shell carries $b at $p" >&2; bad=1; fi
  done
  for b in dotnet tofu kubeconform shellcheck; do
    command -v "$b" >/dev/null || { echo "❌ control: default shell lost $b" >&2; bad=1; }
  done
  exit "$bad"
' || fail "default shell docker absence / kept-toolchain presence"

# --- the many-owner files the strip edited still parse and lint ---------------------
for f in .github/workflows/ci.yaml .github/dependabot.yml Taskfile.yaml dlint.yaml; do
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

echo "✅ docker-absence: no D path, reference, entry, nix slice or shell binary; edited files valid"
