#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
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
OBS='ServiceMonitor|PodMonitor|PrometheusRule|Probe|ScrapeConfig|GrafanaDashboard|GrafanaAlertRuleGroup|AlertmanagerConfig'

paths="$(grep -E '(^|/)languages/[^/]+\.md$|^(docs/standards|\.claude/skills)/(observability|grafana-dashboards)(/|$)|^docs/developer/standard/|(^|/)(dashboards?|alerts?)/|\.dashboard\.json$|^chart/(files|dashboards|alerts)/' <<<"${files}" | grep -v '^\.claude/skills/vendor/' || true)"
[[ -z ${paths} ]] || fail "observability or sample payload is tracked: ${paths//$'\n'/ }"
hits="$(git -c core.quotePath=false grep -n -I -E "kind: *(${OBS})\b" "${tree}" -- chart ':!chart/charts/**' || true)"
[[ -z ${hits} ]] || fail "the wrapper authors an observability object:"$'\n'"${hits}"

stacks=("")
for f in "${work}"/chart/values.*.yaml; do
  [[ $(basename "${f}") == values.canary.yaml ]] || stacks+=("--values ${f#"${work}/"}")
done
stacks+=("--values chart/values.serving.yaml --values chart/values.canary.yaml")
on=0
for stack in "${stacks[@]}"; do
  # shellcheck disable=SC2086
  if ! (cd "${work}" && helm template xenon chart --namespace metrics ${stack}) >"${work}/render.yaml" 2>"${work}/render.err"; then
    fail "stack '${stack}' does not render: $(head -3 "${work}/render.err")"
    continue
  fi
  yq eval-all -o=json '.' "${work}/render.yaml" | jq -s 'map(select(.kind != null))' >"${work}/render.json"
  kinds="$(jq -r 'map(.kind + "/" + .metadata.name) | .[]' "${work}/render.json" | sort)"
  [[ -n ${kinds} ]] && on=$((on + 1))
  extra="$(jq -r --arg obs "^(${OBS})$" '.[] | select((.kind | test($obs)) or (.kind == "ConfigMap") or (.kind == "Service" and (.spec.ports // [] | any(.name == "metrics")))) | .kind + "/" + .metadata.name' "${work}/render.json")"
  [[ -z ${extra} ]] || fail "stack '${stack}' ships observability or sample payload: ${extra//$'\n'/ }"
  args="$(jq -r '.[] | select(.kind == "Deployment") | .spec.template.spec.containers[].args[]? | select(test("^--(metrics-|profiling|enable-pprof)"))' "${work}/render.json")"
  [[ -z ${args} ]] || fail "stack '${stack}' turns on an extra metrics/profiling endpoint: ${args//$'\n'/ }"
  deps="$(jq -r '[.[] | select(.kind == "Deployment") | .metadata.name] | join(",")' "${work}/render.json")"
  [[ -z ${deps} || ${deps} == xenon-metrics ]] || fail "stack '${stack}' renders a workload beyond metrics-server: ${deps}"
done
[[ ${on} -gt 0 ]] || fail "no stack renders metrics-server (vacuous)"

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ payload-purity: no ServiceMonitor/PodMonitor/rules/dashboards/alerts, no metrics endpoint, no sample payload, no observability docs"
