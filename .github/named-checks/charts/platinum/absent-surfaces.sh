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

git archive "${tree}" | tar -x -C "${work}"
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"
EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!chart/charts/**')
ACTIVE=("${EXEMPT[@]}" ':!*.md' ':!docs/**' ':!.gitignore')
# scan <pathspec> <git-grep args...>; a grep error is a failure, not an empty result.
scan() {
  local where="$1" rc=0
  shift
  git -c core.quotePath=false grep -n -I "$@" "${tree}" -- "${where}" "${ACTIVE[@]}" || rc=$?
  [[ ${rc} -le 1 ]] || { echo "❌ git grep failed (${rc}) for $*" >&2 && exit 2; }
}

hits="$(scan chart/templates -E 'argocd\.argoproj\.io/hook:|helm\.sh/hook:')"
[[ -z ${hits} ]] || fail "wrapper templates declare hooks:"$'\n'"${hits}"
stacks=("" "--values chart/values.ditto.yaml" "--values chart/values.pichu.yaml --values chart/values.ruby.yaml" "--values chart/values.opal.yaml --values chart/values.entei.yaml")
for stack in "${stacks[@]}"; do
  # shellcheck disable=SC2086
  if ! (cd "${work}" && helm template platinum chart --namespace sulfoxide ${stack}) >"${work}/render.yaml" 2>"${work}/render.err"; then
    fail "stack '${stack:-values.yaml}' does not render: $(head -3 "${work}/render.err")"
    continue
  fi
  yq eval-all -o=json '.' "${work}/render.yaml" | jq -s 'map(select(.kind != null))' >"${work}/render.json"
  jq -e 'map(select(.kind == "Gateway")) | length == 1' "${work}/render.json" >/dev/null || fail "stack '${stack:-values.yaml}' renders no shared Gateway (vacuous)"
  es="$(jq -r '.[] | select(.kind == "ExternalSecret" or .kind == "SecretStore" or .kind == "Secret") | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${es} ]] || fail "stack '${stack:-values.yaml}' renders secret wiring: ${es//$'\n'/ }"
  hooks="$(jq -r '.[] | select(.kind == "Job" or .kind == "Pod") | select(.metadata.annotations // {} | (."argocd.argoproj.io/hook" // "" | test("PreSync")) or (."helm.sh/hook" // "" | test("pre-install|pre-upgrade"))) | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${hooks} ]] || fail "stack '${stack:-values.yaml}' renders a pre-sync hook: ${hooks//$'\n'/ }"
done

vendored="$(grep -E '^(config/|chart/files/|scripts/local/vendor-chart-config\.sh$)' <<<"${files}" || true)"
[[ -z ${vendored} ]] || fail "config vendoring surface is tracked: ${vendored//$'\n'/ }"
hits="$(scan . -E 'vendor-chart-config|chart/files/config|\.Files\.(Glob|Get)')"
[[ -z ${hits} ]] || fail "config vendoring is still wired:"$'\n'"${hits}"

docker_paths="$(grep -iE '(^|/)(Dockerfile[^/]*|Containerfile[^/]*|[^/]*\.(docker|container)file|\.dockerignore|docker-compose[^/]*|compose\.ya?ml|Taskfile\.docker\.ya?ml|docker\.sh|⚡reusable-docker\.ya?ml)$|^\.claude/skills/docker-push/|^docs/standards/docker/' <<<"${files}" || true)"
[[ -z ${docker_paths} ]] || fail "docker axis is tracked: ${docker_paths//$'\n'/ }"
hits="$(scan . -E '\b(docker|podman) (build|push|buildx)\b|\bbuildah\b|\bkaniko\b|docker/(build-push|setup-buildx|login)-action|reusable-docker|Taskfile\.docker')"
[[ -z ${hits} ]] || fail "image build/push is wired:"$'\n'"${hits}"
show() { git show "${tree}:$1"; }
for f in .github/workflows/ci.yaml .github/workflows/cd.yaml; do
  [[ "$(show "${f}" | yq '.jobs | has("docker")')" == false ]] || fail "${f} has a docker job"
done
[[ "$(show Taskfile.yaml | yq '.includes | has("docker")')" == false ]] || fail "Taskfile.yaml includes docker"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker")] | length')" == 0 ]] || fail "dependabot.yml has a docker entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|hadolint)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml smokes a docker binary"

hits="$(scan chart -E 'ExternalSecret|secretPrefix|dataFrom|rewrite:')"
[[ -z ${hits} ]] || fail "ES folder-prefix mapping is wired:"$'\n'"${hits}"
[[ "$(show chart/values.yaml | yq 'has("secret")')" == false ]] || fail "chart/values.yaml declares a secret block"

hits="$(scan . -i -E 'doppler|bromine')"
[[ -z ${hits} ]] || fail "doppler or bromine in active inputs:"$'\n'"${hits}"

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ absent-surfaces: no pre-sync hook Job, config vendoring, ES folder-prefix mapping, docker axis or bromine/Doppler"
