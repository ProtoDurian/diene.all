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
ACTIVE=(':!.github/named-checks/**' ':!Changelog.md' ':!*.md' ':!docs/**' ':!.gitignore')
scan() {
  local where="$1" rc=0
  shift
  git -c core.quotePath=false grep -n -I "$@" "${tree}" -- "${where}" "${ACTIVE[@]}" || rc=$?
  [[ ${rc} -le 1 ]] || { echo "❌ git grep failed (${rc}) for $*" >&2 && exit 2; }
}
show() { git show "${tree}:$1"; }

[[ "$(show chart/Chart.yaml | yq -o=json -I=0 '.dependencies // []')" == '[]' ]] || fail "chart/Chart.yaml declares an upstream dependency (zinc wraps nothing)"
sample="$(grep -E '^chart/charts/|^chart/Chart\.lock$|^schemas/|^chart/files/' <<<"${files}" || true)"
[[ -z ${sample} ]] || fail "vendored chart or helm-wrapper sample surface is tracked: ${sample//$'\n'/ }"

[[ "$(show Taskfile.yaml | yq '.tasks | has("update") or has("latest")')" == false ]] || fail "Taskfile.yaml has an update/latest task (no upstream to bump)"
latest="$(grep -E '^scripts/local/latest-chart-upstreams\.sh$' <<<"${files}" || true)"
[[ -z ${latest} ]] || fail "update/latest surface is tracked: ${latest}"
hits="$(scan . -E 'latest-chart-upstreams|helm dependency update')"
[[ -z ${hits} ]] || fail "update/latest is still wired:"$'\n'"${hits}"

hits="$(scan . -i -E 'bromine')"
[[ -z ${hits} ]] || fail "bromine is present:"$'\n'"${hits}"
hits="$(scan . -E 'reloader\.stakater\.com')"
[[ -z ${hits} ]] || fail "a Reloader annotation is present:"$'\n'"${hits}"
hits="$(scan chart/templates -E 'argocd\.argoproj\.io/hook|helm\.sh/hook')"
[[ -z ${hits} ]] || fail "zinc templates declare a hook:"$'\n'"${hits}"

for overlay in "" $(grep -E '^chart/values\.[a-z0-9]+\.yaml$' <<<"${files}" | sed 's/^chart\/values\.//; s/\.yaml$//'); do
  args=()
  [[ -z ${overlay} ]] || args=(--values "chart/values.${overlay}.yaml")
  if ! (cd "${work}" && helm template zinc chart --namespace certs "${args[@]}") >"${work}/render.yaml" 2>"${work}/render.err"; then
    fail "overlay '${overlay:-values.yaml}' does not render: $(head -3 "${work}/render.err")"
    continue
  fi
  yq eval-all -o=json '.' "${work}/render.yaml" | jq -s 'map(select(.kind != null))' >"${work}/render.json"
  jq -e 'any(.[]; .kind == "ClusterIssuer")' "${work}/render.json" >/dev/null || fail "overlay '${overlay:-values.yaml}' renders no ClusterIssuer (vacuous)"
  extra="$(jq -r '.[] | select(.kind != "ClusterIssuer" and .kind != "ExternalSecret") | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${extra} ]] || fail "overlay '${overlay:-values.yaml}' renders a workload, Job or sample object: ${extra//$'\n'/ }"
  hooks="$(jq -r '.[] | select(.metadata.annotations // {} | has("helm.sh/hook") or has("argocd.argoproj.io/hook")) | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${hooks} ]] || fail "overlay '${overlay:-values.yaml}' renders a hook: ${hooks//$'\n'/ }"
done

vendored="$(grep -E '^(config/|chart/files/|scripts/local/vendor-chart-config\.sh$)' <<<"${files}" || true)"
[[ -z ${vendored} ]] || fail "config vendoring surface is tracked: ${vendored//$'\n'/ }"
hits="$(scan . -E 'vendor-chart-config|chart/files/config|\.Files\.(Glob|Get)')"
[[ -z ${hits} ]] || fail "config vendoring is still wired:"$'\n'"${hits}"

docker_paths="$(grep -iE '(^|/)(Dockerfile[^/]*|Containerfile[^/]*|[^/]*\.(docker|container)file|\.dockerignore|docker-compose[^/]*|compose\.ya?ml|Taskfile\.docker\.ya?ml|docker\.sh|⚡reusable-docker\.ya?ml)$|^\.claude/skills/docker-push/|^docs/standards/docker/' <<<"${files}" || true)"
[[ -z ${docker_paths} ]] || fail "docker axis is tracked: ${docker_paths//$'\n'/ }"
hits="$(scan . -E '\b(docker|podman) (build|push|buildx)\b|\bbuildah\b|\bkaniko\b|docker/(build-push|setup-buildx|login)-action|reusable-docker|Taskfile\.docker')"
[[ -z ${hits} ]] || fail "image build/push is wired:"$'\n'"${hits}"
for f in .github/workflows/ci.yaml .github/workflows/cd.yaml; do
  [[ "$(show "${f}" | yq '.jobs | has("docker")')" == false ]] || fail "${f} has a docker job"
done
[[ "$(show Taskfile.yaml | yq '.includes | has("docker")')" == false ]] || fail "Taskfile.yaml includes docker"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker")] | length')" == 0 ]] || fail "dependabot.yml has a docker entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(docker|hadolint)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml smokes a docker binary"

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ absent-surfaces: no upstream, update/latest, bromine, Reloader annotation, pre-sync hook Job, workload, config vendoring or docker axis"
