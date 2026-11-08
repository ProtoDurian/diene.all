#!/usr/bin/env bash
set -euo pipefail

# The observability payload go-base-w-observability carries (its delta from go-base .3)
# reaches this node intact: every payload line is still present at HEAD in the same file.
# This node may only add lines around it.

here="$(dirname "$0")"
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${here}/parent.sha")}"

ensure_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${1}" || true
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || { echo "❌ ${2} commit ${1} not found; fetch it first" >&2 && exit 1; }
}

ensure_commit "${parent_sha}" "go-base-w-observability .3"
go_base_sha="$(git show "${parent_sha}:.github/named-checks/go-base-w-observability/parent.sha")"
ensure_commit "${go_base_sha}" "go-base .3"

cd "$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"

mapfile -t paths < <(git -c core.quotePath=false diff --no-renames --name-only --diff-filter=AM "${go_base_sha}" "${parent_sha}" -- . ':!.github/named-checks')
[[ ${#paths[@]} -gt 0 ]] || { echo "❌ go-base-w-observability .3 ${parent_sha} carries no payload over go-base .3 ${go_base_sha}" >&2 && exit 1; }

failed=0
for path in "${paths[@]}"; do
  if ! git cat-file -e "${tree}:${path}" 2>/dev/null; then
    echo "❌ payload file ${path} is missing" >&2
    failed=1
    continue
  fi
  git -c core.quotePath=false diff --no-renames -U0 "${go_base_sha}" "${parent_sha}" -- "${path}" |
    grep -E '^\+' | grep -vE '^\+\+\+ ' | cut -c2- >"${work}/want" || true
  git show "${tree}:${path}" >"${work}/have"
  missing="$(awk 'NR == FNR { have[$0]++; next } { want[$0]++ } END { for (l in want) if (have[l] < want[l]) print l }' "${work}/have" "${work}/want")"
  if [[ -n ${missing} ]]; then
    echo "❌ ${path} lost payload lines:" >&2
    printf '%s\n' "${missing}" | sed 's/^/     /' >&2
    failed=1
  fi
done

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ payload-purity: all ${#paths[@]} payload files of ${parent_sha} keep every payload line"
