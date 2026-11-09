#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
tree="$(git write-tree)"
failed=0
fail() {
  echo "❌ $*" >&2
  failed=1
}

files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

built="$(grep -E '^(chart/files/config/|\.chart-checks/|dist/|reports/|coverage/|result(-[^/]*)?$|result/|\.direnv/|node_modules/)|(^|/)probe-report\.json$' <<<"${files}" || true)"
[[ -z ${built} ]] || fail "build outputs are tracked:"$'\n'"${built}"

# The only committed archives are the Chart.lock dependencies (goal: vendored upstream deps).
want="$(git show "${tree}:chart/Chart.lock" | yq -r '.dependencies[] | "chart/charts/" + .name + "-" + .version + ".tgz"' | LC_ALL=C sort)"
have="$(grep -E '\.(tgz|tar\.gz|tar|zip)$' <<<"${files}" | LC_ALL=C sort || true)"
[[ ${have} == "${want}" ]] || fail "tracked archives differ from Chart.lock dependencies: have [${have//$'\n'/ }], want [${want//$'\n'/ }]"

for p in chart/files/config/application.yaml .chart-checks/stamp dist/x probe-report.json; do
  git check-ignore -q --no-index "${p}" || fail "${p} is not gitignored"
done

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ no-vendored-artifacts: no build output tracked; archives == Chart.lock dependencies"
