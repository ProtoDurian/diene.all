#!/usr/bin/env bash
set -euo pipefail

# The diff from go-base-wo-helm's .3 commit is exactly the D (docker) strip
# plus the release-only CD stub.
# Proof by recomputation: copy go-base-wo-helm's .3 tree, apply the D ledger
# below, and require the result to equal HEAD's tree byte for byte (content and
# mode), ignoring only this directory. Any hunk the ledger does not declare
# fails; a ledger anchor that no longer matches the parent fails (stale anchor).
#
# LEDGER — read this section to review the strip. It is the workspace D ledger
# (.github/named-checks/workspace/removal-points.sh apply_D) plus the D
# contributions go-base adds on top of it.

# --- whole paths removed ------------------------------------------------------
D_PATHS=(
  infra/Dockerfile
  .dockerignore
  '.github/workflows/⚡reusable-docker.yaml'
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
  # go-base's image policy: it validates infra/Dockerfile
  probes/distroless-base-policy.ts
  probes/nonroot-image-policy.ts
)

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ go-base-wo-helm .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

root="$(git rev-parse --show-toplevel)"
self_dir=".github/named-checks/go-base-wo-helm-docker"
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
          for (i--; line[i] == ""; i--) {}
          continue
        }
        out[++n] = line[i]
      }
      for (j = 1; j <= n; j++) print out[j]
    }' "$2" >"${2}.new" && mv "${2}.new" "$2"
}
# drop_lines <first regex> <last regex>: that line range and the blank line after it.
drop_lines() { awk -v a="$1" -v b="$2" 'skip == 0 && $0 ~ a { skip = 1 } skip == 1 { if ($0 ~ b) skip = 2; next } skip == 2 && $0 == "" { skip = 0; next } { if (skip == 2) skip = 0; print }' "$3" >"${3}.new" && mv "${3}.new" "$3"; }

# --- the CD stub: a v*.*.* tag runs CD, which publishes nothing ----------------
# add <path> <mode> <writer>: a file the parent must not have.
add() {
  if [[ -e $1 ]]; then
    fail "stub file $1 already in parent tree (stale anchor)"
    return
  fi
  "$3" "$1"
  chmod "$2" "$1"
}
cd_stub() {
  cat >"$1" <<'EOF'
name: CD

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  release:
    name: Release
    uses: ./.github/workflows/⚡reusable-release-note.yaml
    secrets: inherit
    with:
      version: ${{ github.ref_name }}
EOF
}
release_note_workflow() {
  cat >"$1" <<'EOF'
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
    runs-on:
      - nscloud-ubuntu-26.04-amd64-4x8-with-cache
      - nscloud-cache-size-20gb
      - nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64
    timeout-minutes: 5
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
      - name: Release note
        env:
          VERSION: ${{ inputs.version }}
        run: ./scripts/ci/release-note.sh
EOF
}
release_note_script() {
  cat >"$1" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Released ${VERSION}"
EOF
}

apply_D() {
  rm_paths "${D_PATHS[@]}"
  rmdir infra || fail "infra/ is not empty after the D strip"
  edit .github/workflows/cd.yaml cd_stub
  add '.github/workflows/⚡reusable-release-note.yaml' 644 release_note_workflow
  add scripts/ci/release-note.sh 755 release_note_script
  # workspace ledger
  edit .github/workflows/ci.yaml drop_yaml_job '  docker:'
  edit Taskfile.yaml sed_e '/^  docker: tasks\/Taskfile\.docker\.yaml$/d'
  edit .github/dependabot.yml yq_del 'del(.updates[] | select(.package-ecosystem == "docker"))'
  edit dlint.yaml sed_e '/^      - docker$/d;/^      - hadolint$/d'
  edit CLAUDE.md drop_section '# Docker build and publishing'
  edit probes/features.json yq_del 'del(.[] | select(.name == "docker-build" or .name == "distroless-base-policy" or .name == "nonroot-image-policy"))'
  edit probes/binary-smoke.ts drop_lines '^docker --version' '^docker info'
  edit probes/binary-smoke.ts drop_lines '^hadolint --version' '^hadolint infra/Dockerfile'
  edit docs/standards/taskfile/index.md sed_z 's#Docker tasks are keyed by the artifact they act on — one task set per Dockerfile.\nSee \[the Docker standard\](\.\./docker/index\.md) for that naming convention\.\n\n##'
  # infra/ leaves whole and CD loses its caller jobs, so prose that points at them goes too
  # shellcheck disable=SC2016
  edit docs/standards/service-tree/index.md sed_z 's#; the published artifact names this repository uses are the\n`with:` inputs on the Docker and Helm caller jobs in `\.github/workflows/ci\.yaml` and\n`\.github/workflows/cd\.yaml`\.#.#'
  # shellcheck disable=SC2016
  edit README.md sed_z 's#is that key in the included file\. Build artifacts — Dockerfiles and Helm charts —\nlive under \[`infra/`\](infra) and may be plural, so their tasks are keyed per\nartifact\. See \[the Taskfile standard\](docs/standards/taskfile/index\.md) for the\nconventions\.#is that key in the included file. See\n[the Taskfile standard](docs/standards/taskfile/index.md) for the conventions.#'

  # go-base's D contributions
  # the image-policy helpers serve only the two policy probes; they read infra/Dockerfile
  edit probes/lib/go.ts sed_z 's#\n\nconst imagePolicies = {\n.*#\n#'
  edit .claude/skills/go-baseline/SKILL.md sed_e 's/ vulnerability, Docker, or Go CI/ vulnerability, or Go CI/'
  # shellcheck disable=SC2016
  edit docs/developer/go-baseline.md sed_z 's|## Docker\n\nThe Dockerfile builds a static binary and runs it from\n`gcr\.io/distroless/static-debian12:nonroot` as UID/GID 65532\.\n\n||'
  edit docs/developer/go-baseline.md sed_z 's#coverage thresholds after adding real surface and the Docker entrypoint\.\n#coverage thresholds after adding real surface.\n#'
  edit docs/developer/go-baseline.md sed_z 's#one\ncomposition root, distroless nonroot runtime policy, and generated hook/probe\ncoverage\.#one\ncomposition root, and generated hook/probe coverage.#'
}

# --- recompute from the parent ------------------------------------------------
copy="${work}/copy"
mkdir -p "${copy}"
git -C "${root}" archive "${parent_sha}" | tar -x -C "${copy}"
(
  cd "${copy}"
  apply_D
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
  fail "HEAD differs from go-base-wo-helm .3 ${parent_sha} + the D ledger (left: ledger, right: HEAD):"
  git -C "${root}" -c core.quotePath=false diff --no-renames --stat "${got}" "${want}" >&2
  git -C "${root}" -c core.quotePath=false diff --no-renames "${got}" "${want}" | head -60 >&2 || true
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ strip-exactness: HEAD == go-base-wo-helm .3 ${parent_sha} + exactly the D ledger and CD stub"
