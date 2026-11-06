#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

# evaluated, so Directory.*.props overrides count
evaluate() {
  dotnet msbuild "$1" -getProperty:PackageId -getProperty:AssemblyName -getProperty:IsPackable \
    -getProperty:RootNamespace -getItem:PackageReference
}

prop() {
  jq -r --arg name "$2" '.Properties[$name] // ""' <<<"$1"
}

for pair in "Lib/Lib.csproj:AtomiCloud.Diene.Result" "TestHelper/TestHelper.csproj:AtomiCloud.Diene.Result.TestHelper"; do
  project="${pair%%:*}"
  want="${pair#*:}"
  eval_json="$(evaluate "${project}")" || { fail "${project} does not evaluate" && continue; }
  [[ "$(prop "${eval_json}" PackageId)" == "${want}" ]] || fail "${project} PackageId is not ${want}"
  [[ "$(prop "${eval_json}" AssemblyName)" == "${want}" ]] || fail "${project} AssemblyName is not ${want}"
  [[ "$(prop "${eval_json}" IsPackable)" == true ]] || fail "${project} is not packable"
  [[ "$(prop "${eval_json}" RootNamespace)" == AtomiCloud.Diene.Results* ]] || fail "${project} RootNamespace leaves AtomiCloud.Diene.Results"
  if [[ ${project} == Lib/Lib.csproj ]]; then
    deps="$(jq -r '[.Items.PackageReference[]?.Identity] | join(", ")' <<<"${eval_json}")"
    [[ -z ${deps} ]] || fail "${project} takes a runtime dependency: ${deps}"
  fi
done

if ! app="$(evaluate App/App.csproj)"; then
  fail "App/App.csproj does not evaluate"
elif [[ "$(prop "${app}" IsPackable)" != false ]]; then
  fail "App/App.csproj must stay IsPackable=false"
fi

skills="$(git ls-files -- 'skills/*/SKILL.md' | cut -d/ -f2 | sort -u | paste -sd' ' -)"
[[ ${skills} == diene-dotnet-result-usage ]] || fail "shipped skills are '${skills}', want diene-dotnet-result-usage only"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-identity: AtomiCloud.Diene.Result + .TestHelper, no runtime dependency, one usage skill"
