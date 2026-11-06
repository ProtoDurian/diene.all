#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs are single-quoted on purpose
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-zinc}"
namespace="${NAMESPACE:-certs}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

prod=https://acme-v02.api.letsencrypt.org/directory
staging=https://acme-staging-v02.api.letsencrypt.org/directory
landscapes=(example pikachu raichu ampharos pichu entei)
prod_rows=(pikachu raichu ampharos)
entei_zones='["castform.dev.atomi.cloud","eevee.dev.atomi.cloud"]'
schemas='tests/schemas/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json'

render() {
  local root="$1"
  shift
  helm template "${release}" "${root}/chart" --namespace "${namespace}" "$@"
}

render_l() { render "$1" --values "$1/chart/values.$2.yaml" "${@:3}"; }

json() { yq eval-all -o=json '.' "$1" | jq -s 'map(select(.kind != null))'; }

need_jq() {
  local reason="$1"
  shift
  jq -e "$@" >/dev/null || { echo "❌ ${reason}" >&2 && return 1; }
}

expect_red() {
  local label="$1" pattern="$2"
  shift 2
  if "$@" >"${tmp}/red.txt" 2>&1; then
    echo "❌ negative fixture '${label}' was not caught" >&2 && exit 1
  fi
  rg -q -- "${pattern}" "${tmp}/red.txt" || { echo "❌ negative fixture '${label}' failed for the wrong reason" >&2 && cat "${tmp}/red.txt" >&2 && exit 1; }
}

expect_refusal() {
  local pattern="$1"
  shift
  expect_red "refusal: $*" "${pattern}" render . "$@"
}

copy_root() {
  mkdir -p "$1"
  cp -a chart tests Taskfile.yaml tasks "$1/"
}

issuers() { render_l "$1" "$2" >"${tmp}/issuers.yaml" && json "${tmp}/issuers.yaml" | jq -c '[.[] | select(.kind == "ClusterIssuer") | {name: .metadata.name, server: .spec.acme.server, zones: (.spec.acme.solvers[0].selector.dnsZones // [] | sort)}] | sort_by(.name)'; }

check_map() {
  local root="$1" l got
  local lapras
  lapras="$( (
    find "${root}/chart" -maxdepth 1 -name 'values.lapras*' -print
    rg -l '^\s*landscape:\s*lapras\b' "${root}/chart" || true
  ) | sort -u)"
  [ -z "${lapras}" ] || { echo "❌ a lapras issuer overlay exists (Lapras is Boron-direct; the Q-I33 map has no lapras row): ${lapras}" >&2 && return 1; }
  got="$(find "${root}/chart" -maxdepth 1 -name 'values.*.yaml' ! -name values.schema.json -printf '%f\n' | sed 's/^values\.//; s/\.yaml$//' | sort | paste -sd' ')"
  [ "${got}" = "$(printf '%s\n' "${landscapes[@]}" | sort | paste -sd' ')" ] || { echo "❌ the landscape overlay set differs from the Q-I33 map: ${got}" >&2 && return 1; }
  for l in "${prod_rows[@]}"; do
    issuers "${root}" "${l}" | need_jq "${l} is not on the LE production directory (Q-I33)" --arg s "${prod}" '. == [{name: "zinc-letsencrypt", server: $s, zones: []}]' || return 1
  done
  issuers "${root}" pichu | need_jq "pichu is not on the LE staging directory (Q-I33)" --arg s "${staging}" '. == [{name: "zinc-letsencrypt", server: $s, zones: []}]'
}

check_entei() {
  local root="$1"
  issuers "${root}" entei >"${tmp}/entei.json"
  need_jq 'ENTEI does not expose exactly the zinc-production and zinc-staging refs' '[.[].name] == ["zinc-production", "zinc-staging"]' "${tmp}/entei.json" || return 1
  need_jq 'the ENTEI staging ref zinc-staging does not resolve to the LE staging directory' --arg s "${staging}" '.[1].server == $s' "${tmp}/entei.json" || return 1
  need_jq 'the ENTEI production ref zinc-production does not resolve to the LE production directory' --arg s "${prod}" '.[0].server == $s' "${tmp}/entei.json" || return 1
  need_jq 'the ENTEI DNS-01 solver is not restricted to the hosted-development zones' --argjson z "${entei_zones}" 'all(.[]; .zones == $z)' "${tmp}/entei.json"
}

check_cardinality() {
  local root="$1" defs l paths allowed bad
  defs="$(rg -c '^\s*kind:\s*(Cluster)?Issuer\b' "${root}/chart/templates" || true)"
  [ "${defs}" = "${root}/chart/templates/clusterissuer.yaml:1" ] || { echo "❌ the issuer definition is not exactly one template: ${defs//$'\n'/ }" >&2 && return 1; }
  render "${root}" >"${tmp}/base.yaml"
  json "${tmp}/base.yaml" | jq -c '[.[] | select(.kind == "ClusterIssuer") | .spec | del(.acme.server, .acme.privateKeySecretRef, .acme.solvers[].selector)] | unique' >"${tmp}/base-spec.json"
  for l in "${landscapes[@]}"; do
    render_l "${root}" "${l}" >"${tmp}/card.yaml"
    json "${tmp}/card.yaml" | jq -c '[.[] | select(.kind == "ClusterIssuer") | .spec | del(.acme.server, .acme.privateKeySecretRef, .acme.solvers[].selector)] | unique' |
      need_jq "${l} renders a per-landscape issuer variant (spec differs beyond directory, ref and zones)" --slurpfile b "${tmp}/base-spec.json" '. == $b[0] and length == 1' || return 1
    allowed='^(serviceTree\.landscape|issuer\.refs\.0\.(token|directory))$'
    [ "${l}" = entei ] && allowed='^(serviceTree\.landscape|issuer\.refs\.[01]\.(token|directory)|issuer\.dnsZones\.[0-9]+)$'
    paths="$(yq '[.. | select(tag != "!!map" and tag != "!!seq") | path | join(".")] | .[]' "${root}/chart/values.${l}.yaml")"
    bad="$(rg -v "${allowed}" <<<"${paths}" || true)"
    [ -z "${bad}" ] || { echo "❌ ${l} overlay is a per-landscape issuer variant: it sets ${bad//$'\n'/ } (only landscape, refs and the ENTEI zones vary)" >&2 && return 1; }
  done
  for l in example pikachu raichu ampharos pichu; do
    issuers "${root}" "${l}" | need_jq "${l} renders a per-landscape issuer variant (not the one zinc-letsencrypt ref)" 'length == 1 and .[0].name == "zinc-letsencrypt" and .[0].zones == []' || return 1
  done
}

check_no_certs() {
  local root="$1" hits l
  hits="$(rg -n '^\s*kind:\s*(Certificate|CertificateRequest)\b' "${root}/chart" || true)"
  [ -z "${hits}" ] || { echo "❌ zinc authors a Certificate (certificate owners live outside zinc): ${hits}" >&2 && return 1; }
  for l in "" "${landscapes[@]}"; do
    if [ -z "${l}" ]; then render "${root}" >"${tmp}/certs.yaml"; else render_l "${root}" "${l}" >"${tmp}/certs.yaml"; fi
    json "${tmp}/certs.yaml" | need_jq "zinc renders a Certificate (${l:-values.yaml})" 'all(.[]; .kind != "Certificate" and .kind != "CertificateRequest")' || return 1
  done
}

check_intents() {
  local root="$1" file="$2"
  issuers "${root}" entei | jq -c '[.[].name]' >"${tmp}/refs.json"
  yq eval-all -o=json '.' "${file}" | jq -s 'map(select(.kind == "Certificate"))' >"${tmp}/intents.json"
  need_jq 'the fixture holds no Certificate intent' 'length > 0' "${tmp}/intents.json" || return 1
  need_jq 'a Certificate intent references no zinc ENTEI ref' --slurpfile r "${tmp}/refs.json" 'all(.[]; .spec.issuerRef.kind == "ClusterIssuer" and (.spec.issuerRef.name | IN($r[0][])))' "${tmp}/intents.json" || return 1
  need_jq 'a Certificate intent names an exact host instead of a service.platform wildcard (exact-name-per-host)' 'all(.[].spec.dnsNames[]; startswith("*."))' "${tmp}/intents.json" || return 1
  need_jq 'a Certificate intent carries a broad landscape wildcard (not one single-label wildcard per service.platform pair)' --argjson z "${entei_zones}" '
    def dnslabel: test("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$");
    all(.[].spec.dnsNames[]; . as $n | any($z[]; . as $zone | ($n | endswith("." + $zone)) and
      ($n | ltrimstr("*.") | rtrimstr("." + $zone) | split(".") | length == 3 and all(.[]; dnslabel))))' "${tmp}/intents.json"
}

check_credentials() {
  local root="$1" hits l
  hits="$(rg -n -i --glob '*.yaml' --glob '*.tpl' -e '(api[_-]?(token|key)|password|secret[_-]?key)\s*:\s*\S' -e '\b[A-Za-z0-9_-]{40}\b' "${root}/chart" | rg -v 'apiTokenSecretRef:|cloudflareTokenKey:' || true)"
  [ -z "${hits}" ] || { echo "❌ a credential literal is inlined in the chart (the Cloudflare token comes only from the ExternalSecret): ${hits}" >&2 && return 1; }
  for l in "${landscapes[@]}"; do
    render_l "${root}" "${l}" >"${tmp}/cred.yaml"
    json "${tmp}/cred.yaml" | need_jq "${l} renders an inline credential (a Secret, inline data or a non-ref Cloudflare field)" '
      all(.[]; .kind != "Secret" and (has("data") or has("stringData") | not)) and
      all(.[] | select(.kind == "ClusterIssuer"); .spec.acme.solvers | all(.[]; (.dns01.cloudflare | keys) == ["apiTokenSecretRef"])) and
      all(.[] | select(.kind == "ExternalSecret"); .spec.data == null and .spec.target.template.data == null)' || return 1
  done
}

check_lpsm() {
  local root="$1" prefix="$2" l
  shift 2
  for l in "${landscapes[@]}"; do
    render_l "${root}" "${l}" "$@" >"${tmp}/lpsm.yaml"
    json "${tmp}/lpsm.yaml" | need_jq "LPSM labels/annotations differ on the ClusterIssuer, ExternalSecret or its Secret (${l})" --arg p "${prefix}" --arg l "${l}" '
      ({($p + "/platform"): "certs", ($p + "/service"): "zinc", ($p + "/module"): "issuer", ($p + "/layer"): "1", ($p + "/landscape"): $l}) as $want |
      def lpsm: . as $m | all($want | to_entries[]; $m[.key] == .value);
      (map(.kind) | sort | unique) == ["ClusterIssuer", "ExternalSecret"] and
      all(.[]; (.metadata.labels | lpsm) and (.metadata.annotations | lpsm)) and
      all(.[] | select(.kind == "ExternalSecret"); (.spec.target.template.metadata.labels | lpsm) and (.spec.target.template.metadata.annotations | lpsm)) and
      ($p == "atomi.cloud" or all(.[]; [.metadata.labels, .metadata.annotations | keys[] | select(startswith("atomi.cloud/"))] | length == 0))' || return 1
    json "${tmp}/lpsm.yaml" | need_jq "the ExternalSecret target Secret carries a non-LPSM (Helm/Argo ownership) key (${l})" --arg p "${prefix}" '
      all(.[] | select(.kind == "ExternalSecret"); .spec.target.template.metadata | [.labels, .annotations | keys[]] | all(startswith($p + "/")))' || return 1
  done
}

check_secret() {
  local root="$1"
  render_l "${root}" pikachu >"${tmp}/secret.yaml"
  json "${tmp}/secret.yaml" >"${tmp}/secret.json"
  need_jq 'zinc does not render exactly one ExternalSecret without hand-written key mappings' 'map(select(.kind == "ExternalSecret")) | length == 1 and .[0].spec.data == null' "${tmp}/secret.json" || return 1
  need_jq 'the ExternalSecret name, store or folder-derived prefixes are wrong' '
    map(select(.kind == "ExternalSecret"))[0] as $s | $s.metadata.name == "zinc-secrets" and $s.spec.target.name == "zinc-secrets" and
    $s.spec.secretStoreRef == {kind: "SecretStore", name: "certs"} and
    ($s.spec.dataFrom | map(.find.path)) == ["/shared", "/zinc"] and ($s.spec.dataFrom | map(.rewrite[0].regexp.target)) == ["SHARED_$1", "ZINC_$1"]' "${tmp}/secret.json" || return 1
  need_jq 'the ClusterIssuer token ref is not the folder-prefixed ExternalSecret key' '
    all(.[] | select(.kind == "ClusterIssuer"); .spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef == {name: "zinc-secrets", key: "ZINC_CLOUDFLARE_API_TOKEN"})' "${tmp}/secret.json"
}

check_tasks() {
  local root="$1" got want
  got="$(yq -r '.includes | to_entries[] | select(.key != "helm") | [.key, .value.taskfile, .value.vars.LANDSCAPE, .value.vars.NAMESPACE, .value.vars.RELEASE_NAME, (.value.vars.CLUSTER // "")] | join(" ")' "${root}/Taskfile.yaml" | sort)"
  want="$(for l in "${landscapes[@]}"; do echo "${l} tasks/Taskfile.cluster.yaml ${l} certs zinc "; done | sort)"
  [ "${got}" = "${want}" ] || { echo "❌ the Taskfile includes differ from the landscape overlays (one tasks/Taskfile.cluster.yaml include per overlay)" >&2 && diff <(echo "${want}") <(echo "${got}") >&2 || true && return 1; }
  (cd "${root}" && task --silent pikachu:template) >"${tmp}/task.yaml"
  json "${tmp}/task.yaml" | need_jq 'pikachu:template does not render the pikachu overlay' --arg s "${prod}" '
    map(select(.kind == "ClusterIssuer")) | length == 1 and .[0].spec.acme.server == $s and .[0].metadata.labels["atomi.cloud/landscape"] == "pikachu"'
}

vap_stage() {
  local root="$1" file="$2"
  kubeconform -strict -summary -schema-location default -schema-location "${root}/${schemas}" "${file}" >"${file}.kc.txt" 2>&1 ||
    { cat "${file}.kc.txt" >&2 && echo "❌ kubeconform rejected the rendered manifests" >&2 && return 1; }
  rg -q 'Valid: [1-9][0-9]*, Invalid: 0, Errors: 0, Skipped: 0' "${file}.kc.txt" || { cat "${file}.kc.txt" >&2 && echo "❌ kubeconform validated nothing or skipped a kind" >&2 && return 1; }
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${file}" >"${file}.vap.yaml"
  if [ -s "${file}.vap.yaml" ]; then
    kyverno apply "${root}/policies/vap" --resource "${file}.vap.yaml" --detailed-results --remove-color
  else
    echo "VAP evaluation vacuous: no workload or Service targets"
  fi
}

stale="amph"
stale+="oros"

check_stale() {
  local tree="$1" dir="${2:-.}" hits
  hits="$(git -C "${dir}" -c core.quotePath=false ls-tree -r --name-only "${tree}" | rg -i "${stale}" || true)"
  hits+="$(git -C "${dir}" grep -n -I -i "${stale}" "${tree}" || true)"
  [ -z "${hits}" ] || { echo "❌ a shipped file names the stale ${stale} row: ${hits}" >&2 && return 1; }
}

case "${mode}" in
schema)
  expect_red 'platform other than certs' "serviceTree/platform|at '/serviceTree/platform'" helm lint chart --namespace other --set serviceTree.platform=other
  expect_red 'layer is not numeric' "serviceTree/layer|at '/serviceTree/layer'" helm lint chart --namespace "${namespace}" --set-string serviceTree.layer=one
  expect_red 'unknown ACME directory' "refs/0/directory|at '/issuer/refs/0/directory'" helm lint chart --namespace "${namespace}" --set 'issuer.refs[0].directory=prod'
  expect_red 'dashed ref token' "refs/0/token|at '/issuer/refs/0/token'" helm lint chart --namespace "${namespace}" --set 'issuer.refs[0].token=lets-encrypt'
  expect_red 'no refs' "issuer/refs|at '/issuer/refs'" helm lint chart --namespace "${namespace}" --set-json 'issuer.refs=[]'
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  for l in "${landscapes[@]}"; do helm lint chart --namespace "${namespace}" --values "chart/values.${l}.yaml"; done
  ;;
render)
  render . >/dev/null
  for l in "${landscapes[@]}"; do render_l . "${l}" >/dev/null; done
  expect_refusal 'must equal release namespace' --namespace other
  expect_refusal 'repeats token "b" or directory "staging"' --set-json 'issuer.refs=[{"token":"a","directory":"staging"},{"token":"b","directory":"staging"}]'
  expect_refusal 'repeats token "a"' --set-json 'issuer.refs=[{"token":"a","directory":"staging"},{"token":"a","directory":"production"}]'
  ;;
lpsm-labels)
  check_lpsm . atomi.cloud
  check_lpsm . example.dev --set labelPrefix=example.dev
  copy_root "${tmp}/nolabels"
  sed -i '/include "zinc.serviceTreeLabels"/d' "${tmp}/nolabels/chart/templates/_helpers.tpl"
  expect_red 'LPSM labels dropped' 'LPSM labels/annotations differ' check_lpsm "${tmp}/nolabels" atomi.cloud
  copy_root "${tmp}/owned"
  sed -i '27s|include "zinc.serviceTreeLabels" . \| trim|include "zinc.labels" .|' "${tmp}/owned/chart/templates/externalsecret.yaml"
  expect_red 'Helm/Argo ownership labels on the ESO-owned Secret' 'carries a non-LPSM \(Helm/Argo ownership\) key' check_lpsm "${tmp}/owned" atomi.cloud
  ;;
secret)
  check_secret .
  render_l . pikachu --set secret.sharedFolder=/common --set secret.serviceFolder=/team/zinc-issuer --set secret.store.name=other |
    yq eval-all -o=json '.' | jq -s -e 'map(select(.kind != null)) | (map(select(.kind == "ExternalSecret"))[0].spec | .secretStoreRef.name == "other" and (.dataFrom | map(.rewrite[0].regexp.target)) == ["COMMON_$1", "TEAM_ZINC_ISSUER_$1"]) and
      (map(select(.kind == "ClusterIssuer"))[0].spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef.key == "TEAM_ZINC_ISSUER_CLOUDFLARE_API_TOKEN")' >/dev/null ||
    { echo "❌ the ExternalSecret prefixes or the issuer token key do not follow the folders" >&2 && exit 1; }
  expect_refusal 'secret key prefixes "SHARED_" \(/shared\) and "SHARED_" \(/shared\) collide' --set secret.serviceFolder=/shared
  expect_refusal 'collide' --set secret.sharedFolder=/zinc/inner
  copy_root "${tmp}/rawkey"
  sed -i 's|key: {{ $tokenKey }}|key: CLOUDFLARE_API_TOKEN|' "${tmp}/rawkey/chart/templates/clusterissuer.yaml"
  expect_red 'issuer reads the un-prefixed key' 'not the folder-prefixed ExternalSecret key' check_secret "${tmp}/rawkey"
  ;;
task-surface)
  check_tasks .
  copy_root "${tmp}/tasks"
  yq -i 'del(.includes.raichu)' "${tmp}/tasks/Taskfile.yaml"
  expect_red 'an overlay without its Taskfile include' 'Taskfile includes differ from the landscape overlays' check_tasks "${tmp}/tasks"
  ;;
directory-map)
  check_map .
  for row in "${prod_rows[@]}"; do
    copy_root "${tmp}/map-${row}"
    yq -i '.issuer.refs[0].directory = "staging"' "${tmp}/map-${row}/chart/values.${row}.yaml"
    expect_red "${row} on the staging directory" "${row} is not on the LE production directory" check_map "${tmp}/map-${row}"
  done
  copy_root "${tmp}/map-pichu"
  yq -i '.issuer.refs[0].directory = "production"' "${tmp}/map-pichu/chart/values.pichu.yaml"
  expect_red 'pichu on the production directory' 'pichu is not on the LE staging directory' check_map "${tmp}/map-pichu"
  copy_root "${tmp}/map-lapras"
  sed 's/pichu/lapras/' chart/values.pichu.yaml >"${tmp}/map-lapras/chart/values.lapras.yaml"
  expect_red 'a lapras issuer overlay' 'a lapras issuer overlay exists' check_map "${tmp}/map-lapras"
  ;;
entei-overlay)
  check_entei .
  copy_root "${tmp}/swap"
  yq -i '.issuer.refs[0].directory = "production" | .issuer.refs[1].directory = "staging"' "${tmp}/swap/chart/values.entei.yaml"
  expect_red 'the two ACME directories swapped' 'zinc-staging does not resolve to the LE staging directory' check_entei "${tmp}/swap"
  copy_root "${tmp}/nozones"
  yq -i 'del(.issuer.dnsZones)' "${tmp}/nozones/chart/values.entei.yaml"
  expect_red 'the hosted-zone restriction omitted' 'not restricted to the hosted-development zones' check_entei "${tmp}/nozones"
  copy_root "${tmp}/stagingprod"
  yq -i ".issuer.directories.staging = \"${prod}\"" "${tmp}/stagingprod/chart/values.yaml"
  expect_red 'the staging ref resolving to production' 'zinc-staging does not resolve to the LE staging directory' check_entei "${tmp}/stagingprod"
  ;;
issuer-cardinality)
  check_cardinality .
  copy_root "${tmp}/second"
  cp chart/templates/clusterissuer.yaml "${tmp}/second/chart/templates/clusterissuer-entei.yaml"
  expect_red 'a second hand-authored issuer template' 'the issuer definition is not exactly one template' check_cardinality "${tmp}/second"
  copy_root "${tmp}/variant"
  yq -i '.issuer.email = "raichu@atomi.cloud"' "${tmp}/variant/chart/values.raichu.yaml"
  expect_red 'a per-landscape issuer variant (raichu email)' 'raichu .*per-landscape issuer variant' check_cardinality "${tmp}/variant"
  copy_root "${tmp}/variant2"
  yq -i '.issuer.refs += [{"token": "raichu", "directory": "staging"}]' "${tmp}/variant2/chart/values.raichu.yaml"
  expect_red 'a per-landscape issuer variant (raichu second ref)' 'raichu overlay is a per-landscape issuer variant' check_cardinality "${tmp}/variant2"
  ;;
no-certificate)
  check_no_certs .
  check_intents . tests/fixtures/certificates/instance-intents.yaml
  copy_root "${tmp}/authored"
  sed -n '1,/^---$/p' tests/fixtures/certificates/instance-intents.yaml | sed '$d' >"${tmp}/authored/chart/templates/certificate.yaml"
  expect_red 'a chart-authored Certificate' 'zinc authors a Certificate' check_no_certs "${tmp}/authored"
  expect_red 'a broad *.eevee.<host-domain> wildcard' 'broad landscape wildcard' check_intents . tests/fixtures/certificates/bad-landscape-wildcard.yaml
  expect_red 'an exact-name-per-host Certificate' 'exact-name-per-host' check_intents . tests/fixtures/certificates/bad-exact-host.yaml
  ;;
credential-literal)
  check_credentials .
  copy_root "${tmp}/inline"
  fake="$(printf 'x%.0s' {1..40})"
  yq -i ".issuer.cloudflareApiToken = \"${fake}\"" "${tmp}/inline/chart/values.yaml"
  expect_red 'an inlined Cloudflare token in values' 'credential literal is inlined' check_credentials "${tmp}/inline"
  copy_root "${tmp}/secretobj"
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: zinc-cloudflare\nstringData:\n  token: {{ .Values.issuer.email }}\n' >"${tmp}/secretobj/chart/templates/token.yaml"
  expect_red 'an inline token Secret' 'renders an inline credential' check_credentials "${tmp}/secretobj"
  ;;
rendered-manifests)
  for l in "" "${landscapes[@]}"; do
    if [ -z "${l}" ]; then render . >"${tmp}/rendered.yaml"; else render_l . "${l}" >"${tmp}/rendered.yaml"; fi
    vap_stage . "${tmp}/rendered.yaml"
  done
  copy_root "${tmp}/invalid"
  sed -i 's|^    email: |    emial: |' "${tmp}/invalid/chart/templates/clusterissuer.yaml"
  render_l "${tmp}/invalid" pikachu >"${tmp}/invalid.yaml"
  expect_red 'a schema-invalid rendered ClusterIssuer' 'kubeconform rejected the rendered manifests' vap_stage . "${tmp}/invalid.yaml"
  ;;
stale-row)
  check_stale "$(git write-tree)"
  copy_root "${tmp}/stale"
  cp chart/values.ampharos.yaml "${tmp}/stale/chart/values.${stale}.yaml"
  git -C "${tmp}/stale" init --quiet && git -C "${tmp}/stale" add -A
  expect_red "a values.${stale}.yaml overlay" 'names the stale' check_stale "$(git -C "${tmp}/stale" write-tree)" "${tmp}/stale"
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/zinc-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/zinc-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  expect_red 'a tag that differs from Chart.yaml' 'does not match tag 9.9.9' env PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v9.9.9 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh
  ;;
presence)
  test -s docs/developer/zinc-baseline.md
  test -s .claude/skills/zinc/SKILL.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ zinc ${mode} validation passed"
