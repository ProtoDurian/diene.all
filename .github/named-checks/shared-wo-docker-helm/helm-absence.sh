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

H_PATHS=(
  infra
  '.github/workflows/⚡reusable-helm.yaml'
  .github/workflows/cd.yaml
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
  '](infra)' 'infra/' workflows/cd.yaml
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
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(helm|helm-docs|kubeconform|kyverno)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes an H binary"
[[ "$(show dlint.yaml | yq '.checks["ci-wiring"].orchestrators')" == "$(printf -- '- .github/workflows/ci.yaml\n- .github/workflows/release.yaml')" ]] || fail "dlint.yaml ci-wiring orchestrators are not exactly ci.yaml + release.yaml"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("helm"))] | length')" == 0 ]] || fail "features.json still has a helm row"
if show CLAUDE.md | grep -qi '^# helm'; then fail "CLAUDE.md still has a Helm section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(helm|helm-docs) '; then fail "binary-smoke.ts still smokes helm"; fi
if show nix/pre-commit.nix | grep -q 'helm'; then fail "nix/pre-commit.nix still has a helm hook"; fi

# Positive control: retained CI, secrets and release surface is intact.
for j in precommit named-checks; do
  [[ "$(show .github/workflows/ci.yaml | yq ".jobs | has(\"${j}\")")" == true ]] || fail "ci.yaml lost its ${j} job"
done
show nix/pre-commit.nix | grep -q 'a-infisical = {' || fail "pre-commit lost a-infisical"
[[ -n "$(git ls-tree --name-only "${tree}" -- .github/workflows/release.yaml)" ]] || fail "release.yaml missing"

for f in .github/workflows/ci.yaml .github/dependabot.yml Taskfile.yaml dlint.yaml; do
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

echo "✅ helm-absence: no H path, reference or entry; retained CI/secrets/release surface intact; edited files valid"
