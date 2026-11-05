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
scan() {
  local where="$1" rc=0
  shift
  git -c core.quotePath=false grep -n -I "$@" "${tree}" -- "${where}" "${ACTIVE[@]}" || rc=$?
  [[ ${rc} -le 1 ]] || { echo "❌ git grep failed (${rc}) for $*" >&2 && exit 2; }
}

hits="$(scan chart/templates -E '^\s*kind:')"
[[ -z ${hits} ]] || fail "sulfur templates author a resource (pure passthrough; no sample or issuer surface):"$'\n'"${hits}"
hits="$(scan chart/templates -E 'argocd\.argoproj\.io/hook|helm\.sh/hook')"
[[ -z ${hits} ]] || fail "sulfur templates declare a hook:"$'\n'"${hits}"
sample="$(grep -E '^chart/charts/podinfo|^schemas/|^chart/files/' <<<"${files}" || true)"
[[ -z ${sample} ]] || fail "helm-wrapper sample surface is tracked: ${sample//$'\n'/ }"
[[ "$(git show "${tree}:chart/Chart.yaml" | yq -o=json -I=0 '[.dependencies[].name]')" == '["cert-manager"]' ]] || fail "chart/Chart.yaml depends on more than cert-manager"
stacks=("" "--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")
for stack in "${stacks[@]}"; do
  # shellcheck disable=SC2086
  if ! (cd "${work}" && helm template sulfur chart --namespace certs ${stack}) >"${work}/render.yaml" 2>"${work}/render.err"; then
    fail "stack '${stack}' does not render: $(head -3 "${work}/render.err")"
    continue
  fi
  yq eval-all -o=json '.' "${work}/render.yaml" | jq -s 'map(select(.kind != null))' >"${work}/render.json"
  jq -e '(map(select(.kind == "Deployment")) | length) == 3' "${work}/render.json" >/dev/null ||
    fail "stack '${stack}' renders no cert-manager workloads (vacuous)"
  jobs="$(jq -r '.[] | select(.kind == "Job" or .kind == "Pod" or .kind == "CronJob") | select((.kind + "/" + .metadata.name) != "Job/sulfur-cert-manager-startupapicheck" or .metadata.annotations["helm.sh/hook"] != "post-install") | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${jobs} ]] || fail "stack '${stack}' renders a Job or Pod beyond upstream's post-install startupapicheck: ${jobs//$'\n'/ }"
  hooks="$(jq -r '.[] | select(.metadata.annotations // {} | (."argocd.argoproj.io/hook" // "" | test("PreSync")) or (."helm.sh/hook" // "" | test("pre-install|pre-upgrade"))) | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${hooks} ]] || fail "stack '${stack}' renders a pre-sync hook: ${hooks//$'\n'/ }"
  es="$(jq -r '.[] | select(.kind == "ExternalSecret" or .kind == "ClusterExternalSecret" or .kind == "Secret") | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${es} ]] || fail "stack '${stack}' renders a Secret or ExternalSecret (sulfur ships no credentials): ${es//$'\n'/ }"
done

vendored="$(grep -E '^(config/|chart/files/|scripts/local/vendor-chart-config\.sh$)' <<<"${files}" || true)"
[[ -z ${vendored} ]] || fail "config vendoring surface is tracked: ${vendored//$'\n'/ }"
hits="$(scan . -E 'vendor-chart-config|chart/files/config|\.Files\.(Glob|Get)')"
[[ -z ${hits} ]] || fail "config vendoring is still wired:"$'\n'"${hits}"

hits="$(scan chart -E 'kind: *(Cluster)?ExternalSecret\b|serviceFolder|sharedFolder|secretPrefix|regexp:')"
[[ -z ${hits} ]] || fail "ExternalSecret folder-prefix mapping is present:"$'\n'"${hits}"

hits="$(scan chart -iE 'eks\.amazonaws\.com/role-arn|iam\.gke\.io|azure\.workload\.identity|apiTokenSecretRef|api-token')"
[[ -z ${hits} ]] || fail "cloud IAM or Cloudflare credential wiring is present (zinc's issuer concern):"$'\n'"${hits}"

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
echo "✅ absent-surfaces: no sample/issuer template, pre-sync hook, extra Job, credential, config vendoring, ES folder-prefix mapping or docker axis"
