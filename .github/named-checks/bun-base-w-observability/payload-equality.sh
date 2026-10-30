#!/usr/bin/env bash
set -euo pipefail

# The diff from bun-base's .3 commit is the accepted observability payload
# (shared .3 .. observability .3) byte-for-byte: the same paths with the same
# status, every added file's mode and blob identical to observability's, and
# every edited parent file gaining exactly the lines the payload adds and
# losing exactly the lines it removes. This node's own named checks are the
# only paths outside the payload.

here="$(dirname "$0")"
own_dir='.github/named-checks/bun-base-w-observability/'

ensure_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${1}" || true
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || { echo "❌ ${2} commit ${1} not found; fetch it first" >&2 && exit 1; }
}

# The graph ancestors: bun-base (parent.sha) and observability (payload.sha) at
# their recorded .3 commits. The payload is measured from the shared .3 commit
# observability itself was cut from.
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${here}/parent.sha")}"
payload_sha="${NAMED_CHECKS_PAYLOAD_SHA:-$(cat "${here}/payload.sha")}"
ensure_commit "${parent_sha}" "bun-base .3"
ensure_commit "${payload_sha}" "observability .3"
payload_base="$(git show "${payload_sha}:.github/named-checks/observability/parent.sha")"
ensure_commit "${payload_base}" "shared .3"

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

changed_lines() {
  git -c core.quotePath=false diff --no-renames -U0 "$1" "$2" -- "$3" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' || true
}

expected="$(git -c core.quotePath=false diff --no-renames --name-status "${payload_base}" "${payload_sha}")"
actual="$(git -c core.quotePath=false diff --no-renames --name-status "${parent_sha}" "${tree}" | grep -vF "	${own_dir}" || true)"

if [[ ${actual} != "${expected}" ]]; then
  echo "❌ the delta from bun-base .3 is not the payload's path set:" >&2
  diff <(echo "${expected}") <(echo "${actual}") | sed -n 's/^[<>]/   &/p' >&2 || true
  failed=1
fi

while IFS=$'\t' read -r status path; do
  [[ -n ${status} ]] || continue
  case "${status}" in
  A)
    want="$(git ls-tree "${payload_sha}" -- "${path}" | cut -f1)"
    got="$(git ls-tree "${tree}" -- "${path}" | cut -f1)"
    if [[ ${got} != "${want}" ]]; then
      echo "❌ ${path} differs from the payload (want '${want}', got '${got}')" >&2
      failed=1
    fi
    ;;
  M)
    if [[ "$(changed_lines "${parent_sha}" "${tree}" "${path}")" != "$(changed_lines "${payload_base}" "${payload_sha}" "${path}")" ]]; then
      echo "❌ ${path} carries hunks that are not the payload's" >&2
      failed=1
    fi
    ;;
  *)
    echo "❌ unexpected payload status ${status} for ${path}" >&2
    failed=1
    ;;
  esac
done <<<"${expected}"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ payload-equality: delta from bun-base .3 ${parent_sha} is observability ${payload_base}..${payload_sha} byte-for-byte"
