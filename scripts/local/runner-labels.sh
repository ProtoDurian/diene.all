#!/usr/bin/env bash
set -euo pipefail

# No `runs-on` label in .github/workflows may end in -latest: GitHub moves it to a new image without a commit here.

root="$(git rev-parse --show-toplevel)"
cd "${root}"

fail=0
for file in .github/workflows/*.y*ml; do
  [ -e "${file}" ] || continue
  while IFS= read -r label; do
    [ -n "${label}" ] || continue
    echo "❌ ${file}: runs-on '${label}' ends in -latest; name the version (for example ubuntu-26.04)" >&2
    fail=1
  done < <(yq -r '.jobs[]?["runs-on"]? | .. | select(tag == "!!str") | select(test("-latest$"))' "${file}")
done
[ "${fail}" -eq 0 ] || exit 1
echo "✅ no runs-on label ends in -latest"
