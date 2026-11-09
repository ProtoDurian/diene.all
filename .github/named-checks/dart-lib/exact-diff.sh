#!/usr/bin/env bash
set -euo pipefail

# Ledger = ADDED (dart-lib-owned new paths; bash globs, * spans /) + exact-diff.patch
# (every edit to a parent path). Regenerate the patch only with a reviewed edit:
#   git diff --no-renames --binary "$(cat parent.sha)" HEAD -- <the edited parent paths>

ADDED=(
  '.github/named-checks/dart-lib/*'
  '.github/workflows/⚡reusable-analyze.yaml'
  '.github/workflows/⚡reusable-deadcode.yaml'
  '.github/workflows/⚡reusable-package-validate.yaml'
  '.github/workflows/⚡reusable-publish.yaml'
  '.github/workflows/⚡reusable-test.yaml'
  analysis_options.yaml
  pubspec.yaml
  'packages/diene_dart_lib/*'
  'probes/*.ts'
  'scripts/ci/*.sh'
  'scripts/local/*.sh'
  'scripts/release/*.sh'
  'scripts/validate/*.sh'
  tasks/Taskfile.test.yaml
)

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared-wo-docker-helm .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

cd "$(git rev-parse --show-toplevel)"
self_dir=".github/named-checks/dart-lib"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

# index tree == HEAD in CI; keeps local staged mutations visible
want="$(git write-tree)"
patch="${work}/ledger.patch"
git show "${want}:${self_dir}/exact-diff.patch" >"${patch}" 2>/dev/null || { echo "❌ ${self_dir}/exact-diff.patch is not tracked" >&2 && exit 1; }

git -c core.quotePath=false ls-tree -r --full-tree "${parent_sha}" | cut -f2 | LC_ALL=C sort >"${work}/parent.paths"
git -c core.quotePath=false ls-tree -r --full-tree "${want}" >"${work}/head.entries"

declare -A hits=()
: >"${work}/added.entries"
while IFS=$'\t' read -r meta path; do
  for g in "${ADDED[@]}"; do
    # shellcheck disable=SC2053
    if [[ ${path} == ${g} ]]; then
      hits["${g}"]=1
      grep -qxF -- "${path}" "${work}/parent.paths" || printf '%s\t%s\n' "${meta}" "${path}" >>"${work}/added.entries"
      break
    fi
  done
done <"${work}/head.entries"
for g in "${ADDED[@]}"; do
  [[ -n ${hits["${g}"]:-} ]] || fail "ADDED entry '${g}' matches no path (stale ledger)"
done

while read -r _ _ path; do
  grep -qxF -- "${path}" "${work}/parent.paths" || fail "exact-diff.patch creates ${path}; new paths belong in ADDED"
done < <(git -c core.quotePath=false apply --numstat "${patch}")

export GIT_INDEX_FILE="${work}/index"
git read-tree "${parent_sha}"
git apply --cached "${patch}" 2>"${work}/apply.err" || fail "exact-diff.patch does not apply to shared-wo-docker-helm .3 ${parent_sha}: $(head -5 "${work}/apply.err")"
awk -F'\t' '{ split($1, m, " "); printf "%s %s\t%s\n", m[1], m[3], $2 }' "${work}/added.entries" | git update-index --index-info
got="$(git write-tree)"
unset GIT_INDEX_FILE

self_files="$(git ls-tree --name-only "${want}" -- "${self_dir}/" | LC_ALL=C sort | tr '\n' ' ')"
expected_self=""
for f in branch-ancestry.sh exact-diff.patch exact-diff.sh mirror-topology.sh mirror.repo package-source-purity.sh parent.sha retokenization-fixture.sh stripped-axis-absence.sh; do expected_self+="${self_dir}/${f} "; done
[[ ${self_files} == "${expected_self}" ]] || fail "${self_dir} holds files beyond the six checks, the ledger patch, parent.sha and mirror.repo: ${self_files}"

if [[ ${got} != "${want}" ]]; then
  fail "HEAD differs from shared-wo-docker-helm .3 ${parent_sha} + the dart-lib ledger (left: ledger, right: HEAD):"
  git -c core.quotePath=false diff --no-renames --stat "${got}" "${want}" >&2
  git -c core.quotePath=false diff --no-renames "${got}" "${want}" | head -60 >&2 || true
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ exact-diff: HEAD == shared-wo-docker-helm .3 ${parent_sha} + $(wc -l <"${work}/added.entries") ADDED paths + the reviewed edits to $(git apply --numstat "${patch}" | wc -l) parent files"
