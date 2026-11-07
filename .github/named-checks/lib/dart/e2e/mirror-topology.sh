#!/usr/bin/env bash
set -euo pipefail

# Each ratchet/lib/dart-e2e-g<N> head on the mirror must be the shared step's
# (ratchet ops/mirror-publish.ts) strip commit: first parent = a commit of THIS
# branch, a `Mirrors-Sha:` trailer naming that parent, no named-checks surface.
# The mirror's existing main (the pre-graph seed, no history shared with
# diene.all) stays pinned at main_sha until the owner's review of this node.
#
# NAMED_CHECKS_MIRROR_SHA=<sha> additionally requires a publish head that
# mirrors exactly <sha> (the `.3` claim: the mirror stands at the `.2` SHA).
# Until the first publish there is no head to judge; the check then proves only
# that the mirror is reachable and main is untouched, and says so.

cd "$(git rev-parse --show-toplevel)"
node="lib/dart-e2e"
subject="chore: strip diene-internal named checks for the mirror (owner rule 2026-10-30)"
main_sha="${NAMED_CHECKS_MIRROR_MAIN_SHA:-ea0b50b4a0b15801b31e2c78fb715a80810e8fe4}"
mirror="$(cat "$(dirname "$0")/mirror.repo")"
url="${NAMED_CHECKS_MIRROR_URL:-https://github.com/${mirror}.git}"
want="${NAMED_CHECKS_MIRROR_SHA:-}"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

heads="$(git ls-remote --heads "${url}")" || { echo "❌ mirror ${mirror} is not reachable at ${url}" >&2 && exit 1; }

main_now="$(awk '$2 == "refs/heads/main" { print $1 }' <<<"${heads}")"
[[ ${main_now} == "${main_sha}" ]] || fail "mirror main is ${main_now:-absent}, not the untouched ${main_sha}; main is the owner's until review"

refs="$(awk -v p="refs/heads/ratchet/${node}-g" 'index($2, p) == 1 && substr($2, length(p) + 1) ~ /^[0-9]+$/' <<<"${heads}")"

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

if [[ -n ${want} && ${matched} -ne 1 ]]; then fail "no ratchet/${node}-g* head mirrors ${want}"; fi
if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

if [[ -z ${refs} ]]; then
  echo "✅ mirror-topology: ${mirror} reachable, main untouched at ${main_sha}; no ratchet/${node}-g* publish yet, so no head to judge"
else
  echo "✅ mirror-topology: main untouched at ${main_sha}; every ratchet/${node}-g* head on ${mirror} is a strip commit of this branch${want:+, one mirrors ${want}}"
fi
