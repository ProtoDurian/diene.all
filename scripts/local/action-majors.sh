#!/usr/bin/env bash
set -euo pipefail

# Every trusted `uses:` in the workflows must be on a major tag at or above the one recorded in
# .github/action-majors.yaml. Red when one is below it, used but unlisted, or the list is empty/unreadable.

root="$(git rev-parse --show-toplevel)"
cd "${root}"

list=".github/action-majors.yaml"
dlint="dlint.yaml"
trusted="$(yq -r '.checks["action-pins"].trustedPattern' "${dlint}")"
dir="$(yq -r '.checks["action-pins"].workflowsDir' "${dlint}")"

recorded="$(yq -r '.majors | to_entries | .[] | .key + " " + (.value | tostring)' "${list}" 2>/dev/null)" || recorded=""
[ -n "${recorded}" ] || {
  echo "❌ ${list} is empty or unreadable" >&2
  exit 1
}

fail=0
while read -r rname rmajor; do
  [[ ${rmajor} =~ ^[0-9]+$ ]] || {
    echo "❌ ${list}: ${rname} has a non-integer major '${rmajor}'" >&2
    fail=1
  }
done <<<"${recorded}"
[ "${fail}" -eq 0 ] || exit 1
while read -r uses; do
  [[ ${uses} =~ ${trusted} ]] || continue
  name="$(cut -d/ -f1,2 <<<"${uses%@*}")"
  ref="${uses##*@}"
  major="$(awk -v n="${name}" '$1 == n { print $2 }' <<<"${recorded}")"
  if [ -z "${major}" ]; then
    echo "❌ ${uses}: trusted action is used but not listed in ${list}" >&2
    fail=1
  elif [[ ! ${ref} =~ ^v([0-9]+)$ ]] || [ "${BASH_REMATCH[1]}" -lt "${major}" ]; then
    echo "❌ ${uses}: below the recorded major v${major} in ${list}" >&2
    fail=1
  fi
done < <(yq -r '.. | select(tag == "!!map" and has("uses")) | .uses' "${dir}"/*.y*ml | sort -u)

[ "${fail}" -eq 0 ] || exit 1
echo "✅ Trusted actions are on their recorded majors"
