#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

prop() {
  xmlstarlet sel -t -v "/Project/PropertyGroup/$2" "$1" 2>/dev/null || true
}

for pair in "Lib/Lib.csproj:AtomiCloud.Diene.Result" "TestHelper/TestHelper.csproj:AtomiCloud.Diene.Result.TestHelper"; do
  project="${pair%%:*}"
  want="${pair#*:}"
  [[ "$(prop "${project}" PackageId)" == "${want}" ]] || fail "${project} PackageId is not ${want}"
  [[ "$(prop "${project}" AssemblyName)" == "${want}" ]] || fail "${project} AssemblyName is not ${want}"
  [[ "$(prop "${project}" IsPackable)" == true ]] || fail "${project} is not packable"
done

for project in Lib/Lib.csproj TestHelper/TestHelper.csproj; do
  [[ "$(prop "${project}" RootNamespace)" == AtomiCloud.Diene.Results* ]] || fail "${project} RootNamespace leaves AtomiCloud.Diene.Results"
done

deps="$(xmlstarlet sel -t -v '//PackageReference/@Include' Lib/Lib.csproj 2>/dev/null || true)"
[[ -z ${deps} ]] || fail "Lib/Lib.csproj takes a runtime dependency: ${deps//$'\n'/, }"

[[ "$(prop App/App.csproj IsPackable)" == false ]] || fail "App/App.csproj must stay IsPackable=false"

skills="$(git ls-files -- 'skills/*/SKILL.md' | cut -d/ -f2 | sort -u | paste -sd' ' -)"
[[ ${skills} == diene-dotnet-result-usage ]] || fail "shipped skills are '${skills}', want diene-dotnet-result-usage only"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ package-identity: AtomiCloud.Diene.Result + .TestHelper, no runtime dependency, one usage skill"
