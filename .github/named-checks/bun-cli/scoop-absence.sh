#!/usr/bin/env bash
set -euo pipefail

# Scoop is dropped entirely: no SCOOP_BREW_TOKEN, no scoop manifest or
# GoReleaser scoops block, no Windows build target.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

# The declaration itself and machine-maintained history.
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!Changelog.old.md')

hits="$(git -c core.quotePath=false grep -n -i -e 'scoop' "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files still reference Scoop:"$'\n'"${hits}"

paths="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}" | grep -v '^.github/named-checks/' | grep -i 'scoop' || true)"
[[ -z ${paths} ]] || fail "Scoop paths still tracked:"$'\n'"${paths}"

goreleaser="$(git show "${tree}:.goreleaser.yaml")"
[[ "$(yq 'has("scoops")' <<<"${goreleaser}")" == false ]] || fail ".goreleaser.yaml still declares scoops"
[[ "$(yq '[.builds[]?.goos[]? | select(. == "windows")] | length' <<<"${goreleaser}")" == 0 ]] || fail ".goreleaser.yaml still builds for windows"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ scoop-absence: no Scoop token, path, manifest or Windows target"
