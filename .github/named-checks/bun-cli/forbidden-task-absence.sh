#!/usr/bin/env bash
set -euo pipefail

# M16/R7 and M5: no `run:bin` or `dev` task (`task preview` replaces run:bin),
# and GoReleaser alone publishes the GitHub release, so no
# @semantic-release/github plugin and the releaser does not publish one either.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

FORBIDDEN_TASKS=(run:bin dev)

# The resolved task surface, includes and all, from the checked tree.
git archive "${tree}" | tar -x -C "${work}"
(cd "${work}" && task --list-all --json) >"${work}/tasks.json" 2>"${work}/task.err" || {
  fail "task --list-all failed: $(head -5 "${work}/task.err")"
  exit 1
}
[[ "$(jq '.tasks | length' "${work}/tasks.json")" -gt 0 ]] || fail "task --list-all resolved no tasks"
for t in "${FORBIDDEN_TASKS[@]}"; do
  if jq -e --arg t "${t}" '[.tasks[].name, (.tasks[].aliases // [])[]] | index($t)' "${work}/tasks.json" >/dev/null; then
    fail "forbidden task '${t}' is defined"
  fi
done
# Positive control: the replacement task exists, so the lookup is not vacuous.
jq -e '[.tasks[].name] | index("preview")' "${work}/tasks.json" >/dev/null || fail "control: task 'preview' is missing"

hits="$(git -c core.quotePath=false grep -n -F '@semantic-release/github' "${tree}" -- . ':!.github/named-checks/**' ':!Changelog.md' || true)"
[[ -z ${hits} ]] || fail "@semantic-release/github is still referenced:"$'\n'"${hits}"
[[ "$(git show "${tree}:release.yaml" | yq '.release.github')" == false ]] || fail "release.yaml: release.github must be false (GoReleaser owns the GitHub release)"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ forbidden-task-absence: no ${FORBIDDEN_TASKS[*]} task, no @semantic-release/github, release.github false"
