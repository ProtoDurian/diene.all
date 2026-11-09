#!/usr/bin/env bash
# shellcheck disable=SC2016
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

H_PATHS=(
  infra
  '.github/workflows/⚡reusable-helm.yaml'
  tasks
  scripts/ci/helm.sh
  .claude/skills/helm-push
  docs/standards/helm
  probes/helm-lint.ts
  probes/helm-render.ts
  probes/hook-helm-lint.ts
)
H_TOKENS=(
  root_chart reusable-helm Taskfile.helm helm.sh helm-push standards/helm
  helm/index.md a-helm-lint helm-lint helm-render
  '](infra)' 'infra/'
)
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**')

for p in "${H_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "H path still tracked: ${p}"; fi
done

args=()
for t in "${H_TOKENS[@]}"; do args+=(-e "${t}"); done
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files still reference removed H paths:"$'\n'"${hits}"

show() { git show "${tree}:$1"; }
[[ "$(show .github/workflows/ci.yaml | yq '.jobs | has("helm")')" == false ]] || fail "ci.yaml still has a helm job"
[[ "$(show .github/workflows/ci.yaml | yq '[.jobs[] | select(.uses // "" | test("helm"))] | length')" == 0 ]] || fail "ci.yaml still calls a helm workflow"
[[ "$(show Taskfile.yaml | yq 'has("includes")')" == false ]] || fail "Taskfile.yaml still has includes"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "helm")] | length')" == 0 ]] || fail "dependabot.yml still has a helm entry"
[[ "$(show dlint.yaml | yq '.checks["ci-wiring"].orchestrators')" == "$(printf -- '- .github/workflows/ci.yaml\n- .github/workflows/cd.yaml\n- .github/workflows/release.yaml')" ]] || fail "dlint.yaml ci-wiring orchestrators are not exactly ci.yaml + cd.yaml + release.yaml"
cd_yaml="$(show .github/workflows/cd.yaml 2>/dev/null || true)"
[[ -n ${cd_yaml} ]] || fail "cd.yaml missing: expected the publish-nothing release stub"
[[ "$(yq -o=json -I=0 '{"name": .name, "on": .on, "permissions": .permissions, "jobs": (.jobs | keys)}' <<<"${cd_yaml}")" == '{"name":"CD","on":{"push":{"tags":["v*.*.*"]}},"permissions":null,"jobs":["release"]}' ]] || fail "cd.yaml is not exactly the v*.*.* tag trigger with one release job"
[[ "$(yq -o=json -I=0 '.jobs.release | {"name": .name, "permissions": .permissions, "uses": .uses, "with": .with, "secrets": .secrets}' <<<"${cd_yaml}")" == '{"name":"Release","permissions":{"contents":"read"},"uses":"./.github/workflows/⚡reusable-release-note.yaml","with":{"version":"${{ github.ref_name }}"},"secrets":"inherit"}' ]] || fail "cd.yaml release job must call ⚡reusable-release-note.yaml with only the tag as version"
note="$(show '.github/workflows/⚡reusable-release-note.yaml' 2>/dev/null || true)"
[[ -n ${note} ]] || fail "⚡reusable-release-note.yaml missing"
[[ "$(yq -o=json -I=0 '.on | keys' <<<"${note}")" == '["workflow_call"]' ]] || fail "⚡reusable-release-note.yaml is not workflow_call only"
[[ "$(yq -o=json -I=0 '{"jobs": (.jobs | keys), "uses": [.jobs[] | select(has("uses"))] | length}' <<<"${note}")" == '{"jobs":["release-note"],"uses":0}' ]] || fail "⚡reusable-release-note.yaml must have exactly the release-note job"
[[ "$(yq -o=json -I=0 '[.jobs[].steps[] | select(has("uses")) | .uses]' <<<"${note}")" == '["AtomiCloud/actions.setup-nix@v3"]' ]] || fail "⚡reusable-release-note.yaml uses an action beyond setup-nix"
[[ "$(yq -o=json -I=0 '[.jobs[].steps[] | select(has("run")) | {"run": .run, "env": .env}]' <<<"${note}")" == '[{"run":"nix develop .#cd -c ./scripts/ci/release-note.sh","env":{"VERSION":"${{ inputs.version }}"}}]' ]] || fail "⚡reusable-release-note.yaml must only run release-note.sh, VERSION through env"
[[ "$(show scripts/ci/release-note.sh)" == "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '' "[ -z \"\${VERSION:-}\" ] && echo \"❌ 'VERSION' env var not set\" >&2 && exit 1" '' 'echo "Released ${VERSION}"')" ]] || fail "scripts/ci/release-note.sh does more than echo the version"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("helm"))] | length')" == 0 ]] || fail "features.json still has a helm row"
if show CLAUDE.md | grep -qi '^# helm'; then fail "CLAUDE.md still has a Helm section"; fi
if show nix/pre-commit.nix | grep -q 'helm'; then fail "nix/pre-commit.nix still has a helm hook"; fi

# Positive control: retained CI, secrets, release and helm-toolchain smoke surface is intact.
for j in precommit named-checks; do
  [[ "$(show .github/workflows/ci.yaml | yq ".jobs | has(\"${j}\")")" == true ]] || fail "ci.yaml lost its ${j} job"
done
show nix/pre-commit.nix | grep -q 'a-infisical = {' || fail "pre-commit lost a-infisical"
[[ -n "$(git ls-tree --name-only "${tree}" -- .github/workflows/release.yaml)" ]] || fail "release.yaml missing"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(. == "helm version" or . == "helm-docs" or . == "kubeconform -v" or . == "kyverno version")] | length')" == 4 ]] || fail "dlint.yaml lost a helm-toolchain smoke"
for l in 'helm-docs --version >/dev/null' 'helm version --short >/dev/null' 'kubeconform -v >/dev/null' 'kyverno version >/dev/null'; do
  show probes/binary-smoke.ts | grep -qxF "${l}" || fail "binary-smoke.ts lost: ${l}"
done

for f in .github/workflows/ci.yaml .github/workflows/cd.yaml '.github/workflows/⚡reusable-release-note.yaml' .github/dependabot.yml Taskfile.yaml dlint.yaml; do
  yq e '.' "${f}" >/dev/null 2>&1 || fail "${f} is not valid YAML"
done
jq -e . probes/features.json >/dev/null 2>&1 || fail "probes/features.json is not valid JSON"
for f in nix/pre-commit.nix nix/fmt.nix; do
  nix-instantiate --parse "${f}" >/dev/null 2>&1 || fail "${f} does not parse"
done
actionlint -config-file .github/actionlint.yaml .github/workflows/*.y*ml >"${work}/actionlint.out" 2>&1 || fail "actionlint failed: $(head -5 "${work}/actionlint.out")"
task --list-all --json >"${work}/task.out" 2>&1 || fail "task --list-all failed: $(head -5 "${work}/task.out")"
dlint ci-wiring >"${work}/dlint.out" 2>&1 || fail "dlint ci-wiring failed: $(head -5 "${work}/dlint.out")"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ helm-absence: no H path, reference or entry; CD is the publish-nothing release stub; retained surface and helm-toolchain smokes intact; edited files valid"
