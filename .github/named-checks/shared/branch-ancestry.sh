#!/usr/bin/env bash
set -euo pipefail

# shared is cut from workspace: HEAD contains workspace's recorded .3 commit.

# shellcheck source=.github/named-checks/shared/parent.bash
source "$(dirname "$0")/parent.bash"
require_parent

if ! git merge-base --is-ancestor "${parent_sha}" HEAD; then
  echo "❌ HEAD does not contain workspace .3 ${parent_sha}; the branch is not cut from workspace" >&2
  exit 1
fi

echo "branch-ancestry: HEAD contains workspace .3 ${parent_sha}"
