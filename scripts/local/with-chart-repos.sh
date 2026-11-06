#!/usr/bin/env bash
set -euo pipefail

# Run a command with the https repositories named in chart/Chart.yaml registered in a throwaway Helm repo config.
[ "$#" -eq 0 ] && echo "❌ usage: with-chart-repos.sh <command...>" >&2 && exit 1
repos="$(mktemp -d)"
trap 'rm -rf "${repos}"' EXIT
export HELM_REPOSITORY_CONFIG="${repos}/repositories.yaml" HELM_REPOSITORY_CACHE="${repos}/cache"
index=0
while IFS= read -r url; do
  index=$((index + 1))
  helm repo add "chart-dep-${index}" "${url}" >/dev/null
done < <(yq -r '.dependencies[].repository | select(test("^https?://"))' chart/Chart.yaml)
"$@"
