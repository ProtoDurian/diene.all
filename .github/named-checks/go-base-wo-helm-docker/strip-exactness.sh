#!/usr/bin/env bash
set -euo pipefail

# The diff from go-base-wo-helm's .3 commit is exactly the D (docker) strip.
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
  # cd.yaml's only job is the docker one once H is gone
  .github/workflows/cd.yaml
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

apply_D() {
  rm_paths "${D_PATHS[@]}"
  rmdir infra || fail "infra/ is not empty after the D strip"
  # workspace ledger
  edit .github/workflows/ci.yaml drop_yaml_job '  docker:'
  edit Taskfile.yaml sed_e '/^  docker: tasks\/Taskfile\.docker\.yaml$/d'
  edit .github/dependabot.yml yq_del 'del(.updates[] | select(.package-ecosystem == "docker"))'
  edit dlint.yaml sed_e '/^      - docker$/d;/^      - hadolint$/d;/^      - \.github\/workflows\/cd\.yaml$/d'
  edit CLAUDE.md drop_section '# Docker build and publishing'
  edit probes/features.json yq_del 'del(.[] | select(.name == "docker-build" or .name == "distroless-base-policy" or .name == "nonroot-image-policy"))'
  edit probes/binary-smoke.ts drop_lines '^docker --version' '^docker info'
  edit probes/binary-smoke.ts drop_lines '^hadolint --version' '^hadolint infra/Dockerfile'
  edit docs/standards/taskfile/index.md sed_z 's#Docker tasks are keyed by the artifact they act on — one task set per Dockerfile.\nSee \[the Docker standard\](\.\./docker/index\.md) for that naming convention\.\n\n##'
  # infra/ and cd.yaml leave whole, so prose that points at them goes too
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

echo "✅ strip-exactness: HEAD == go-base-wo-helm .3 ${parent_sha} minus exactly the D ledger"
