#!/usr/bin/env bash
set -euo pipefail

# Diff vs shared-wo-docker .3: new files, plus additions to the anchored files below.
ANCHORED=(
  .github/dependabot.yml
  .github/workflows/cd.yaml
  .github/workflows/ci.yaml
  .gitignore
  CLAUDE.md
  dlint.yaml
  README.md
  Taskfile.yaml
  nix/env.nix
  nix/fmt.nix
  nix/packages.nix
  nix/pre-commit.nix
  probes/features.json
  release.yaml
)
# The only parent lines this node may replace, as "<file>:<line>".
REPLACED=(
  'release.yaml:    prepare: []'
)
NO_NEW_FILES_UNDER=(nix/ docs/standards/ .claude/skills/vendor/ .github/named-checks/)
self_dir=.github/named-checks/helm-wrapper

cd "$(git rev-parse --show-toplevel)"
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${self_dir}/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared-wo-docker .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0
fail() {
  echo "❌ $*" >&2
  failed=1
}
in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do [[ ${item} == "${needle}" ]] && return 0; done
  return 1
}

while IFS=$'\t' read -r status path; do
  case "${status}" in
  A)
    for prefix in "${NO_NEW_FILES_UNDER[@]}"; do
      if [[ ${path} == "${prefix}"* && ${path} != "${self_dir}/"* ]]; then fail "new file in a parent-owned tree: ${path}"; fi
    done
    ;;
  M)
    if ! in_list "${path}" "${ANCHORED[@]}"; then
      fail "inherited file changed outside the anchored list: ${path}"
      continue
    fi
    while IFS= read -r removed; do
      in_list "${path}:${removed}" "${REPLACED[@]}" || fail "${path}: parent line removed or changed: '${removed}'"
    done < <(git -c core.quotePath=false diff -U0 --no-renames "${parent_sha}" "${tree}" -- "${path}" | awk '/^@@/ { hunk = 1; next } hunk && /^-/ { print substr($0, 2) }')
    ;;
  *) fail "${status} ${path}: only additions and anchored edits are allowed" ;;
  esac
done < <(git -c core.quotePath=false diff --name-status --no-renames "${parent_sha}" "${tree}")

for path in "${ANCHORED[@]}"; do
  git cat-file -e "${parent_sha}:${path}" 2>/dev/null || fail "anchored file ${path} is not in the parent tree (stale anchor)"
done

self_files="$(git ls-tree --name-only "${tree}" -- "${self_dir}/" | LC_ALL=C sort | tr '\n' ' ')"
expected="${self_dir}/branch-ancestry.sh ${self_dir}/docker-absence.sh ${self_dir}/doppler-absence.sh ${self_dir}/exact-diff.sh ${self_dir}/no-vendored-artifacts.sh ${self_dir}/parent.sha "
[[ ${self_files} == "${expected}" ]] || fail "${self_dir} holds files beyond the five checks and parent.sha: ${self_files}"

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ exact-diff: HEAD == shared-wo-docker .3 ${parent_sha} + new files + anchored additions"
