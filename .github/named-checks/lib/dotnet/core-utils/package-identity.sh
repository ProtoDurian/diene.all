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

if ! lib="$(evaluate Lib/Lib.csproj)"; then
  fail "Lib/Lib.csproj does not evaluate"
else
  [[ "$(prop "${lib}" PackageId)" == AtomiCloud.Diene.CoreUtils ]] || fail "Lib PackageId is not AtomiCloud.Diene.CoreUtils"
  [[ "$(prop "${lib}" AssemblyName)" == AtomiCloud.Diene.CoreUtils ]] || fail "Lib AssemblyName is not AtomiCloud.Diene.CoreUtils"
  [[ "$(prop "${lib}" IsPackable)" == true ]] || fail "Lib is not packable"
  [[ "$(prop "${lib}" RootNamespace)" == AtomiCloud.Diene.CoreUtils* ]] || fail "Lib RootNamespace leaves AtomiCloud.Diene.CoreUtils"
  want="AtomiCloud.Diene.Interfaces, AtomiCloud.Diene.Result"
  [[ "$(refs "${lib}" PackageReference)" == "${want}" ]] || fail "Lib PackageReferences are '$(refs "${lib}" PackageReference)', want '${want}'"
  [[ -z "$(refs "${lib}" ProjectReference)" ]] || fail "Lib ProjectReferences are '$(refs "${lib}" ProjectReference)', want none"
fi

if ! app="$(evaluate App/App.csproj)"; then
  fail "App/App.csproj does not evaluate"
elif [[ "$(prop "${app}" IsPackable)" != false ]]; then
  fail "App/App.csproj must stay IsPackable=false"
fi

helpers="$(git ls-files -- '*TestHelper*.csproj' | paste -sd' ' -)"
[[ -z ${helpers} ]] || fail "this package ships no TestHelper, but found: ${helpers}"

# Result and Interfaces must come from nuget.org, never a local feed or a sibling project
sources="$(yq -p=xml -o=json NuGet.config | jq -r '[.configuration.packageSources.add] | flatten | map(.["+@value"]) | join(" ")')"
[[ ${sources} == https://api.nuget.org/v3/index.json ]] || fail "NuGet.config sources are '${sources}', want nuget.org only"
yq -p=xml -o=json NuGet.config | jq -e '.configuration.packageSources | has("clear")' >/dev/null || fail "NuGet.config does not clear inherited sources"
if git ls-files -- '*.csproj' '*.props' '*.targets' | xargs grep -nE 'ProjectReference[^>]*([Rr]esult|[Ii]nterfaces)' 2>/dev/null; then
  fail "a project references a Result or Interfaces project instead of the published package"
fi

skills="$(git ls-files -- 'skills/*/SKILL.md' | cut -d/ -f2 | sort -u | paste -sd' ' -)"
[[ ${skills} == diene-dotnet-core-utils-usage ]] || fail "shipped skills are '${skills}', want diene-dotnet-core-utils-usage only"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-identity: AtomiCloud.Diene.CoreUtils only, no TestHelper, Result and Interfaces only from nuget.org, one usage skill"
