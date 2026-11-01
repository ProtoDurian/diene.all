#!/usr/bin/env bash
set -euo pipefail

# dotnet-base is cut from shared and replays its own .NET history: HEAD contains
# shared's recorded .3 commit (parent.sha) and the replayed dotnet-base line
# (replay.sha, the branch tip the go-live graph was seeded with).

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
  echo "❌ HEAD does not contain the replayed dotnet-base line ${replay_sha}" >&2
  exit 1
fi

echo "✅ branch-parentage: HEAD contains shared .3 ${parent_sha} and the dotnet-base replay ${replay_sha}"
