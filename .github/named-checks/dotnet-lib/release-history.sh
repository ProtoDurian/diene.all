#!/usr/bin/env bash
set -euo pipefail

# Every `release: <v>` commit on the mirror's default branch commits Version.props
# stamped to <v>, the single release stamp.

cd "$(git rev-parse --show-toplevel)"
mirror="$(cat "$(dirname "$0")/mirror.repo")"
url="${NAMED_CHECKS_MIRROR_URL:-https://github.com/${mirror}.git}"
ref="refs/named-checks/release-history"
trap 'git update-ref -d "${ref}" 2>/dev/null || true' EXIT

git fetch --quiet --no-tags "${url}" "+HEAD:${ref}" || { echo "❌ cannot fetch ${mirror}" >&2 && exit 1; }

releases=0
failed=0
while read -r sha subject; do
  version="${subject#release: }"
  releases=$((releases + 1))
  if ! git diff-tree --no-commit-id --name-only -r "${sha}" | grep -qx Version.props; then
    echo "❌ ${sha} (${subject}) does not commit Version.props" >&2
    failed=1
    continue
  fi
  stamped="$(git show "${sha}:Version.props" | xmlstarlet sel -t -v '/Project/PropertyGroup/Version')"
  if [[ ${stamped} != "${version}" ]]; then
    echo "❌ ${sha} (${subject}) stamps Version.props to ${stamped}" >&2
    failed=1
  fi
done < <(git log --format='%H %s' "${ref}" | grep -E '^[0-9a-f]+ release: [0-9]+\.[0-9]+\.[0-9]+$')

if [[ ${releases} -eq 0 ]]; then
  echo "❌ ${mirror} has no release commit" >&2
  exit 1
fi
if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ release-history: ${releases} release commit(s) on ${mirror} stamp Version.props"
