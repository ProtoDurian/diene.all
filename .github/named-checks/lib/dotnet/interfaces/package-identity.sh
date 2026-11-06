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
    -getProperty:RootNamespace -getItem:PackageReference -getItem:ProjectReference
}

prop() {
  jq -r --arg name "$2" '.Properties[$name] // ""' <<<"$1"
}

refs() {
  jq -r --arg item "$2" '[.Items[$item][]?.Identity] | sort | join(", ")' <<<"$1"
}

check_project() {
  local project=$1 want=$2 packages=$3 projects=$4 eval_json
  eval_json="$(evaluate "${project}")" || { fail "${project} does not evaluate" && return; }
  [[ "$(prop "${eval_json}" PackageId)" == "${want}" ]] || fail "${project} PackageId is not ${want}"
  [[ "$(prop "${eval_json}" AssemblyName)" == "${want}" ]] || fail "${project} AssemblyName is not ${want}"
  [[ "$(prop "${eval_json}" IsPackable)" == true ]] || fail "${project} is not packable"
  [[ "$(prop "${eval_json}" RootNamespace)" == AtomiCloud.Diene.Interfaces* ]] || fail "${project} RootNamespace leaves AtomiCloud.Diene.Interfaces"
  [[ "$(refs "${eval_json}" PackageReference)" == "${packages}" ]] || fail "${project} PackageReferences are '$(refs "${eval_json}" PackageReference)', want '${packages}'"
  [[ "$(refs "${eval_json}" ProjectReference)" == "${projects}" ]] || fail "${project} ProjectReferences are '$(refs "${eval_json}" ProjectReference)', want '${projects}'"
}

check_project Lib/Lib.csproj AtomiCloud.Diene.Interfaces "AtomiCloud.Diene.Result" ""
check_project TestHelper/TestHelper.csproj AtomiCloud.Diene.Interfaces.TestHelper \
  "AtomiCloud.Diene.Result.TestHelper, FluentAssertions" "../Lib/Lib.csproj"

if ! app="$(evaluate App/App.csproj)"; then
  fail "App/App.csproj does not evaluate"
elif [[ "$(prop "${app}" IsPackable)" != false ]]; then
  fail "App/App.csproj must stay IsPackable=false"
fi

# Result must come from nuget.org, never a local feed or a sibling project
sources="$(yq -p=xml -o=json NuGet.config | jq -r '[.configuration.packageSources.add] | flatten | map(.["+@value"]) | join(" ")')"
[[ ${sources} == https://api.nuget.org/v3/index.json ]] || fail "NuGet.config sources are '${sources}', want nuget.org only"
yq -p=xml -o=json NuGet.config | jq -e '.configuration.packageSources | has("clear")' >/dev/null || fail "NuGet.config does not clear inherited sources"
if git ls-files -- '*.csproj' '*.props' '*.targets' | xargs grep -nE 'ProjectReference[^>]*[Rr]esult' 2>/dev/null; then
  fail "a project references a Result project instead of the published package"
fi

skills="$(git ls-files -- 'skills/*/SKILL.md' | cut -d/ -f2 | sort -u | paste -sd' ' -)"
[[ ${skills} == diene-dotnet-interfaces-usage ]] || fail "shipped skills are '${skills}', want diene-dotnet-interfaces-usage only"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-identity: AtomiCloud.Diene.Interfaces + .TestHelper, Result only from nuget.org, one usage skill"
