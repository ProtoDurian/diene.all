#!/usr/bin/env bash
set -euo pipefail

# The mirror tracks this branch, never a foreign base. The mirror is published
# only by the shared step (ratchet ops/mirror-publish.ts) onto branches
# ratchet/bun-lib-g<N>; each head there must be that step's strip commit:
# first parent = a commit of THIS branch (an ancestor of HEAD), a
# `Mirrors-Sha:` trailer naming that same parent, and no named-checks surface.
# A re-rooted or hand-pushed head fails. The mirror's default branch is the
# owner's to publish and is reported, not judged.
#
# NAMED_CHECKS_MIRROR_SHA=<sha> additionally requires a publish head that
# mirrors exactly <sha> (the `.3` claim: the mirror stands at the `.2` SHA).
# Until the first publish there is no head to judge; the check then proves only
# that the declared mirror is reachable, and says so.

cd "$(git rev-parse --show-toplevel)"
node="bun-lib"
subject="chore: strip diene-internal named checks for the mirror (owner rule 2026-10-30)"
mirror="$(cat "$(dirname "$0")/mirror.repo")"
url="${NAMED_CHECKS_MIRROR_URL:-https://github.com/${mirror}.git}"
want="${NAMED_CHECKS_MIRROR_SHA:-}"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

refs="$(git ls-remote --heads "${url}" "refs/heads/ratchet/${node}-g*")" || { echo "❌ mirror ${mirror} is not reachable at ${url}" >&2 && exit 1; }

# ancestry needs this branch's history; CI checkouts may be shallow
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then git fetch --quiet --no-tags --unshallow origin || true; fi

matched=0
while read -r head ref; do
  [[ -z ${head} ]] && continue
  branch="${ref#refs/heads/}"
  local_ref="refs/named-checks/mirror/${branch}"
  git fetch --quiet --no-tags "${url}" "+${ref}:${local_ref}" || { fail "${branch}: cannot fetch ${head}" && continue; }
  parent="$(git rev-parse --verify --quiet "${head}^1" || true)"
  trailer="$(git log -1 --format='%(trailers:key=Mirrors-Sha,valueonly)' "${head}" | tr -d '[:space:]')"
  [[ "$(git log -1 --format=%s "${head}")" == "${subject}" ]] || fail "${branch}: head ${head} is not a mirror-publish strip commit"
  [[ -n ${parent} ]] || fail "${branch}: head ${head} has no parent (re-rooted mirror)"
  [[ ${trailer} == "${parent}" ]] || fail "${branch}: Mirrors-Sha '${trailer}' is not the head's parent '${parent}'"
  if [[ -n ${parent} ]] && ! git merge-base --is-ancestor "${parent}" HEAD 2>/dev/null; then
    fail "${branch}: mirrored commit ${parent} is not on this branch (foreign base)"
  fi
  [[ -z "$(git ls-tree -r --name-only "${head}" -- .github/named-checks scripts/ci/named-checks.sh)" ]] || fail "${branch}: head ${head} still ships named checks"
  [[ ${parent} == "${want}" ]] && matched=1
  echo "  ${branch} @ ${head} mirrors ${parent}"
  git update-ref -d "${local_ref}"
done <<<"${refs}"

default="$(git ls-remote --symref "${url}" HEAD | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2 }')"
echo "  default branch ${default:-unknown} is owner-published; not judged"

if [[ -n ${want} && ${matched} -ne 1 ]]; then fail "no ratchet/${node}-g* head mirrors ${want}"; fi
if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

if [[ -z ${refs} ]]; then
  echo "✅ mirror-topology: ${mirror} reachable; no ratchet/${node}-g* publish yet, so no head to judge"
else
  echo "✅ mirror-topology: every ratchet/${node}-g* head on ${mirror} is a strip commit of this branch${want:+, one mirrors ${want}}"
fi
