#!/usr/bin/env bash
set -euo pipefail

here="$(dirname "$0")"
own_pattern='^\.github/named-checks/bun-base-wo-helm-docker-w-observability/[^/]+$'

ensure_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${1}" || true
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || { echo "❌ ${2} commit ${1} not found; fetch it first" >&2 && exit 1; }
}

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${here}/parent.sha")}"
payload_sha="${NAMED_CHECKS_PAYLOAD_SHA:-$(cat "${here}/payload.sha")}"
ensure_commit "${parent_sha}" "bun-base-wo-helm-docker .3"
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

payload_paths_of() {
  local base
  base="$(git show "$1:.github/named-checks/observability/parent.sha" 2>/dev/null)" || base="${payload_base}"
  git -c core.quotePath=false diff --no-renames --name-only "${base}" "$1"
}

declare -A former_payload=()
while read -r _ _ second _; do
  if [[ -z ${second:-} ]] || ! git merge-base --is-ancestor "${second}" "${payload_sha}"; then continue; fi
  while read -r p; do former_payload["${p}"]=1; done < <(payload_paths_of "${second}")
done < <(git rev-list --first-parent --parents "${parent_sha}..HEAD")

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
    unset merged && declare -A merged=()
    while read -r p; do merged["${p}"]=1; done < <(payload_paths_of "${second}")
    for path in "${touched[@]}"; do
      [[ -n ${merged["${path}"]:-} ]] && continue
      # a former payload path that this payload version removed
      if [[ -n ${former_payload["${path}"]:-} ]] && ! git cat-file -e "${second}:${path}" 2>/dev/null && ! git cat-file -e "${commit}:${path}" 2>/dev/null; then
        continue
      fi
      echo "❌ payload merge ${short} changes ${path}, which is not a payload path" >&2
      failed=1
    done
  elif git merge-base --is-ancestor "${second}" "${parent_sha}"; then
    : # a bun-base-wo-helm-docker cascade; payload-equality guards the resulting tree
  elif [[ "$(git rev-parse "${commit}^{tree}")" != "$(git rev-parse "${first}^{tree}")" ]]; then
    echo "❌ merge ${short} of ${second} changes the tree; only payload and bun-base-wo-helm-docker merges may" >&2
    failed=1
  fi
done < <(git rev-list --first-parent --parents "${parent_sha}..HEAD")

if [[ ${chain} -gt 0 && ${last_first_parent} != "${parent_sha}" ]] && ! git merge-base --is-ancestor "${last_first_parent}" "${parent_sha}"; then
  echo "❌ the first-parent chain does not start from bun-base-wo-helm-docker history" >&2
  failed=1
fi

declare -A current_payload=()
while read -r p; do current_payload["${p}"]=1; done < <(payload_paths_of "${payload_sha}")
for path in "${!former_payload[@]}"; do
  [[ -n ${current_payload["${path}"]:-} ]] && continue
  if git cat-file -e "HEAD:${path}" 2>/dev/null && ! git cat-file -e "${parent_sha}:${path}" 2>/dev/null; then
    echo "❌ ${path} was removed from the payload but is still here" >&2
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ no-direct-wiring: ${chain} first-parent commits since bun-base-wo-helm-docker .3; observability arrives only by merging ${payload_sha}"
