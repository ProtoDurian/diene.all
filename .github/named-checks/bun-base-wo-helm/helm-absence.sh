#!/usr/bin/env bash
set -euo pipefail

# Nothing of H survives: no H path, no reference to one, no H job, include,
# hook, Dependabot entry or probe row, no helm-carrying nix aggregate, and no
# helm binary in the default shell. The many-owner files the strip edited
# still parse and lint.

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
# Strings no remaining file may contain (the parent ledger's H_TOKENS).
H_TOKENS=(
  root_chart reusable-helm Taskfile.helm helm.sh helm-push standards/helm
  helm/index.md a-helm-lint helm-lint helm-render
)
# The declaration itself; machine-maintained history; the probe harness whose
# command-string fixtures are generic and name no axis file.
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**')

# --- paths ----------------------------------------------------------------------
for p in "${H_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "H path still tracked: ${p}"; fi
done

# --- references -------------------------------------------------------------------
args=()
for t in "${H_TOKENS[@]}"; do args+=(-e "${t}"); done
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files still reference removed H paths:"$'\n'"${hits}"

# --- anchored entries -------------------------------------------------------------
show() { git show "${tree}:$1"; }
[[ "$(show .github/workflows/ci.yaml | yq '.jobs | has("helm")')" == false ]] || fail "ci.yaml still has a helm job"
[[ "$(show .github/workflows/cd.yaml | yq '.jobs | has("helm")')" == false ]] || fail "cd.yaml still has a helm job"
[[ "$(show Taskfile.yaml | yq '.includes | has("helm")')" == false ]] || fail "Taskfile.yaml still includes helm"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "helm")] | length')" == 0 ]] || fail "dependabot.yml still has a helm entry"
[[ "$(show dlint.yaml | yq '[.checks["toolchain-smoke"].binaries[] | select(test("^(helm|helm-docs|helmlint|kubeconform|kyverno)( |$)"))] | length')" == 0 ]] || fail "dlint.yaml still smokes an H binary"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("helm"))] | length')" == 0 ]] || fail "features.json still has a helm row"
if show CLAUDE.md | grep -qi '^# helm'; then fail "CLAUDE.md still has a Helm section"; fi
if show probes/binary-smoke.ts | grep -Eq '^(helm|helm-docs|helmlint|kubeconform|kyverno) '; then fail "binary-smoke.ts still smokes an H binary"; fi

# --- nix: no aggregate that carries H by content -----------------------------------
for f in nix/packages.nix nix/env.nix; do
  if show "${f}" | grep -v '^ *#' | grep -Eq '(^|[^A-Za-z0-9-])(infralint|infrautils|kubernetes-helm|helm|helm-docs|helmlint)([^A-Za-z0-9-]|$)'; then
    fail "${f} declares a helm-carrying package"
  fi
done

# --- the shell itself: no helm binary, docker still there ---------------------------
# -i clears the caller's PATH, so only the shell's own inputs resolve. The
# positive control proves the lookup is not vacuous.
# shellcheck disable=SC2016
nix develop -i --keep HOME .#default -c bash -c '
  set -u
  bad=0
  for b in helm helm-docs helmlint; do
    if p="$(command -v "$b")"; then echo "❌ default shell carries $b at $p" >&2; bad=1; fi
  done
  for b in docker hadolint skopeo bun; do
    command -v "$b" >/dev/null || { echo "❌ control: default shell lost $b" >&2; bad=1; }
  done
  exit "$bad"
' || fail "default shell helm absence / docker presence"

# --- the many-owner files the strip edited still parse and lint ---------------------
for f in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/dependabot.yml Taskfile.yaml dlint.yaml; do
  yq e '.' "${f}" >/dev/null 2>&1 || fail "${f} is not valid YAML"
done
jq -e . probes/features.json >/dev/null 2>&1 || fail "probes/features.json is not valid JSON"
for f in nix/packages.nix nix/env.nix nix/pre-commit.nix nix/fmt.nix; do
  nix-instantiate --parse "${f}" >/dev/null 2>"${work}/nix.out" || fail "${f} does not parse: $(head -3 "${work}/nix.out")"
done
actionlint -config-file .github/actionlint.yaml .github/workflows/*.y*ml >"${work}/actionlint.out" 2>&1 || fail "actionlint failed: $(head -5 "${work}/actionlint.out")"
task --list-all >"${work}/task.out" 2>&1 || fail "task --list-all failed: $(head -5 "${work}/task.out")"
jq -e . flake.lock >/dev/null 2>&1 || fail "flake.lock is not valid JSON"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ helm-absence: no H path, reference, entry, nix aggregate or shell binary; edited files valid"
