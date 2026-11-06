# shellcheck shell=bash
# Sourced by each <base>-w-observability fold's no-direct-wiring.sh and payload-equality.sh;
# lives in lib/ so the named-check runner does not run it on its own.
set -euo pipefail

fold_setup() {
  fold="$1"
  base="$2"
  own_dir=".github/named-checks/${fold}/"
  local here
  here="$(git rev-parse --show-toplevel)/${own_dir}"
  parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${here}parent.sha")}"
  payload_sha="${NAMED_CHECKS_PAYLOAD_SHA:-$(cat "${here}payload.sha")}"
  ensure_commit "${parent_sha}" "${base} .3"
  ensure_commit "${payload_sha}" "observability .3"
  payload_base="$(git show "${payload_sha}:.github/named-checks/observability/parent.sha")"
  ensure_commit "${payload_base}" "shared .3"
}

ensure_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${1}" || true
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null || { echo "❌ ${2} commit ${1} not found; fetch it first" >&2 && exit 1; }
}

payload_paths_of() {
  local payload_parent
  payload_parent="$(git show "$1:.github/named-checks/observability/parent.sha" 2>/dev/null)" || return 0
  git -c core.quotePath=false diff --no-renames --name-only "${payload_parent}" "$1"
}

no_direct_wiring() {
  fold_setup "$@"
  local own_pattern="^${own_dir//./\\.}[^/]+\$"

  if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
    git fetch --quiet --no-tags --unshallow origin || true
  fi

  local failed=0
  if ! git merge-base --is-ancestor "${payload_sha}" HEAD; then
    echo "❌ observability .3 ${payload_sha} is not merged into HEAD; the payload was not merged" >&2
    failed=1
  fi

  local -A former_payload=()
  local commit first second extra p
  while read -r _ _ second _; do
    if [[ -z ${second:-} ]] || ! git merge-base --is-ancestor "${second}" "${payload_sha}"; then continue; fi
    while read -r p; do former_payload["${p}"]=1; done < <(payload_paths_of "${second}")
  done < <(git rev-list --first-parent --parents "${parent_sha}..HEAD")

  local chain=0 last_first_parent='' short path
  local -a touched
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
      local -A merged=()
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
      unset merged
    elif git merge-base --is-ancestor "${second}" "${parent_sha}"; then
      : # a base cascade; payload-equality guards the resulting tree
    elif [[ "$(git rev-parse "${commit}^{tree}")" != "$(git rev-parse "${first}^{tree}")" ]]; then
      echo "❌ merge ${short} of ${second} changes the tree; only payload and ${base} merges may" >&2
      failed=1
    fi
  done < <(git rev-list --first-parent --parents "${parent_sha}..HEAD")

  if [[ ${chain} -gt 0 && ${last_first_parent} != "${parent_sha}" ]] && ! git merge-base --is-ancestor "${last_first_parent}" "${parent_sha}"; then
    echo "❌ the first-parent chain does not start from ${base} history" >&2
    failed=1
  fi

  local -A current_payload=()
  while read -r p; do current_payload["${p}"]=1; done < <(payload_paths_of "${payload_sha}")
  for path in "${!former_payload[@]}"; do
    [[ -n ${current_payload["${path}"]:-} ]] && continue
    if git cat-file -e "HEAD:${path}" 2>/dev/null && ! git cat-file -e "${parent_sha}:${path}" 2>/dev/null; then
      echo "❌ ${path} was removed from the payload but is still here" >&2
      failed=1
    fi
  done

  [[ ${failed} -eq 0 ]] || exit 1
  echo "✅ no-direct-wiring: ${chain} first-parent commits since ${base} .3; observability arrives only by merging ${payload_sha}"
}

mode_of() {
  git ls-tree "$1" -- "$2" | cut -d' ' -f1
}

# one line per hunk: the old line before it, the old line after it, then its -/+ lines
hunks_of() {
  awk 'NR == FNR { old[FNR] = $0; next }
    /^@@ / {
      if (n++) print rec
      split($2, a, ","); start = substr(a[1], 2) + 0; count = (2 in a) ? a[2] + 0 : 1
      rec = old[count ? start - 1 : start] "\036" old[count ? start + count : start + 1] "\036"
      next
    }
    n { rec = rec $0 "\037" }
    END { if (n) print rec }' <(git show "$1:$3") <(git -c core.quotePath=false diff --no-renames -U0 "$1" "$2" -- "$3")
}

# same hunks in the same order, each still next to the line it was next to in the payload
same_hunks() {
  local -a want got
  local i wb wa wl gb ga gl
  mapfile -t want < <(hunks_of "${payload_base}" "${payload_sha}" "$1")
  mapfile -t got < <(hunks_of "${parent_sha}" "$2" "$1")
  [[ ${#want[@]} -eq ${#got[@]} ]] || return 1
  for i in "${!want[@]}"; do
    IFS=$'\036' read -r wb wa wl <<<"${want[i]}"
    IFS=$'\036' read -r gb ga gl <<<"${got[i]}"
    [[ ${gl} == "${wl}" && (${gb} == "${wb}" || ${ga} == "${wa}") ]] || return 1
  done
}

payload_equality() {
  fold_setup "$@"
  # index tree == HEAD in CI; keeps local staged mutations visible
  local tree failed=0 expected actual status path want got
  tree="$(git write-tree)"

  expected="$(git -c core.quotePath=false diff --no-renames --name-status "${payload_base}" "${payload_sha}")"
  actual="$(git -c core.quotePath=false diff --no-renames --name-status "${parent_sha}" "${tree}" | grep -vF "	${own_dir}" || true)"

  if [[ ${actual} != "${expected}" ]]; then
    echo "❌ the delta from ${base} .3 is not the payload's path set:" >&2
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
      want="$(mode_of "${parent_sha}" "${path}")"
      [[ "$(mode_of "${payload_base}" "${path}")" == "$(mode_of "${payload_sha}" "${path}")" ]] || want="$(mode_of "${payload_sha}" "${path}")"
      got="$(mode_of "${tree}" "${path}")"
      if [[ ${got} != "${want}" ]]; then
        echo "❌ ${path} has mode ${got}; the payload leaves it ${want}" >&2
        failed=1
      fi
      if ! same_hunks "${path}" "${tree}"; then
        echo "❌ ${path} is not ${base}'s version plus the payload's hunks in place" >&2
        failed=1
      fi
      ;;
    *)
      echo "❌ unexpected payload status ${status} for ${path}" >&2
      failed=1
      ;;
    esac
  done <<<"${expected}"

  [[ ${failed} -eq 0 ]] || exit 1
  echo "✅ payload-equality: delta from ${base} .3 ${parent_sha} is observability ${payload_base}..${payload_sha} byte-for-byte"
}
