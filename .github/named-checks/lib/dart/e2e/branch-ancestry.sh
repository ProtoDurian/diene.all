#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ dart-lib .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then git fetch --quiet --no-tags --unshallow origin || true; fi

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain dart-lib .3 ${parent_sha}; the branch is not cut from dart-lib" >&2
  exit 1
fi

# split so this file does not match itself
token='diene_dart''_lib'
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
hits="$( (
  git grep -I -l -F "${token}" "${tree}" -- . ':!.github/named-checks/dart-lib/' | sed "s/^${tree}://" || true
  git ls-tree -r --name-only "${tree}" | grep -F "${token}" | grep -v '^\.github/named-checks/dart-lib/' || true
) | LC_ALL=C sort -u)"
if [[ -n ${hits} ]]; then
  echo "❌ residual ${token} token outside .github/named-checks/dart-lib/:"$'\n'"${hits}" >&2
  exit 1
fi

echo "✅ branch-ancestry: HEAD contains dart-lib .3 ${parent_sha}; no residual ${token} token"
