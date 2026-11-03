#!/usr/bin/env bash
set -euo pipefail

# Observability arrives only by merging its .3; no commit on this branch authors it.

here="$(dirname "$0")"
own_pattern='^\.github/named-checks/dotnet-base-w-observability/[^/]+$'

ensure_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${1}" || true
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || { echo "❌ ${2} commit ${1} not found; fetch it first" >&2 && exit 1; }
}

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${here}/parent.sha")}"
payload_sha="${NAMED_CHECKS_PAYLOAD_SHA:-$(cat "${here}/payload.sha")}"
ensure_commit "${parent_sha}" "dotnet-base .3"
ensure_commit "${payload_sha}" "observability .3"
payload_base="$(git show "${payload_sha}:.github/named-checks/observability/parent.sha")"
ensure_commit "${payload_base}" "shared .3"

if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
  git fetch --quiet --no-tags --unshallow origin || true
fi

failed=0

if ! git merge-base --is-ancestor "${payload_sha}" HEAD; then
  echo "❌ observability .3 ${payload_sha} is not merged into HEAD; the payload was not merged" >&2
  failed=1
fi

mapfile -t payload_paths < <(git -c core.quotePath=false diff --no-renames --name-only "${payload_base}" "${payload_sha}")
is_payload_path() {
  local p
  for p in "${payload_paths[@]}"; do
    [[ ${p} == "$1" ]] && return 0
  done
  return 1
}

chain=0
last_first_parent=''
while read -r commit first second extra; do
  chain=$((chain + 1))
  last_first_parent="${first}"
  short="$(git rev-parse --short "${commit}")"
  if [[ -n ${extra:-} ]]; then
    echo "❌ ${short} is an octopus merge" >&2
    failed=1
    continue
  fi
  mapfile -t touched < <(git -c core.quotePath=false diff --no-renames --name-only "${first}" "${commit}")
  if [[ -z ${second:-} ]]; then
    for path in "${touched[@]}"; do
      if [[ ! ${path} =~ ${own_pattern} ]]; then
        echo "❌ ${short} authors ${path} directly; only the payload merge may bring it" >&2
        failed=1
      fi
    done
  elif git merge-base --is-ancestor "${second}" "${payload_sha}"; then
    for path in "${touched[@]}"; do
      if ! is_payload_path "${path}"; then
        echo "❌ payload merge ${short} changes ${path}, which is not a payload path" >&2
        failed=1
      fi
    done
  elif git merge-base --is-ancestor "${second}" "${parent_sha}"; then
    : # a dotnet-base cascade; payload-equality guards the resulting tree
  elif [[ "$(git rev-parse "${commit}^{tree}")" != "$(git rev-parse "${first}^{tree}")" ]]; then
    echo "❌ merge ${short} of ${second} changes the tree; only payload and dotnet-base merges may" >&2
    failed=1
  fi
done < <(git rev-list --first-parent --parents "${parent_sha}..HEAD")

if [[ ${chain} -gt 0 && ${last_first_parent} != "${parent_sha}" ]] && ! git merge-base --is-ancestor "${last_first_parent}" "${parent_sha}"; then
  echo "❌ the first-parent chain does not start from dotnet-base history" >&2
  failed=1
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ no-direct-wiring: ${chain} first-parent commits since dotnet-base .3; observability arrives only by merging ${payload_sha}"
