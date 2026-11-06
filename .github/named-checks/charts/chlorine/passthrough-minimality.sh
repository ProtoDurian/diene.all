#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
parent_sha="$(tr -d '[:space:]' <"$(dirname "$0")/parent.sha")"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0
fail() {
  echo "❌ $*" >&2
  failed=1
}

[[ ${parent_sha} =~ ^[0-9a-f]{40}$ ]] || { echo "❌ parent.sha '${parent_sha}' is not a full 40-hex commit sha" >&2 && exit 1; }
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ helm-wrapper .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

git archive "${tree}" | tar -x -C "${work}"
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

# Split a helpers file into one file per define, named by the define with its chart prefix removed.
split_helpers() {
  local src="$1" out="$2" prefix="$3"
  mkdir -p "${out}"
  awk -v out="${out}" -v prefix="${prefix}" '
    /^\{\{- define "/ { name = $0; sub(/^\{\{- define "/, "", name); sub(/".*/, "", name)
      if (index(name, prefix) != 1) { print "foreign " name > "/dev/stderr"; bad = 1 }
      name = substr(name, length(prefix) + 1); file = out "/" name; depth = 0 }
    file != "" { line = $0; gsub("\"" prefix, "\"HELPER.", line); print line >> file
      depth += gsub(/\{\{-? *(define|if|range|with)[ (]/, "&", $0); depth -= gsub(/\{\{-? *end *-?\}\}/, "&", $0)
      if (depth == 0) { close(file); file = "" } next }
    /[^[:space:]]/ { print "stray " $0 > "/dev/stderr"; bad = 1 }
    END { exit bad }' "${src}"
}

own_templates="$(grep -E '^chart/templates/' <<<"${files}" | sort)"
[[ ${own_templates} == $'chart/templates/_helpers.tpl\nchart/templates/validate.yaml' ]] ||
  fail "chart/templates is not exactly the skeleton (_helpers.tpl + validate.yaml): ${own_templates//$'\n'/ }"
bespoke="$(grep -E '^chart/(crds/|files/|templates/NOTES\.txt$)' <<<"${files}" || true)"
[[ -z ${bespoke} ]] || fail "chart ships its own crds/, files/ or NOTES.txt: ${bespoke//$'\n'/ }"

git show "${parent_sha}:chart/templates/_helpers.tpl" >"${work}/parent-helpers.tpl"
if ! split_helpers "${work}/parent-helpers.tpl" "${work}/parent" diene-helm-wrapper. 2>"${work}/split.err"; then
  fail "parent helpers at ${parent_sha} do not split: $(cat "${work}/split.err")"
fi
if [[ -f "${work}/chart/templates/_helpers.tpl" ]]; then
  if ! split_helpers "${work}/chart/templates/_helpers.tpl" "${work}/own" chlorine. 2>"${work}/split.err"; then
    fail "_helpers.tpl holds something other than chlorine.* helper defines: $(cat "${work}/split.err")"
  fi
  for helper in "${work}"/own/*; do
    [[ -e ${helper} ]] || { fail "_helpers.tpl defines no helper" && break; }
    name="$(basename "${helper}")"
    if [[ ! -f "${work}/parent/${name}" ]]; then
      fail "helper chlorine.${name} is bespoke: the helm-wrapper skeleton has no diene-helm-wrapper.${name}"
    elif ! cmp -s "${helper}" "${work}/parent/${name}"; then
      fail "helper chlorine.${name} differs from the skeleton's diene-helm-wrapper.${name}:"$'\n'"$(diff "${work}/parent/${name}" "${helper}" || true)"
    fi
  done
fi
if [[ -f "${work}/chart/templates/validate.yaml" ]]; then
  stray="$(rg -v '^\{\{- include "chlorine\.[A-Za-z]+" \. -\}\}$' "${work}/chart/templates/validate.yaml" || true)"
  [[ -z ${stray} ]] || fail "validate.yaml does more than invoke skeleton guards: ${stray}"
fi

[[ "$(git show "${tree}:chart/Chart.yaml" | yq -o=json -I=0 '[.dependencies[] | .name + "@" + .alias]')" == '["reloader@upstream"]' ]] ||
  fail "chart/Chart.yaml depends on more than the vendored reloader (alias upstream)"
sample="$(grep -E '^chart/charts/' <<<"${files}" | grep -vE '^chart/charts/reloader-[0-9.]+\.tgz$' || true)"
[[ -z ${sample} ]] || fail "vendored archives beyond reloader are tracked: ${sample//$'\n'/ }"

stacks=("" "--values chart/values.example.yaml" "--values chart/values.example.yaml --values chart/values.lapras.yaml")
for stack in "${stacks[@]}"; do
  # shellcheck disable=SC2086
  if ! (cd "${work}" && helm template chlorine chart --namespace reloader ${stack}) >"${work}/render.yaml" 2>"${work}/render.err"; then
    fail "stack '${stack}' does not render: $(head -3 "${work}/render.err")"
    continue
  fi
  own="$(rg '^# Source: ' "${work}/render.yaml" | rg -v '^# Source: chlorine/charts/upstream/templates/' || true)"
  [[ -z ${own} ]] || fail "stack '${stack}' renders objects from chlorine's own templates: ${own//$'\n'/ }"
  yq eval-all -o=json '.' "${work}/render.yaml" | jq -s 'map(select(.kind != null))' >"${work}/render.json"
  jq -e 'map(select(.kind == "Deployment")) | length == 1' "${work}/render.json" >/dev/null ||
    fail "stack '${stack}' renders no Reloader controller (vacuous)"
  extra="$(jq -r '.[] | select(.kind | IN("Job", "Pod", "CronJob", "Secret", "ExternalSecret", "ClusterExternalSecret", "ConfigMap", "ServiceMonitor", "PodMonitor", "PrometheusRule")) | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${extra} ]] || fail "stack '${stack}' renders a hook Job, Secret, config or monitoring object: ${extra//$'\n'/ }"
  hooks="$(jq -r '.[] | select(.metadata.annotations // {} | has("helm.sh/hook") or has("argocd.argoproj.io/hook")) | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${hooks} ]] || fail "stack '${stack}' renders a hook: ${hooks//$'\n'/ }"
done

ACTIVE=(':!.github/named-checks/**' ':!Changelog.md' ':!chart/charts/**' ':!*.md' ':!docs/**' ':!.gitignore')
scan() {
  local where="$1" rc=0
  shift
  git -c core.quotePath=false grep -n -I "$@" "${tree}" -- "${where}" "${ACTIVE[@]}" || rc=$?
  [[ ${rc} -le 1 ]] || { echo "❌ git grep failed (${rc}) for $*" >&2 && exit 2; }
}
surface="$(grep -E '^(config/|schemas/|probes/|chart/files/|scripts/local/vendor-chart-config\.sh$)' <<<"${files}" || true)"
[[ -z ${surface} ]] || fail "helm-wrapper sample, probe or config vendoring surface is tracked: ${surface//$'\n'/ }"
hits="$(scan . -E 'vendor-chart-config|chart/files/config|\.Files\.(Glob|Get)|podinfo')"
[[ -z ${hits} ]] || fail "sample app or config vendoring is still wired:"$'\n'"${hits}"
hits="$(scan chart -E 'kind: *(Cluster)?ExternalSecret\b|serviceFolder|sharedFolder|secretPrefix|regexp:')"
[[ -z ${hits} ]] || fail "ExternalSecret folder-prefix mapping is present:"$'\n'"${hits}"
hits="$(scan . -i -e doppler -e bromine)"
[[ -z ${hits} ]] || fail "bromine/Doppler is wired:"$'\n'"${hits}"

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

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ passthrough-minimality: own templates = skeleton helpers + guard only (zero own objects); no sample, hook, Job, Secret, config vendoring, ES mapping, monitoring, docker axis or bromine/Doppler"
