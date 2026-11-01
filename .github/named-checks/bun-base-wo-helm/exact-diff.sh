#!/usr/bin/env bash
set -euo pipefail

# The diff from bun-base's .3 commit is exactly the H (helm) strip. Proof by
# recomputation: copy bun-base's .3 tree, apply the H ledger below, and require
# the result to equal HEAD's tree byte for byte (content and mode), ignoring
# only this directory. Any hunk the ledger does not declare fails; a ledger
# anchor that no longer matches the parent fails (stale anchor).
#
# LEDGER — read this section to review the strip. It is the parent's own H
# ledger (.github/named-checks/workspace/removal-points.sh apply_H) plus the
# H contributions bun-base adds on top of it.

# --- whole paths removed ------------------------------------------------------
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
)

# --- flake.lock: atomipkgs bbf8c71 -> 116ef25 (the v5 tag) ---------------------
# bun-base's lock predates the axis-pure slices the nix hunks below need. This
# is workspace's lock byte for byte, so the hunk vanishes once bun-base takes it.
FLAKE_LOCK_BLOB=cfe880eec0ff82bc14a380e0ef0aedb5c5e44dce

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ bun-base .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

root="$(git rev-parse --show-toplevel)"
self_dir=".github/named-checks/bun-base-wo-helm"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

# --- helpers ------------------------------------------------------------------
rm_paths() {
  local p
  for p in "$@"; do
    if [[ -e ${p} ]]; then rm -rf -- "${p}"; else fail "ledger path ${p} not in parent tree (stale anchor)"; fi
  done
}

# edit <file> <cmd...>: run cmd on file; the file must change.
edit() {
  local file="$1"
  shift
  if [[ ! -f ${file} ]]; then
    fail "ledger file ${file} not in parent tree (stale anchor)"
    return
  fi
  cp -- "${file}" "${work}/before"
  "$@" "${file}" || {
    fail "edit failed on ${file}: ${*}"
    return
  }
  if cmp -s -- "${work}/before" "${file}"; then fail "anchor not found in ${file}: ${*}"; fi
}

yq_del() { yq -i "$1" "$2"; }
sed_e() { sed -i "$1" "$2"; }
sed_z() { sed -i -z "$1" "$2"; }
drop_section() { awk -v h="$1" '$0 == h { skip = 1; next } /^# / { skip = 0 } !skip' "$2" >"${2}.new" && mv "${2}.new" "$2"; }
drop_nix_block() { awk -v s="$1" '$0 == s { skip = 1 } skip { if ($0 ~ /^    };$/) { skip = 0; eat = 1 } next } eat && $0 == "" { eat = 0; next } { eat = 0; print }' "$2" >"${2}.new" && mv "${2}.new" "$2"; }
# drop_yaml_job <key line>: the job, its deeper-indented body and the blank line before it.
drop_yaml_job() {
  awk -v k="$1" '
    { line[NR] = $0 }
    END {
      n = 0
      for (i = 1; i <= NR; i++) {
        if (line[i] == k) {
          if (n > 0 && out[n] == "") n--
          for (i++; i <= NR && (line[i] == "" || line[i] ~ /^    /); i++) {}
          i--
          continue
        }
        out[++n] = line[i]
      }
      for (j = 1; j <= n; j++) print out[j]
    }' "$2" >"${2}.new" && mv "${2}.new" "$2"
}
# drop_lines <first regex> <last regex>: that line range and the blank line after it.
drop_lines() { awk -v a="$1" -v b="$2" 'skip == 0 && $0 ~ a { skip = 1 } skip == 1 { if ($0 ~ b) skip = 2; next } skip == 2 && $0 == "" { skip = 0; next } { if (skip == 2) skip = 0; print }' "$3" >"${3}.new" && mv "${3}.new" "$3"; }
put_blob() { git -C "${root}" cat-file blob "$1" >"$2"; }

apply_H() {
  rm_paths "${H_PATHS[@]}"
  # workspace ledger
  edit .github/workflows/ci.yaml drop_yaml_job '  helm:'
  edit .github/workflows/cd.yaml drop_yaml_job '  helm:'
  edit Taskfile.yaml sed_e '/^  helm: tasks\/Taskfile\.helm\.yaml$/d'
  edit .github/dependabot.yml yq_del 'del(.updates[] | select(.package-ecosystem == "helm"))'
  edit dlint.yaml sed_e '/^      - helm version$/d;/^      - helm-docs$/d;/^      - kubeconform -v$/d;/^      - kyverno version$/d'
  edit CLAUDE.md drop_section '# Helm charts and publishing'
  edit probes/features.json yq_del 'del(.[] | select(.name == "helm-lint" or .name == "helm-render" or .name == "hook-helm-lint"))'
  edit probes/binary-smoke.ts drop_lines '^helm-docs --version' '^helm template diene-workspace infra/root_chart'
  edit nix/pre-commit.nix drop_nix_block '    a-helm-lint = {'
  edit nix/pre-commit.nix sed_e '/"\^infra\/root_chart\/"/d'
  edit nix/fmt.nix sed_e '/"infra\/root_chart\/\*\*"/d'
  edit .gitignore sed_z 's|\n### workspace \[helm\]\ninfra/root_chart/uploads/\n||'
  edit docs/standards/taskfile/index.md sed_z 's#Docker and Helm tasks are keyed by the artifact they act on — one task set per\nDockerfile and per chart. See \[the Docker standard\](\.\./docker/index\.md) and\n\[the Helm standard\](\.\./helm/index\.md) for that naming convention\.#Docker tasks are keyed by the artifact they act on — one task set per Dockerfile.\nSee [the Docker standard](../docker/index.md) for that naming convention.#'

  # bun-base's H contributions
  # shellcheck disable=SC2016
  edit docs/developer/bun-baseline.md sed_e '/^- `task helm:lint` and `task helm:template` retain the inherited Helm axis\.$/d;s/^- Unit, integration, build, Docker, and Helm are separate CI jobs\.$/- Unit, integration, build, and Docker are separate CI jobs./'

  # nix: the aggregates carry H by content; take the axis-pure slices. Docker
  # (D) keeps its slices. kubectl and k3d ship only in infrautils-k8s, beside
  # helm, so they leave with the aggregate and their declared smokes go too.
  edit nix/packages.nix sed_e 's/^          infralint$/          # Axis-pure slices: the infralint\/infrautils aggregates ship helm, helm-docs and helmlint.\n          infralint-core\n          infralint-docker/;s/^          infrautils$/          infrautils-core\n          infrautils-docker/'
  edit nix/env.nix sed_e 's/^    infralint$/    infralint-core\n    infralint-docker/;s/^    infrautils$/    infrautils-core\n    infrautils-docker/'
  edit flake.lock put_blob "${FLAKE_LOCK_BLOB}"
  edit dlint.yaml sed_e '/^      - k3d$/d;/^      - kubectl version --client$/d'
  edit probes/binary-smoke.ts drop_lines '^k3d version' '^printf .* kyverno jp query'
}

# --- recompute from the parent ------------------------------------------------
copy="${work}/copy"
mkdir -p "${copy}"
git -C "${root}" archive "${parent_sha}" | tar -x -C "${copy}"
(
  cd "${copy}"
  apply_H
  exit "${failed}"
) || failed=1

# Both sides as git trees, so content and mode compare exactly.
# index tree == HEAD in CI; keeps local staged mutations visible
head_tree="$(git -C "${root}" write-tree)"
export GIT_INDEX_FILE="${work}/index"
git -C "${root}" read-tree "${head_tree}"
git -C "${root}" rm -r -q --cached --ignore-unmatch -- "${self_dir}"
want="$(git -C "${root}" write-tree)"
git -C "${root}" read-tree "${parent_sha}"
git -C "${root}" --work-tree="${copy}" add -A -f -- .
got="$(git -C "${root}" write-tree)"
unset GIT_INDEX_FILE

if [[ ${got} != "${want}" ]]; then
  fail "HEAD differs from bun-base .3 ${parent_sha} + the H ledger (left: ledger, right: HEAD):"
  git -C "${root}" -c core.quotePath=false diff --no-renames --stat "${got}" "${want}" >&2
  git -C "${root}" -c core.quotePath=false diff --no-renames "${got}" "${want}" | head -60 >&2 || true
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ exact-diff: HEAD == bun-base .3 ${parent_sha} minus exactly the H ledger"
