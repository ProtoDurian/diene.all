#!/usr/bin/env bash
set -euo pipefail

# HEAD == shared's .3 tree + the D ledger below, byte for byte (content and mode),
# ignoring only this directory. The ledger is workspace's apply_D plus its D set
# edit (.github/named-checks/workspace/removal-points.sh); shared adds no D surface.

D_PATHS=(
  infra/Dockerfile
  .dockerignore
  '.github/workflows/⚡reusable-docker.yaml'
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
)

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

root="$(git rev-parse --show-toplevel)"
self_dir=".github/named-checks/shared-wo-docker"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

rm_paths() {
  local p
  for p in "$@"; do
    if [[ -e ${p} ]]; then rm -rf -- "${p}"; else fail "ledger path ${p} not in parent tree (stale anchor)"; fi
  done
}

# edit <file> <cmd...>: the file must change.
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

sed_e() { sed -i "$1" "$2"; }
sed_z() { sed -i -z "$1" "$2"; }
drop_section() { awk -v h="$1" '$0 == h { skip = 1; next } /^# / { skip = 0 } !skip' "$2" >"${2}.new" && mv "${2}.new" "$2"; }
# drop_yaml_job <key line>: from the key up to the next job key (or EOF).
drop_yaml_job() { awk -v k="$1" '$0 == k { skip = 1; next } skip && /^  [^ ]/ { skip = 0 } !skip' "$2" >"${2}.new" && mv "${2}.new" "$2"; }
# drop_lines <first regex> <last regex>: that line range and the blank line after it.
drop_lines() { awk -v a="$1" -v b="$2" 'skip == 0 && $0 ~ a { skip = 1 } skip == 1 { if ($0 ~ b) skip = 2; next } skip == 2 && $0 == "" { skip = 0; next } { if (skip == 2) skip = 0; print }' "$3" >"${3}.new" && mv "${3}.new" "$3"; }

apply_D() {
  rm_paths "${D_PATHS[@]}"
  edit .github/workflows/ci.yaml drop_yaml_job '  docker:'
  edit .github/workflows/cd.yaml drop_yaml_job '  docker:'
  edit Taskfile.yaml sed_e '/^  docker: tasks\/Taskfile\.docker\.yaml$/d'
  edit .github/dependabot.yml sed_z "s#  - package-ecosystem: docker\n    directory: /infra\n    schedule:\n      interval: weekly\n    groups:\n      all:\n        patterns:\n          - '\*'\n    open-pull-requests-limit: 2\n##"
  edit dlint.yaml sed_e '/^      - docker$/d;/^      - hadolint$/d'
  edit CLAUDE.md drop_section '# Docker build and publishing'
  edit probes/features.json sed_z 's#  {\n    "template": "diene/workspace",\n    "name": "docker-build",\n    "class": "smoke"\n  },\n##'
  edit probes/binary-smoke.ts drop_lines '^docker --version' '^docker info'
  edit probes/binary-smoke.ts drop_lines '^hadolint --version' '^hadolint infra/Dockerfile'
  edit docs/standards/taskfile/index.md sed_z 's#Docker and Helm tasks are keyed by the artifact they act on — one task set per\nDockerfile and per chart. See \[the Docker standard\](\.\./docker/index\.md) and\n\[the Helm standard\](\.\./helm/index\.md) for that naming convention\.#Helm tasks are keyed by the artifact they act on — one task set per chart. See\n[the Helm standard](../helm/index.md) for that naming convention.#'
}

if [[ ${1:-} == --apply ]]; then
  cd "${root}"
  apply_D
  exit "${failed}"
fi

copy="${work}/copy"
mkdir -p "${copy}"
git -C "${root}" archive "${parent_sha}" | tar -x -C "${copy}"
(
  cd "${copy}"
  apply_D
  exit "${failed}"
) || failed=1

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

self_files="$(git -C "${root}" ls-tree --name-only "${head_tree}" -- "${self_dir}/" | LC_ALL=C sort | tr '\n' ' ')"
[[ ${self_files} == "${self_dir}/branch-ancestry.sh ${self_dir}/docker-absence.sh ${self_dir}/exact-diff.sh ${self_dir}/parent.sha " ]] || fail "${self_dir} holds files beyond the three checks and parent.sha: ${self_files}"

if [[ ${got} != "${want}" ]]; then
  fail "HEAD differs from shared .3 ${parent_sha} + the D ledger (left: ledger, right: HEAD):"
  git -C "${root}" -c core.quotePath=false diff --no-renames --stat "${got}" "${want}" >&2
  git -C "${root}" -c core.quotePath=false diff --no-renames "${got}" "${want}" | head -60 >&2 || true
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ exact-diff: HEAD == shared .3 ${parent_sha} minus exactly the D ledger"
