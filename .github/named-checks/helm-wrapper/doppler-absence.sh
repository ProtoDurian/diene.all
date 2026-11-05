#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
tree="$(git write-tree)"
# Active payload = every tracked build/render input; prose and the checks themselves are not inputs.
EXCLUDE=(':!*.md' ':!docs/**' ':!.github/named-checks/**')
failed=0
fail() {
  echo "❌ $*" >&2
  failed=1
}

hits="$(git -c core.quotePath=false grep -n -i -I -e doppler -e sulfoxide-bromine "${tree}" -- . "${EXCLUDE[@]}" || true)"
[[ -z ${hits} ]] || fail "doppler or sulfoxide-bromine in active inputs:"$'\n'"${hits}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
while IFS= read -r path; do
  git show "${tree}:${path}" >"${work}/f"
  case "${path}" in
  *.yaml | *.yml) yq -o=json eval-all '[.. | select(tag == "!!map") | keys | .[]] + [.. | anchor | select(. != "")] + [.. | alias | select(. != "")]' "${work}/f" >"${work}/k" 2>/dev/null || {
    fail "${path} does not parse as YAML"
    continue
  } ;;
  *.json) jq '[paths | .[-1] | strings]' "${work}/f" >"${work}/k" 2>/dev/null || {
    fail "${path} does not parse as JSON"
    continue
  } ;;
  *.toml) yq -p toml -o=json '[.. | select(tag == "!!map") | keys | .[]]' "${work}/f" >"${work}/k" 2>/dev/null || {
    fail "${path} does not parse as TOML"
    continue
  } ;;
  esac
  if jq -s -e 'flatten | any(. == "sulfoxide-bromine")' "${work}/k" >/dev/null; then fail "${path} declares the sulfoxide-bromine key or alias"; fi
done < <(git -c core.quotePath=false ls-tree -r --name-only "${tree}" | grep -E '\.(ya?ml|json|toml)$' | grep -vE '^(docs/|\.github/named-checks/)|(^|/)templates/')

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ doppler-absence: no doppler token or sulfoxide-bromine key in the active payload"
