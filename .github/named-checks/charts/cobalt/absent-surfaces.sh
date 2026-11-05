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
ACTIVE=(':!.github/named-checks/**' ':!Changelog.md' ':!chart/charts/**' ':!*.md' ':!docs/**' ':!.gitignore')
# scan <pathspec> <git-grep args...>; a grep error is a failure, not an empty result.
scan() {
  local where="$1" rc=0
  shift
  git -c core.quotePath=false grep -n -I "$@" "${tree}" -- "${where}" "${ACTIVE[@]}" || rc=$?
  [[ ${rc} -le 1 ]] || { echo "❌ git grep failed (${rc}) for $*" >&2 && exit 2; }
}

hits="$(scan chart/templates -E 'argocd\.argoproj\.io/hook:|helm\.sh/hook:')"
[[ -z ${hits} ]] || fail "cobalt templates declare hooks:"$'\n'"${hits}"
stacks=("--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")
for stack in "${stacks[@]}"; do
  # shellcheck disable=SC2086
  if ! (cd "${work}" && helm template cobalt chart --namespace secrets ${stack}) >"${work}/render.yaml" 2>"${work}/render.err"; then
    fail "stack '${stack}' does not render: $(head -3 "${work}/render.err")"
    continue
  fi
  yq eval-all -o=json '.' "${work}/render.yaml" | jq -s 'map(select(.kind != null))' >"${work}/render.json"
  jq -e '(map(select(.kind == "ClusterSecretStore")) | length) == 1 and (map(select(.kind == "Deployment")) | length) == 3' "${work}/render.json" >/dev/null ||
    fail "stack '${stack}' renders no store or ESO workloads (vacuous)"
  hooks="$(jq -r '.[] | select(.kind == "Job" or .kind == "Pod" or .kind == "CronJob") | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${hooks} ]] || fail "stack '${stack}' renders a Job or Pod (pre-sync hook surface): ${hooks//$'\n'/ }"
  hooks="$(jq -r '.[] | select(.metadata.annotations // {} | (."argocd.argoproj.io/hook" // "" | test("PreSync")) or (."helm.sh/hook" // "" | test("pre-install|pre-upgrade"))) | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${hooks} ]] || fail "stack '${stack}' renders a pre-sync hook: ${hooks//$'\n'/ }"
  es="$(jq -r '.[] | select(.kind == "ExternalSecret" or .kind == "ClusterExternalSecret") | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${es} ]] || fail "stack '${stack}' renders an ExternalSecret: ${es//$'\n'/ }"
done

vendored="$(grep -E '^(config/|chart/files/|scripts/local/vendor-chart-config\.sh$)' <<<"${files}" || true)"
[[ -z ${vendored} ]] || fail "config vendoring surface is tracked: ${vendored//$'\n'/ }"
hits="$(scan . -E 'vendor-chart-config|chart/files/config|\.Files\.(Glob|Get)')"
[[ -z ${hits} ]] || fail "config vendoring is still wired:"$'\n'"${hits}"

hits="$(scan chart -E 'kind: *(Cluster)?ExternalSecret\b|serviceFolder|sharedFolder|secretPrefix|regexp:')"
[[ -z ${hits} ]] || fail "ExternalSecret folder-prefix mapping is present:"$'\n'"${hits}"

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

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ absent-surfaces: no pre-sync hook Job, config vendoring, ES folder-prefix mapping or docker axis"
