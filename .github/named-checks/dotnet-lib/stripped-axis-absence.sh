#!/usr/bin/env bash
set -euo pipefail

# The inherited strip state still holds: nothing of D (docker) or H (helm)
# survives — no axis path, no reference to one, no axis job, include, hook,
# Dependabot entry, dlint smoke or probe row, no axis-carrying nix package, and
# no axis binary in the default shell. dotnet-lib re-adds cd.yaml for its NuGet
# publish job only, so cd.yaml is checked for axis jobs instead of absence.

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
# which dotnet-lib re-adds for publish).
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
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|dockerd|hadolint|skopeo|helm|helm-docs|helmlint|kubeconform|kyverno)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes a D/H binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker|helm"))] | length')" == 0 ]] || fail "features.json still has a docker/helm row"
if show CLAUDE.md | grep -Eqi '^# (docker|helm)'; then fail "CLAUDE.md still has a Docker/Helm section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(docker|dockerd|hadolint|skopeo|helm|helm-docs|helmlint|kubeconform|kyverno) '; then fail "binary-smoke.ts still smokes a D/H binary"; fi

# --- nix: no slice or package that carries D by content -------------------------------
for f in nix/packages.nix nix/env.nix; do
  if show "${f}" | grep -v '^ *#' | grep -Eq '(^|[^A-Za-z0-9-])(infralint-docker|infrautils-docker|infralint|infrautils|docker|docker-client|hadolint|skopeo|kubernetes-helm|helm|helm-docs|helmlint)([^A-Za-z0-9-]|$)'; then
    fail "${f} declares a docker/helm-carrying package"
  fi
done

# --- the shell itself: no docker binary, the kept toolchain still there -------------
# -i clears the caller's PATH, so only the shell's own inputs resolve. The
# positive control proves the lookup is not vacuous.
# shellcheck disable=SC2016
nix develop -i --keep HOME .#default -c bash -c '
  set -u
  bad=0
  for b in docker dockerd hadolint skopeo helm helm-docs helmlint; do
    if p="$(command -v "$b")"; then echo "❌ default shell carries $b at $p" >&2; bad=1; fi
  done
  for b in dotnet tofu kubeconform shellcheck; do
    command -v "$b" >/dev/null || { echo "❌ control: default shell lost $b" >&2; bad=1; }
  done
  exit "$bad"
' || fail "default shell docker/helm absence / kept-toolchain presence"

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

echo "✅ stripped-axis-absence: no D/H path, reference, entry, nix package or shell binary; cd.yaml is publish-only; edited files valid"
