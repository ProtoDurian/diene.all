#!/usr/bin/env bash
set -euo pipefail

# Ledger = workspace removal-points.sh apply_H + DH set edits + a publish-nothing CD stub; helm binaries stay smoked (nix unchanged).

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

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared-wo-docker .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

root="$(git rev-parse --show-toplevel)"
self_dir=".github/named-checks/shared-wo-docker-helm"
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

rm_empty_dir() {
  rmdir -- "$1" 2>/dev/null || fail "ledger dir $1 missing or not empty after the strip"
}

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
drop_nix_block() { awk -v s="$1" '$0 == s { skip = 1 } skip { if ($0 ~ /^    };$/) { skip = 0; eat = 1 } next } eat && $0 == "" { eat = 0; next } { eat = 0; print }' "$2" >"${2}.new" && mv "${2}.new" "$2"; }
drop_yaml_job() {
  awk -v k="$1" '
    { line[NR] = $0 }
    END {
      n = 0
      for (i = 1; i <= NR; i++) {
        if (line[i] == k) {
          if (n > 0 && out[n] == "") n--
          for (i++; i <= NR && line[i] ~ /^    /; i++) {}
          i--
          continue
        }
        out[++n] = line[i]
      }
      for (j = 1; j <= n; j++) print out[j]
    }' "$2" >"${2}.new" && mv "${2}.new" "$2"
}

add_file() {
  if [[ -e $1 ]]; then
    fail "ledger file $1 already in parent tree (stale anchor)"
    return
  fi
  cat >"$1"
}

cd_release_job() {
  cat >>"$1" <<'YAML'
  release:
    name: Release
    permissions:
      contents: read
    uses: ./.github/workflows/⚡reusable-release-note.yaml
    secrets: inherit
    with:
      version: ${{ github.ref_name }}
YAML
}

add_release_note() {
  add_file '.github/workflows/⚡reusable-release-note.yaml' <<'YAML'
name: ⚡ Reusable Release Note

on:
  workflow_call:
    inputs:
      version:
        required: true
        type: string

jobs:
  release-note:
    name: Release Note
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - name: Release note
        env:
          VERSION: ${{ inputs.version }}
        run: ./scripts/ci/release-note.sh
YAML
  add_file scripts/ci/release-note.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

[ -z "${VERSION:-}" ] && echo "❌ 'VERSION' env var not set" >&2 && exit 1

echo "Released ${VERSION}"
SH
  chmod +x scripts/ci/release-note.sh
}

cicd_stub_paragraph() {
  awk '{ print } $0 == "GitHub-hosted `ubuntu-26.04`." { print ""; while ((getline l < "/dev/stdin") > 0) print l }' "$1" >"${1}.new" <<'MD' && mv "${1}.new" "$1"
The publish-nothing CD stub (`⚡reusable-release-note.yaml`) is the other
exception. It only echoes the release version, so it runs on GitHub-hosted
`ubuntu-latest` with `actions/checkout` and no Nix, and calls
`./scripts/ci/release-note.sh` directly.
MD
}

apply_H() {
  rm_paths "${H_PATHS[@]}"
  rm_empty_dir infra
  rm_empty_dir tasks
  edit .github/workflows/ci.yaml drop_yaml_job '  helm:'
  edit .github/workflows/cd.yaml drop_yaml_job '  helm:'
  edit .github/workflows/cd.yaml cd_release_job
  add_release_note
  edit docs/standards/ci-cd/index.md cicd_stub_paragraph
  edit Taskfile.yaml sed_z 's#includes:\n  helm: tasks/Taskfile\.helm\.yaml\n\n##'
  edit .github/dependabot.yml sed_z "s#  - package-ecosystem: helm\n    directory: /infra/root_chart\n    schedule:\n      interval: weekly\n    groups:\n      all:\n        patterns:\n          - '\*'\n    open-pull-requests-limit: 2\n##"
  edit CLAUDE.md drop_section '# Helm charts and publishing'
  edit probes/features.json sed_z 's#  {\n    "template": "diene/workspace",\n    "name": "helm-lint",\n[^}]*},\n##;s#  {\n    "template": "diene/workspace",\n    "name": "helm-render",\n[^}]*},\n##;s#  {\n    "template": "diene/workspace",\n    "name": "hook-helm-lint",\n[^}]*},\n##'
  edit probes/binary-smoke.ts sed_e '/^helm-docs --dry-run --chart-search-root infra\/root_chart /d;/^helm template diene-workspace infra\/root_chart /d'
  edit nix/pre-commit.nix drop_nix_block '    a-helm-lint = {'
  edit nix/pre-commit.nix sed_e '/"\^infra\/root_chart\/"/d'
  edit nix/fmt.nix sed_e '/"infra\/root_chart\/\*\*"/d'
  edit .gitignore sed_z 's#^\#\#\# helm\ninfra/root_chart/uploads/\n\n##'
  edit docs/standards/taskfile/index.md sed_z 's#Helm tasks are keyed by the artifact they act on — one task set per chart\. See\n\[the Helm standard\](\.\./helm/index\.md) for that naming convention\.\n\n##'
  # shellcheck disable=SC2016
  edit README.md sed_z 's#declared in \[`Taskfile.yaml`\](Taskfile.yaml), whose `includes:` block maps each\nnamespace to a file under \[`tasks/`\](tasks); a task shown as `<namespace>:<task>`\nis that key in the included file. Build artifacts — Dockerfiles and Helm charts —\nlive under \[`infra/`\](infra) and may be plural, so their tasks are keyed per\nartifact\. See#declared in [`Taskfile.yaml`](Taskfile.yaml). See#'
  # shellcheck disable=SC2016
  edit docs/standards/service-tree/index.md sed_z 's#; the published artifact names this repository uses are the\n`with:` inputs on the Docker and Helm caller jobs in `\.github/workflows/ci\.yaml` and\n`\.github/workflows/cd\.yaml`\.#.#'
}

if [[ ${1:-} == --apply ]]; then
  cd "${root}"
  apply_H
  exit "${failed}"
fi

copy="${work}/copy"
mkdir -p "${copy}"
git -C "${root}" archive "${parent_sha}" | tar -x -C "${copy}"
(
  cd "${copy}"
  apply_H
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
[[ ${self_files} == "${self_dir}/branch-ancestry.sh ${self_dir}/docker-absence.sh ${self_dir}/exact-diff.sh ${self_dir}/helm-absence.sh ${self_dir}/parent.sha " ]] || fail "${self_dir} holds files beyond the four checks and parent.sha: ${self_files}"

if [[ ${got} != "${want}" ]]; then
  fail "HEAD differs from shared-wo-docker .3 ${parent_sha} + the H ledger (left: ledger, right: HEAD):"
  git -C "${root}" -c core.quotePath=false diff --no-renames --stat "${got}" "${want}" >&2
  git -C "${root}" -c core.quotePath=false diff --no-renames "${got}" "${want}" | head -60 >&2 || true
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ exact-diff: HEAD == shared-wo-docker .3 ${parent_sha} minus exactly the H ledger"
