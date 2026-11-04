#!/usr/bin/env bash
set -euo pipefail

dir="$(dirname "$0")"
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${dir}/parent.sha")}"
replay_sha="${NAMED_CHECKS_REPLAY_SHA:-$(cat "${dir}/replay.sha")}"

for sha in "${parent_sha}" "${replay_sha}"; do
  git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${sha}" || true
  git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null || { echo "❌ commit ${sha} not found; fetch it first" >&2 && exit 1; }
done

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain shared .3 ${parent_sha}; the branch is not cut from shared" >&2
  exit 1
fi

if ! git merge-base --is-ancestor "${replay_sha}" HEAD; then
  echo "❌ HEAD does not contain the go-base line ${replay_sha}" >&2
  exit 1
fi

echo "✅ branch-parentage: HEAD contains shared .3 ${parent_sha} and the go-base line ${replay_sha}"
